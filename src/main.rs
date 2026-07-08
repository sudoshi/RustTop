mod alerts;
mod api;
mod config;
mod export;
mod metrics;
mod theme;
mod ui;

use alerts::AlertEngine;
use api::{run_api_server, ApiServerOptions};
use clap::Parser;
use config::{Cli, RuntimeOptions, RustTopConfig};
use export::{
    append_history_snapshot, history_path, write_csv_snapshot, write_incident_bundle,
    write_json_snapshot, write_json_snapshot_line, ExportError, SystemSnapshot,
};
use iced::window;
use iced::{Settings, Size, Task};
use metrics::SystemMetrics;
use std::io::{self, BufWriter};
use std::thread;
use std::time::Instant;
use ui::app::RustTop;

fn main() -> iced::Result {
    let cli = Cli::parse();
    let stream_mode = cli.stream_json;
    let one_shot_mode = cli.export_json.is_some()
        || cli.export_csv.is_some()
        || cli.record_history
        || cli.incident_bundle.is_some();
    let api_mode = cli.api;
    let requested_config_path = RustTopConfig::resolve_path(cli.config.as_deref());
    let (config, config_path) = match RustTopConfig::load_or_create(cli.config.as_deref()) {
        Ok(config) => (config, Some(requested_config_path)),
        Err(error) => {
            eprintln!("{error}");
            if cli.config.is_some() || one_shot_mode || api_mode || stream_mode {
                std::process::exit(1);
            }
            eprintln!("Starting with defaults.");
            (RustTopConfig::default(), None)
        }
    };
    let runtime = RuntimeOptions::from_config_and_cli(config, &cli, config_path);

    if stream_mode {
        if let Err(error) = stream_json_snapshots(runtime) {
            eprintln!("{error}");
            std::process::exit(1);
        }

        return Ok(());
    }

    if one_shot_mode {
        let mut metrics = SystemMetrics::new(
            runtime.panels.gpu,
            runtime.default_sort.clone(),
            runtime.sort_ascending,
        );
        metrics.refresh();
        let snapshot = SystemSnapshot::from_metrics(&metrics, &runtime.alerts);
        let mut had_error = false;

        if let Some(path) = cli.export_json.as_deref() {
            if let Err(error) = write_json_snapshot(path, &snapshot) {
                eprintln!("{error}");
                had_error = true;
            }
        }

        if let Some(path) = cli.export_csv.as_deref() {
            if let Err(error) = write_csv_snapshot(path, &snapshot) {
                eprintln!("{error}");
                had_error = true;
            }
        }

        if cli.record_history {
            let path = history_path(runtime.history.path.as_deref());
            if let Err(error) =
                append_history_snapshot(&path, &snapshot, runtime.history.retention_samples)
            {
                eprintln!("{error}");
                had_error = true;
            }
        }

        if let Some(path) = cli.incident_bundle.as_deref() {
            let history_path = history_path(runtime.history.path.as_deref());
            if let Err(error) = write_incident_bundle(path, &snapshot, Some(history_path.as_path()))
            {
                eprintln!("{error}");
                had_error = true;
            }
        }

        if had_error {
            std::process::exit(1);
        }

        return Ok(());
    }

    if api_mode || runtime.api.enabled {
        let address = cli.api_addr.as_deref().unwrap_or(&runtime.api.address);
        let token = cli.api_token.clone().or_else(|| runtime.api.token.clone());
        let options = match ApiServerOptions::from_parts(address, token) {
            Ok(options) => options,
            Err(error) => {
                eprintln!("{error}");
                std::process::exit(1);
            }
        };

        if let Err(error) = run_api_server(options, runtime) {
            eprintln!("{error}");
            std::process::exit(1);
        }

        return Ok(());
    }

    let icon =
        window::icon::from_file_data(include_bytes!("../assets/icons/rust_top.png"), None).ok();

    let mut window_settings = window::Settings {
        size: Size::new(runtime.window.width, runtime.window.height),
        min_size: Some(Size::new(
            runtime.window.min_width,
            runtime.window.min_height,
        )),
        platform_specific: platform_specific_window_settings(),
        ..Default::default()
    };
    window_settings.icon = icon;

    iced::application("RustTop — System Monitor", RustTop::update, RustTop::view)
        .subscription(RustTop::subscription)
        .theme(RustTop::theme)
        .settings(Settings {
            id: Some("rust_top".to_string()),
            ..Settings::default()
        })
        .window(window_settings)
        .antialiasing(true)
        .run_with(move || {
            let app = RustTop::new(runtime);
            (app, Task::none())
        })
}

fn stream_json_snapshots(runtime: RuntimeOptions) -> Result<(), ExportError> {
    let mut metrics = SystemMetrics::new(
        runtime.panels.gpu,
        runtime.default_sort.clone(),
        runtime.sort_ascending,
    );
    let mut alert_engine = AlertEngine::new();
    let stdout = io::stdout();
    let mut writer = BufWriter::new(stdout.lock());

    loop {
        metrics.refresh();
        let alerts = alert_engine.evaluate(&metrics, &runtime.alerts, Instant::now());
        let snapshot = SystemSnapshot::from_metrics_with_alerts(&metrics, alerts);
        write_json_snapshot_line(&mut writer, &snapshot)?;
        thread::sleep(runtime.refresh_interval);
    }
}

#[cfg(target_os = "linux")]
fn platform_specific_window_settings() -> window::settings::PlatformSpecific {
    window::settings::PlatformSpecific {
        application_id: "rust_top".to_string(),
        ..Default::default()
    }
}

#[cfg(not(target_os = "linux"))]
fn platform_specific_window_settings() -> window::settings::PlatformSpecific {
    window::settings::PlatformSpecific::default()
}
