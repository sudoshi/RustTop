use std::fmt::Write as FmtWrite;
use std::io::{BufRead, BufReader, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::json;

use crate::alerts::AlertEngine;
use crate::config::RuntimeOptions;
use crate::export::SystemSnapshot;
use crate::metrics::SystemMetrics;

#[derive(Debug, Clone)]
pub struct ApiServerOptions {
    pub address: SocketAddr,
    pub token: Option<String>,
}

impl ApiServerOptions {
    pub fn from_parts(address: &str, token: Option<String>) -> Result<Self, ApiError> {
        let address: SocketAddr = address.parse().map_err(ApiError::InvalidAddress)?;
        let token = token.and_then(|value| {
            let value = value.trim().to_string();
            (!value.is_empty()).then_some(value)
        });

        if token.is_none() {
            return Err(ApiError::TokenRequired(address));
        }

        Ok(Self { address, token })
    }
}

#[derive(Debug)]
struct HttpRequest {
    method: String,
    path: String,
    authorization: Option<String>,
}

pub fn run_api_server(options: ApiServerOptions, runtime: RuntimeOptions) -> Result<(), ApiError> {
    let listener = TcpListener::bind(options.address).map_err(ApiError::Io)?;
    let bound_address = listener.local_addr().map_err(ApiError::Io)?;
    eprintln!("RustTop API listening on http://{bound_address}");
    let snapshot_cache = start_snapshot_sampler(runtime);

    for stream in listener.incoming() {
        match stream {
            Ok(mut stream) => {
                if let Err(error) = handle_connection(&mut stream, &options, &snapshot_cache) {
                    eprintln!("{error}");
                }
            }
            Err(error) => eprintln!("failed to accept API connection: {error}"),
        }
    }

    Ok(())
}

fn start_snapshot_sampler(runtime: RuntimeOptions) -> Arc<Mutex<SystemSnapshot>> {
    let initial_snapshot = {
        let mut metrics = SystemMetrics::new(
            runtime.panels.gpu,
            runtime.default_sort.clone(),
            runtime.sort_ascending,
        );
        let mut alert_engine = AlertEngine::new();
        collect_snapshot(&mut metrics, &mut alert_engine, &runtime)
    };
    let snapshot_cache = Arc::new(Mutex::new(initial_snapshot));
    let sampler_cache = Arc::clone(&snapshot_cache);

    thread::spawn(move || {
        let interval = runtime.refresh_interval.max(Duration::from_millis(250));
        let mut metrics = SystemMetrics::new(
            runtime.panels.gpu,
            runtime.default_sort.clone(),
            runtime.sort_ascending,
        );
        let mut alert_engine = AlertEngine::new();

        loop {
            thread::sleep(interval);
            let snapshot = collect_snapshot(&mut metrics, &mut alert_engine, &runtime);
            match sampler_cache.lock() {
                Ok(mut cached) => {
                    *cached = snapshot;
                }
                Err(error) => {
                    eprintln!("API snapshot cache poisoned: {error}");
                    break;
                }
            }
        }
    });

    snapshot_cache
}

fn handle_connection(
    stream: &mut TcpStream,
    options: &ApiServerOptions,
    snapshot_cache: &Arc<Mutex<SystemSnapshot>>,
) -> Result<(), ApiError> {
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .map_err(ApiError::Io)?;
    stream
        .set_write_timeout(Some(Duration::from_secs(5)))
        .map_err(ApiError::Io)?;

    let Some(request) = read_request(stream)? else {
        return Ok(());
    };
    let head_only = request.method == "HEAD";

    if request.method != "GET" && request.method != "HEAD" {
        return write_response(
            stream,
            "405 Method Not Allowed",
            "application/json",
            &json!({"schema_version": 1, "error": "method_not_allowed"}).to_string(),
            head_only,
            None,
        );
    }

    let path = request.path.split('?').next().unwrap_or("/");
    if path != "/health" && !is_authorized(&request, options.token.as_deref()) {
        return write_response(
            stream,
            "401 Unauthorized",
            "application/json",
            &json!({"schema_version": 1, "error": "unauthorized"}).to_string(),
            head_only,
            Some("WWW-Authenticate: Bearer realm=\"RustTop API\"\r\n"),
        );
    }

    match path {
        "/" => write_response(
            stream,
            "200 OK",
            "application/json",
            &api_index_json(),
            head_only,
            None,
        ),
        "/health" => write_response(
            stream,
            "200 OK",
            "application/json",
            &health_json(),
            head_only,
            None,
        ),
        "/api/v1/snapshot" => {
            let snapshot = latest_snapshot(snapshot_cache)?;
            let body = serde_json::to_string(&snapshot).map_err(ApiError::Json)?;
            write_response(stream, "200 OK", "application/json", &body, head_only, None)
        }
        "/api/v1/alerts" => {
            let snapshot = latest_snapshot(snapshot_cache)?;
            let body = serde_json::to_string(&json!({
                "schema_version": 1,
                "kind": "alerts",
                "alerts": snapshot.alerts,
            }))
            .map_err(ApiError::Json)?;
            write_response(stream, "200 OK", "application/json", &body, head_only, None)
        }
        "/metrics" => {
            let snapshot = latest_snapshot(snapshot_cache)?;
            write_response(
                stream,
                "200 OK",
                "text/plain; version=0.0.4; charset=utf-8",
                &prometheus_snapshot(&snapshot),
                head_only,
                None,
            )
        }
        _ => write_response(
            stream,
            "404 Not Found",
            "application/json",
            &json!({"schema_version": 1, "error": "not_found"}).to_string(),
            head_only,
            None,
        ),
    }
}

fn collect_snapshot(
    metrics: &mut SystemMetrics,
    alert_engine: &mut AlertEngine,
    runtime: &RuntimeOptions,
) -> SystemSnapshot {
    metrics.refresh();
    let alerts = alert_engine.evaluate(metrics, &runtime.alerts, Instant::now());
    SystemSnapshot::from_metrics_with_alerts(metrics, alerts)
}

fn latest_snapshot(
    snapshot_cache: &Arc<Mutex<SystemSnapshot>>,
) -> Result<SystemSnapshot, ApiError> {
    snapshot_cache
        .lock()
        .map(|snapshot| snapshot.clone())
        .map_err(|_| ApiError::StatePoisoned)
}

fn read_request(stream: &TcpStream) -> Result<Option<HttpRequest>, ApiError> {
    let mut reader = BufReader::new(stream.try_clone().map_err(ApiError::Io)?);
    let mut first_line = String::new();
    if reader.read_line(&mut first_line).map_err(ApiError::Io)? == 0 {
        return Ok(None);
    }

    let mut parts = first_line.split_whitespace();
    let method = parts.next().unwrap_or_default().to_string();
    let path = parts.next().unwrap_or("/").to_string();
    let mut authorization = None;

    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).map_err(ApiError::Io)? == 0 {
            break;
        }
        let line = line.trim_end_matches(['\r', '\n']);
        if line.is_empty() {
            break;
        }
        if let Some((name, value)) = line.split_once(':') {
            if name.trim().eq_ignore_ascii_case("authorization") {
                authorization = Some(value.trim().to_string());
            }
        }
    }

    Ok(Some(HttpRequest {
        method,
        path,
        authorization,
    }))
}

fn is_authorized(request: &HttpRequest, token: Option<&str>) -> bool {
    match token {
        None => false,
        Some(token) => request
            .authorization
            .as_deref()
            .is_some_and(|value| value == format!("Bearer {token}")),
    }
}

fn write_response(
    stream: &mut TcpStream,
    status: &str,
    content_type: &str,
    body: &str,
    head_only: bool,
    extra_headers: Option<&str>,
) -> Result<(), ApiError> {
    let extra_headers = extra_headers.unwrap_or_default();
    write!(
        stream,
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n{extra_headers}\r\n",
        body.len()
    )
    .map_err(ApiError::Io)?;
    if !head_only {
        stream.write_all(body.as_bytes()).map_err(ApiError::Io)?;
    }
    Ok(())
}

fn health_json() -> String {
    json!({
        "schema_version": 1,
        "kind": "health",
        "status": "ok",
        "version": env!("CARGO_PKG_VERSION"),
    })
    .to_string()
}

fn api_index_json() -> String {
    json!({
        "schema_version": 1,
        "kind": "api_index",
        "endpoints": [
            "/health",
            "/api/v1/snapshot",
            "/api/v1/alerts",
            "/metrics"
        ],
    })
    .to_string()
}

pub fn prometheus_snapshot(snapshot: &SystemSnapshot) -> String {
    let mut output = String::new();
    write_metric(
        &mut output,
        "rusttop_cpu_usage_percent",
        "Current global CPU usage percent.",
        snapshot.cpu_usage_percent as f64,
    );
    write_metric(
        &mut output,
        "rusttop_memory_usage_percent",
        "Current memory usage percent.",
        snapshot.memory.usage_percent as f64,
    );
    write_metric(
        &mut output,
        "rusttop_swap_usage_percent",
        "Current swap usage percent.",
        snapshot.memory.swap_usage_percent as f64,
    );
    write_metric(
        &mut output,
        "rusttop_network_rx_bytes_per_second",
        "Aggregate network receive rate.",
        snapshot.network.total_rx_rate as f64,
    );
    write_metric(
        &mut output,
        "rusttop_network_tx_bytes_per_second",
        "Aggregate network transmit rate.",
        snapshot.network.total_tx_rate as f64,
    );
    write_metric(
        &mut output,
        "rusttop_process_count",
        "Total visible process count.",
        snapshot.process_count as f64,
    );
    write_metric(
        &mut output,
        "rusttop_active_alerts",
        "Current active alert count.",
        snapshot.alerts.len() as f64,
    );

    output.push_str("# HELP rusttop_disk_usage_percent Disk usage percent by mount point.\n");
    output.push_str("# TYPE rusttop_disk_usage_percent gauge\n");
    for disk in &snapshot.disks {
        let _ = writeln!(
            output,
            "rusttop_disk_usage_percent{{mount=\"{}\",fs_type=\"{}\"}} {:.2}",
            prometheus_label(&disk.mount_point),
            prometheus_label(&disk.fs_type),
            disk.usage_percent
        );
    }

    output.push_str("# HELP rusttop_gpu_usage_percent GPU usage percent by device.\n");
    output.push_str("# TYPE rusttop_gpu_usage_percent gauge\n");
    for gpu in &snapshot.gpus {
        let _ = writeln!(
            output,
            "rusttop_gpu_usage_percent{{device=\"{}\"}} {:.2}",
            prometheus_label(&gpu.name),
            gpu.usage_percent
        );
    }

    output
}

fn write_metric(output: &mut String, name: &str, help: &str, value: f64) {
    let _ = writeln!(output, "# HELP {name} {help}");
    let _ = writeln!(output, "# TYPE {name} gauge");
    let _ = writeln!(output, "{name} {value:.2}");
}

fn prometheus_label(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('\n', "\\n")
        .replace('"', "\\\"")
}

#[derive(Debug)]
pub enum ApiError {
    InvalidAddress(std::net::AddrParseError),
    TokenRequired(SocketAddr),
    Io(std::io::Error),
    Json(serde_json::Error),
    StatePoisoned,
}

impl std::fmt::Display for ApiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ApiError::InvalidAddress(source) => write!(f, "invalid API address: {source}"),
            ApiError::TokenRequired(address) => write!(
                f,
                "API address {address} requires --api-token before serving host metrics"
            ),
            ApiError::Io(source) => write!(f, "API server error: {source}"),
            ApiError::Json(source) => write!(f, "failed to serialize API response: {source}"),
            ApiError::StatePoisoned => write!(f, "API snapshot cache is unavailable"),
        }
    }
}

impl std::error::Error for ApiError {}

#[cfg(test)]
mod tests {
    use super::{
        is_authorized, prometheus_label, prometheus_snapshot, ApiServerOptions, HttpRequest,
    };
    use crate::export::SystemSnapshot;
    use crate::metrics::process::SortField;
    use crate::metrics::SystemMetrics;

    #[test]
    fn api_requires_token_even_on_loopback() {
        assert!(ApiServerOptions::from_parts("127.0.0.1:9977", None).is_err());
    }

    #[test]
    fn api_rejects_non_loopback_without_token() {
        assert!(ApiServerOptions::from_parts("0.0.0.0:9977", None).is_err());
    }

    #[test]
    fn api_allows_non_loopback_with_token() {
        let options = ApiServerOptions::from_parts("0.0.0.0:9977", Some("secret".to_string()))
            .expect("remote bind with token");

        assert_eq!(options.token.as_deref(), Some("secret"));
    }

    #[test]
    fn api_authorization_requires_exact_bearer_token() {
        let request = HttpRequest {
            method: "GET".to_string(),
            path: "/api/v1/snapshot".to_string(),
            authorization: Some("Bearer secret".to_string()),
        };

        assert!(is_authorized(&request, Some("secret")));
        assert!(!is_authorized(&request, Some("wrong")));
        assert!(!is_authorized(&request, None));
    }

    #[test]
    fn prometheus_output_includes_core_metrics() {
        let metrics = SystemMetrics::new(false, SortField::Cpu, false);
        let snapshot = SystemSnapshot::from_metrics_with_alerts(&metrics, Vec::new());

        let output = prometheus_snapshot(&snapshot);

        assert!(output.contains("rusttop_cpu_usage_percent"));
        assert!(output.contains("rusttop_memory_usage_percent"));
        assert!(output.contains("rusttop_process_count"));
    }

    #[test]
    fn prometheus_labels_escape_special_characters() {
        assert_eq!(prometheus_label("a\"b\\c\n"), "a\\\"b\\\\c\\n");
    }
}
