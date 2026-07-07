use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use serde::Serialize;
use serde_json::json;

use crate::alerts::{Alert, AlertEngine};
use crate::config::AlertConfig;
use crate::metrics::SystemMetrics;

const HISTORY_TAIL_LINES: usize = 200;

#[derive(Debug, Clone, Serialize)]
pub struct SystemSnapshot {
    pub schema_version: u8,
    pub kind: &'static str,
    pub captured_at_unix: u64,
    pub hostname: String,
    pub os_name: String,
    pub os_version: String,
    pub kernel_version: String,
    pub uptime_seconds: u64,
    pub cpu_usage_percent: f32,
    pub memory: MemorySnapshot,
    pub disks: Vec<DiskSnapshot>,
    pub network: NetworkSnapshot,
    pub gpus: Vec<GpuSnapshot>,
    pub batteries: Vec<BatterySnapshot>,
    pub sensors: Vec<SensorSnapshot>,
    pub process_count: usize,
    pub top_processes: Vec<ProcessSnapshot>,
    pub alerts: Vec<Alert>,
}

#[derive(Debug, Clone, Serialize)]
pub struct MemorySnapshot {
    pub total: u64,
    pub used: u64,
    pub available: u64,
    pub usage_percent: f32,
    pub swap_total: u64,
    pub swap_used: u64,
    pub swap_usage_percent: f32,
}

#[derive(Debug, Clone, Serialize)]
pub struct DiskSnapshot {
    pub mount_point: String,
    pub fs_type: String,
    pub used: u64,
    pub total: u64,
    pub available: u64,
    pub usage_percent: f32,
    pub read_rate: u64,
    pub write_rate: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct NetworkSnapshot {
    pub total_rx_rate: u64,
    pub total_tx_rate: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct GpuSnapshot {
    pub name: String,
    pub usage_percent: f32,
    pub vram_used: u64,
    pub vram_total: u64,
    pub temperature: Option<f32>,
    pub power_watts: Option<f32>,
}

#[derive(Debug, Clone, Serialize)]
pub struct BatterySnapshot {
    pub name: String,
    pub status: String,
    pub capacity_percent: Option<f32>,
    pub health_percent: Option<f32>,
}

#[derive(Debug, Clone, Serialize)]
pub struct SensorSnapshot {
    pub label: String,
    pub temperature: Option<f32>,
    pub critical: Option<f32>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProcessSnapshot {
    pub pid: u32,
    pub name: String,
    pub cpu_usage: f32,
    pub memory: u64,
    pub status: String,
}

impl SystemSnapshot {
    pub fn from_metrics(metrics: &SystemMetrics, alert_config: &AlertConfig) -> Self {
        let mut alert_engine = AlertEngine::new();
        let alerts = alert_engine.evaluate(metrics, alert_config, Instant::now());
        Self::from_metrics_with_alerts(metrics, alerts)
    }

    pub fn from_metrics_with_alerts(metrics: &SystemMetrics, alerts: Vec<Alert>) -> Self {
        Self {
            schema_version: 1,
            kind: "system_snapshot",
            captured_at_unix: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|duration| duration.as_secs())
                .unwrap_or(0),
            hostname: metrics.hostname.clone(),
            os_name: metrics.os_name.clone(),
            os_version: metrics.os_version.clone(),
            kernel_version: metrics.kernel_version.clone(),
            uptime_seconds: metrics.uptime,
            cpu_usage_percent: metrics.cpu.global_usage,
            memory: MemorySnapshot {
                total: metrics.memory.total_mem,
                used: metrics.memory.used_mem,
                available: metrics.memory.available_mem,
                usage_percent: metrics.memory.mem_usage_percent,
                swap_total: metrics.memory.total_swap,
                swap_used: metrics.memory.used_swap,
                swap_usage_percent: metrics.memory.swap_usage_percent,
            },
            disks: metrics
                .disk
                .disks
                .iter()
                .map(|disk| DiskSnapshot {
                    mount_point: disk.mount_point.clone(),
                    fs_type: disk.fs_type.clone(),
                    used: disk.used_space,
                    total: disk.total_space,
                    available: disk.available_space,
                    usage_percent: disk.usage_percent,
                    read_rate: disk.read_rate,
                    write_rate: disk.write_rate,
                })
                .collect(),
            network: NetworkSnapshot {
                total_rx_rate: metrics.network.total_rx_rate,
                total_tx_rate: metrics.network.total_tx_rate,
            },
            gpus: metrics
                .gpu
                .devices
                .iter()
                .map(|gpu| GpuSnapshot {
                    name: gpu.name.clone(),
                    usage_percent: gpu.gpu_usage,
                    vram_used: gpu.vram_used,
                    vram_total: gpu.vram_total,
                    temperature: gpu.temperature_edge.or(gpu.temperature_junction),
                    power_watts: gpu.power_watts,
                })
                .collect(),
            batteries: metrics
                .battery
                .batteries
                .iter()
                .map(|battery| BatterySnapshot {
                    name: battery.name.clone(),
                    status: battery.status.clone(),
                    capacity_percent: battery.capacity_percent,
                    health_percent: battery.health_percent,
                })
                .collect(),
            sensors: metrics
                .sensors
                .components
                .iter()
                .map(|sensor| SensorSnapshot {
                    label: sensor.label.clone(),
                    temperature: sensor.temperature,
                    critical: sensor.critical,
                })
                .collect(),
            process_count: metrics.processes.total_count,
            top_processes: metrics
                .processes
                .processes
                .iter()
                .take(20)
                .map(|process| ProcessSnapshot {
                    pid: process.pid,
                    name: process.name.clone(),
                    cpu_usage: process.cpu_usage,
                    memory: process.memory,
                    status: process.status.clone(),
                })
                .collect(),
            alerts,
        }
    }
}

#[derive(Debug, Serialize)]
struct HistoryRecord<'a> {
    schema_version: u8,
    kind: &'static str,
    snapshot: &'a SystemSnapshot,
}

pub fn write_json_snapshot(path: &Path, snapshot: &SystemSnapshot) -> Result<(), ExportError> {
    let content = serde_json::to_string_pretty(snapshot).map_err(ExportError::Json)?;
    write_text(path, &content)
}

pub fn write_csv_snapshot(path: &Path, snapshot: &SystemSnapshot) -> Result<(), ExportError> {
    write_text(path, &snapshot_to_csv(snapshot))
}

pub fn append_history_snapshot(
    path: &Path,
    snapshot: &SystemSnapshot,
    retention_samples: usize,
) -> Result<(), ExportError> {
    if let Some(parent) = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        fs::create_dir_all(parent).map_err(ExportError::Io)?;
    }

    let record = HistoryRecord {
        schema_version: 1,
        kind: "system_snapshot",
        snapshot,
    };
    let line = serde_json::to_string(&record).map_err(ExportError::Json)?;
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .map_err(ExportError::Io)?;
    writeln!(file, "{line}").map_err(ExportError::Io)?;

    enforce_jsonl_retention(path, retention_samples)
}

pub fn write_incident_bundle(
    dir: &Path,
    snapshot: &SystemSnapshot,
    history_path: Option<&Path>,
) -> Result<(), ExportError> {
    fs::create_dir_all(dir).map_err(ExportError::Io)?;

    write_json_snapshot(&dir.join("snapshot.json"), snapshot)?;
    write_csv_snapshot(&dir.join("summary.csv"), snapshot)?;
    write_text(&dir.join("top_processes.csv"), &top_processes_csv(snapshot))?;
    write_text(&dir.join("diagnostics.json"), &diagnostics_json(snapshot)?)?;

    let mut files = vec![
        "snapshot.json",
        "summary.csv",
        "top_processes.csv",
        "diagnostics.json",
        "manifest.json",
    ];
    if let Some(path) = history_path.filter(|path| path.exists()) {
        let tail = history_tail(path, HISTORY_TAIL_LINES)?;
        if !tail.is_empty() {
            write_text(&dir.join("history_tail.jsonl"), &tail)?;
            files.push("history_tail.jsonl");
        }
    }

    write_text(
        &dir.join("manifest.json"),
        &manifest_json(snapshot, &files)?,
    )?;
    Ok(())
}

pub fn history_path(configured: Option<&Path>) -> PathBuf {
    configured
        .map(PathBuf::from)
        .unwrap_or_else(default_history_path)
}

fn default_history_path() -> PathBuf {
    if cfg!(target_os = "windows") {
        if let Some(appdata) = env::var_os("APPDATA") {
            return PathBuf::from(appdata).join("RustTop").join("history.jsonl");
        }
    } else if cfg!(target_os = "macos") {
        if let Some(home) = env::var_os("HOME") {
            return PathBuf::from(home)
                .join("Library")
                .join("Application Support")
                .join("RustTop")
                .join("history.jsonl");
        }
    } else if let Some(state_home) = env::var_os("XDG_STATE_HOME") {
        return PathBuf::from(state_home)
            .join("rust_top")
            .join("history.jsonl");
    } else if let Some(home) = env::var_os("HOME") {
        return PathBuf::from(home)
            .join(".local")
            .join("state")
            .join("rust_top")
            .join("history.jsonl");
    }

    PathBuf::from("rust_top_history.jsonl")
}

fn write_text(path: &Path, content: &str) -> Result<(), ExportError> {
    if let Some(parent) = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        fs::create_dir_all(parent).map_err(ExportError::Io)?;
    }
    fs::write(path, content).map_err(ExportError::Io)
}

fn enforce_jsonl_retention(path: &Path, retention_samples: usize) -> Result<(), ExportError> {
    if retention_samples == 0 {
        fs::write(path, "").map_err(ExportError::Io)?;
        return Ok(());
    }

    let content = fs::read_to_string(path).map_err(ExportError::Io)?;
    let lines: Vec<&str> = content.lines().collect();
    if lines.len() <= retention_samples {
        return Ok(());
    }

    let start = lines.len() - retention_samples;
    let mut retained = lines[start..].join("\n");
    retained.push('\n');
    fs::write(path, retained).map_err(ExportError::Io)
}

fn top_processes_csv(snapshot: &SystemSnapshot) -> String {
    let mut content = String::from("pid,name,cpu_usage,memory,status\n");
    for process in &snapshot.top_processes {
        content.push_str(&process.pid.to_string());
        content.push(',');
        content.push_str(&csv_escape(&process.name));
        content.push(',');
        content.push_str(&format!("{:.2}", process.cpu_usage));
        content.push(',');
        content.push_str(&process.memory.to_string());
        content.push(',');
        content.push_str(&csv_escape(&process.status));
        content.push('\n');
    }
    content
}

fn diagnostics_json(snapshot: &SystemSnapshot) -> Result<String, ExportError> {
    serde_json::to_string_pretty(&json!({
        "schema_version": 1,
        "kind": "rusttop_diagnostics",
        "captured_at_unix": snapshot.captured_at_unix,
        "host": {
            "hostname": snapshot.hostname,
            "os_name": snapshot.os_name,
            "os_version": snapshot.os_version,
            "kernel_version": snapshot.kernel_version,
            "uptime_seconds": snapshot.uptime_seconds,
        },
        "counts": {
            "processes": snapshot.process_count,
            "disks": snapshot.disks.len(),
            "gpus": snapshot.gpus.len(),
            "batteries": snapshot.batteries.len(),
            "sensors": snapshot.sensors.len(),
            "alerts": snapshot.alerts.len(),
        },
    }))
    .map_err(ExportError::Json)
}

fn manifest_json(snapshot: &SystemSnapshot, files: &[&str]) -> Result<String, ExportError> {
    serde_json::to_string_pretty(&json!({
        "schema_version": 1,
        "kind": "rusttop_incident_bundle",
        "captured_at_unix": snapshot.captured_at_unix,
        "hostname": snapshot.hostname,
        "files": files,
        "privacy": "Contains local host metrics and process names captured by RustTop.",
    }))
    .map_err(ExportError::Json)
}

fn history_tail(path: &Path, max_lines: usize) -> Result<String, ExportError> {
    if max_lines == 0 {
        return Ok(String::new());
    }

    let content = fs::read_to_string(path).map_err(ExportError::Io)?;
    let lines: Vec<&str> = content.lines().collect();
    let start = lines.len().saturating_sub(max_lines);
    let mut tail = lines[start..].join("\n");
    if !tail.is_empty() {
        tail.push('\n');
    }
    Ok(tail)
}

pub fn snapshot_to_csv(snapshot: &SystemSnapshot) -> String {
    let rows = [
        ("captured_at_unix", snapshot.captured_at_unix.to_string()),
        ("hostname", snapshot.hostname.clone()),
        ("os_name", snapshot.os_name.clone()),
        ("uptime_seconds", snapshot.uptime_seconds.to_string()),
        (
            "cpu_usage_percent",
            format!("{:.2}", snapshot.cpu_usage_percent),
        ),
        ("memory_used", snapshot.memory.used.to_string()),
        ("memory_total", snapshot.memory.total.to_string()),
        (
            "network_rx_rate",
            snapshot.network.total_rx_rate.to_string(),
        ),
        (
            "network_tx_rate",
            snapshot.network.total_tx_rate.to_string(),
        ),
        ("process_count", snapshot.process_count.to_string()),
    ];

    let mut content = String::from("metric,value\n");
    for (key, value) in rows {
        content.push_str(key);
        content.push(',');
        content.push_str(&csv_escape(&value));
        content.push('\n');
    }
    content
}

fn csv_escape(value: &str) -> String {
    let escaped_value = if starts_with_spreadsheet_formula(value) {
        format!("'{value}")
    } else {
        value.to_string()
    };

    if escaped_value.contains([',', '"', '\n']) {
        format!("\"{}\"", escaped_value.replace('"', "\"\""))
    } else {
        escaped_value
    }
}

fn starts_with_spreadsheet_formula(value: &str) -> bool {
    matches!(
        value.trim_start().chars().next(),
        Some('=' | '+' | '-' | '@')
    )
}

#[derive(Debug)]
pub enum ExportError {
    Io(std::io::Error),
    Json(serde_json::Error),
}

impl std::fmt::Display for ExportError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ExportError::Io(source) => write!(f, "failed to write export: {source}"),
            ExportError::Json(source) => write!(f, "failed to serialize snapshot: {source}"),
        }
    }
}

impl std::error::Error for ExportError {}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::{csv_escape, enforce_jsonl_retention, history_tail};
    use crate::alerts::{Alert, AlertSeverity, AlertUnit};
    use crate::metrics::process::SortField;
    use crate::metrics::SystemMetrics;

    #[test]
    fn csv_escape_quotes_values_when_needed() {
        assert_eq!(csv_escape("simple"), "simple");
        assert_eq!(csv_escape("a,b"), "\"a,b\"");
        assert_eq!(csv_escape("a\"b"), "\"a\"\"b\"");
    }

    #[test]
    fn csv_escape_neutralizes_formula_prefixes() {
        assert_eq!(csv_escape("=2+2"), "'=2+2");
        assert_eq!(csv_escape("+SUM(A1:A2)"), "'+SUM(A1:A2)");
        assert_eq!(csv_escape(" @cmd"), "' @cmd");
    }

    #[test]
    fn jsonl_retention_keeps_latest_lines() {
        let path = temp_path("history_retention");
        fs::write(&path, "one\ntwo\nthree\nfour\n").expect("history fixture");

        enforce_jsonl_retention(&path, 2).expect("retention applied");

        assert_eq!(fs::read_to_string(&path).expect("history"), "three\nfour\n");
        let _ = fs::remove_file(path);
    }

    #[test]
    fn history_tail_keeps_latest_lines() {
        let path = temp_path("history_tail");
        fs::write(&path, "one\ntwo\nthree\n").expect("history fixture");

        assert_eq!(history_tail(&path, 2).expect("tail"), "two\nthree\n");

        let _ = fs::remove_file(path);
    }

    #[test]
    fn snapshot_can_use_sustained_alerts_from_app_state() {
        let metrics = SystemMetrics::new(false, SortField::Cpu, false);
        let alerts = vec![Alert {
            key: "cpu".to_string(),
            label: "CPU".to_string(),
            value: 95.0,
            threshold: 90.0,
            unit: AlertUnit::Percent,
            severity: AlertSeverity::Warning,
            active_seconds: 42,
        }];

        let snapshot = super::SystemSnapshot::from_metrics_with_alerts(&metrics, alerts);

        assert_eq!(snapshot.alerts.len(), 1);
        assert_eq!(snapshot.alerts[0].key, "cpu");
        assert_eq!(snapshot.alerts[0].active_seconds, 42);
    }

    #[test]
    fn snapshot_schema_is_versioned() {
        let metrics = SystemMetrics::new(false, SortField::Cpu, false);

        let snapshot = super::SystemSnapshot::from_metrics_with_alerts(&metrics, Vec::new());

        assert_eq!(snapshot.schema_version, 1);
        assert_eq!(snapshot.kind, "system_snapshot");
    }

    fn temp_path(name: &str) -> std::path::PathBuf {
        std::env::temp_dir().join(format!(
            "rust_top_{name}_{}_{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("clock after epoch")
                .as_nanos()
        ))
    }
}
