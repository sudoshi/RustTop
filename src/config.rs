use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

use clap::Parser;
use serde::{Deserialize, Serialize};

use crate::metrics::process::SortField;

const DEFAULT_REFRESH_INTERVAL_MS: u64 = 500;
const MIN_REFRESH_INTERVAL_MS: u64 = 250;
const MAX_REFRESH_INTERVAL_MS: u64 = 60_000;

#[derive(Debug, Clone, Parser)]
#[command(author, version, about)]
pub struct Cli {
    /// Path to a RustTop TOML config file.
    #[arg(long)]
    pub config: Option<PathBuf>,

    /// Refresh interval in milliseconds.
    #[arg(long, value_name = "MS")]
    pub interval: Option<u64>,

    /// Disable GPU collection and hide the GPU panel.
    #[arg(long)]
    pub no_gpu: bool,

    /// Write one system snapshot as JSON and exit.
    #[arg(long, value_name = "PATH")]
    pub export_json: Option<PathBuf>,

    /// Write one summary snapshot as CSV and exit.
    #[arg(long, value_name = "PATH")]
    pub export_csv: Option<PathBuf>,

    /// Append one system snapshot to JSONL history and exit.
    #[arg(long)]
    pub record_history: bool,

    /// Write an incident bundle directory and exit.
    #[arg(long, value_name = "DIR")]
    pub incident_bundle: Option<PathBuf>,

    /// Start the local HTTP API in headless mode.
    #[arg(long)]
    pub api: bool,

    /// Address for --api, for example 127.0.0.1:9977.
    #[arg(long, value_name = "ADDR")]
    pub api_addr: Option<String>,

    /// Bearer token required by API data endpoints.
    #[arg(long, value_name = "TOKEN")]
    pub api_token: Option<String>,
}

#[derive(Debug, Clone)]
pub struct RuntimeOptions {
    pub refresh_interval: Duration,
    pub panels: PanelVisibility,
    pub layout_preset: LayoutPreset,
    pub theme: String,
    pub compact_mode: bool,
    pub gpu_allowed: bool,
    pub history: HistoryConfig,
    pub alerts: AlertConfig,
    pub api: ApiConfig,
    pub default_sort: SortField,
    pub sort_ascending: bool,
    pub window: WindowConfig,
    pub process_columns: ProcessColumnVisibility,
    pub config: RustTopConfig,
    pub config_path: Option<PathBuf>,
}

impl RuntimeOptions {
    pub fn from_config_and_cli(
        config: RustTopConfig,
        cli: &Cli,
        config_path: Option<PathBuf>,
    ) -> Self {
        let interval_ms = cli
            .interval
            .unwrap_or(config.refresh.interval_ms)
            .clamp(MIN_REFRESH_INTERVAL_MS, MAX_REFRESH_INTERVAL_MS);

        let layout_preset = LayoutPreset::from_config_value(&config.appearance.layout_preset);
        let gpu_allowed = !cli.no_gpu;
        let mut panels = layout_preset.apply_to(config.panels.clone());
        if !gpu_allowed {
            panels.gpu = false;
        }

        Self {
            refresh_interval: Duration::from_millis(interval_ms),
            panels,
            layout_preset,
            theme: config.appearance.theme.clone(),
            compact_mode: config.appearance.compact_mode,
            gpu_allowed,
            history: config.history.clone(),
            alerts: config.alerts.clone(),
            api: config.api.clone(),
            default_sort: parse_sort_field(&config.process_table.default_sort),
            sort_ascending: config.process_table.sort_ascending,
            window: config.window.clone(),
            process_columns: ProcessColumnVisibility::from_names(&config.process_table.columns),
            config,
            config_path,
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct RustTopConfig {
    pub refresh: RefreshConfig,
    pub panels: PanelVisibility,
    pub appearance: AppearanceConfig,
    pub history: HistoryConfig,
    pub alerts: AlertConfig,
    pub api: ApiConfig,
    pub window: WindowConfig,
    pub process_table: ProcessTableConfig,
}

impl RustTopConfig {
    pub fn load_or_create(path: Option<&Path>) -> Result<Self, ConfigError> {
        let path = Self::resolve_path(path);
        if path.exists() {
            return Self::load_from_path(&path);
        }

        let config = Self::default();
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            fs::create_dir_all(parent).map_err(|source| ConfigError::CreateDir {
                path: parent.to_path_buf(),
                source,
            })?;
        }

        config.write_to_path(&path)?;
        Ok(config)
    }

    pub fn resolve_path(path: Option<&Path>) -> PathBuf {
        path.map(PathBuf::from).unwrap_or_else(default_config_path)
    }

    pub fn load_from_path(path: &Path) -> Result<Self, ConfigError> {
        let content = fs::read_to_string(path).map_err(|source| ConfigError::Read {
            path: path.to_path_buf(),
            source,
        })?;
        toml::from_str(&content).map_err(|source| ConfigError::Parse {
            path: path.to_path_buf(),
            source,
        })
    }

    pub fn write_to_path(&self, path: &Path) -> Result<(), ConfigError> {
        let content = toml::to_string_pretty(self).map_err(ConfigError::Serialize)?;
        fs::write(path, content).map_err(|source| ConfigError::Write {
            path: path.to_path_buf(),
            source,
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct RefreshConfig {
    pub interval_ms: u64,
}

impl Default for RefreshConfig {
    fn default() -> Self {
        Self {
            interval_ms: DEFAULT_REFRESH_INTERVAL_MS,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct PanelVisibility {
    pub cpu: bool,
    pub memory: bool,
    pub gpu: bool,
    pub network: bool,
    pub disk: bool,
    pub battery: bool,
    pub sensors: bool,
    pub processes: bool,
}

impl Default for PanelVisibility {
    fn default() -> Self {
        Self {
            cpu: true,
            memory: true,
            gpu: true,
            network: true,
            disk: true,
            battery: true,
            sensors: true,
            processes: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AppearanceConfig {
    pub theme: String,
    pub layout_preset: String,
    pub compact_mode: bool,
}

impl Default for AppearanceConfig {
    fn default() -> Self {
        Self {
            theme: "tokyo-night".to_string(),
            layout_preset: "balanced".to_string(),
            compact_mode: false,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LayoutPreset {
    Balanced,
    FocusProcesses,
    Minimal,
}

impl LayoutPreset {
    pub fn from_config_value(value: &str) -> Self {
        match value.to_ascii_lowercase().as_str() {
            "focus-processes" | "processes" | "process-focus" => LayoutPreset::FocusProcesses,
            "minimal" | "compact" => LayoutPreset::Minimal,
            _ => LayoutPreset::Balanced,
        }
    }

    pub fn config_value(self) -> &'static str {
        match self {
            LayoutPreset::Balanced => "balanced",
            LayoutPreset::FocusProcesses => "focus-processes",
            LayoutPreset::Minimal => "minimal",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            LayoutPreset::Balanced => "Balanced",
            LayoutPreset::FocusProcesses => "Process Focus",
            LayoutPreset::Minimal => "Minimal",
        }
    }

    pub fn next(self) -> Self {
        match self {
            LayoutPreset::Balanced => LayoutPreset::FocusProcesses,
            LayoutPreset::FocusProcesses => LayoutPreset::Minimal,
            LayoutPreset::Minimal => LayoutPreset::Balanced,
        }
    }

    pub fn apply_to(self, panels: PanelVisibility) -> PanelVisibility {
        match self {
            LayoutPreset::Balanced => panels,
            LayoutPreset::FocusProcesses => PanelVisibility {
                cpu: true,
                memory: true,
                gpu: false,
                network: true,
                disk: false,
                battery: false,
                sensors: false,
                processes: true,
            },
            LayoutPreset::Minimal => PanelVisibility {
                cpu: true,
                memory: true,
                gpu: false,
                network: true,
                disk: false,
                battery: false,
                sensors: false,
                processes: false,
            },
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct WindowConfig {
    pub width: f32,
    pub height: f32,
    pub min_width: f32,
    pub min_height: f32,
}

impl Default for WindowConfig {
    fn default() -> Self {
        Self {
            width: 1200.0,
            height: 800.0,
            min_width: 800.0,
            min_height: 500.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ProcessTableConfig {
    pub default_sort: String,
    pub sort_ascending: bool,
    pub saved_filters: Vec<String>,
    pub columns: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct HistoryConfig {
    pub enabled: bool,
    pub path: Option<PathBuf>,
    pub interval_seconds: u64,
    pub retention_samples: usize,
}

impl Default for HistoryConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            path: None,
            interval_seconds: 60,
            retention_samples: 1_440,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ApiConfig {
    pub enabled: bool,
    pub address: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub token: Option<String>,
}

impl Default for ApiConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            address: "127.0.0.1:9977".to_string(),
            token: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AlertConfig {
    pub enabled: bool,
    pub desktop_notifications: bool,
    pub min_duration_seconds: u64,
    pub cpu_percent: f32,
    pub memory_percent: f32,
    pub swap_percent: f32,
    #[serde(alias = "disk_percent")]
    pub disk_used_percent: f32,
    pub sensor_warm_c: f32,
    #[serde(alias = "temperature_celsius")]
    pub sensor_critical_c: f32,
    pub gpu_temperature_c: f32,
    pub gpu_vram_percent: f32,
    pub battery_low_percent: f32,
    pub battery_health_percent: f32,
}

impl Default for AlertConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            desktop_notifications: false,
            min_duration_seconds: 10,
            cpu_percent: 90.0,
            memory_percent: 90.0,
            swap_percent: 50.0,
            disk_used_percent: 90.0,
            sensor_warm_c: 75.0,
            sensor_critical_c: 90.0,
            gpu_temperature_c: 85.0,
            gpu_vram_percent: 90.0,
            battery_low_percent: 15.0,
            battery_health_percent: 70.0,
        }
    }
}

impl Default for ProcessTableConfig {
    fn default() -> Self {
        Self {
            default_sort: "cpu".to_string(),
            sort_ascending: false,
            saved_filters: Vec::new(),
            columns: default_process_columns(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessColumnVisibility {
    pub pid: bool,
    pub name: bool,
    pub cpu: bool,
    pub memory: bool,
    pub status: bool,
}

impl ProcessColumnVisibility {
    pub fn from_names(names: &[String]) -> Self {
        if names.is_empty() {
            return Self::default();
        }

        let has = |name: &str| {
            names
                .iter()
                .any(|candidate| candidate.eq_ignore_ascii_case(name))
        };

        Self {
            pid: has("pid"),
            name: true,
            cpu: has("cpu"),
            memory: has("memory") || has("mem"),
            status: has("status"),
        }
    }

    pub fn to_names(&self) -> Vec<String> {
        let mut names = Vec::new();
        if self.pid {
            names.push("pid".to_string());
        }
        names.push("name".to_string());
        if self.cpu {
            names.push("cpu".to_string());
        }
        if self.memory {
            names.push("memory".to_string());
        }
        if self.status {
            names.push("status".to_string());
        }
        names
    }

    pub fn next_preset(&self) -> Self {
        if *self == ProcessColumnVisibility::compact() {
            ProcessColumnVisibility::diagnostic()
        } else if *self == ProcessColumnVisibility::diagnostic() {
            ProcessColumnVisibility::default()
        } else {
            ProcessColumnVisibility::compact()
        }
    }

    pub fn label(&self) -> &'static str {
        if *self == ProcessColumnVisibility::compact() {
            "Compact"
        } else if *self == ProcessColumnVisibility::diagnostic() {
            "Diag"
        } else {
            "Full"
        }
    }

    fn compact() -> Self {
        Self {
            pid: false,
            name: true,
            cpu: true,
            memory: true,
            status: false,
        }
    }

    fn diagnostic() -> Self {
        Self {
            pid: true,
            name: true,
            cpu: false,
            memory: false,
            status: true,
        }
    }
}

impl Default for ProcessColumnVisibility {
    fn default() -> Self {
        Self {
            pid: true,
            name: true,
            cpu: true,
            memory: true,
            status: true,
        }
    }
}

fn default_process_columns() -> Vec<String> {
    ProcessColumnVisibility::default().to_names()
}

#[derive(Debug)]
pub enum ConfigError {
    CreateDir {
        path: PathBuf,
        source: std::io::Error,
    },
    Read {
        path: PathBuf,
        source: std::io::Error,
    },
    Write {
        path: PathBuf,
        source: std::io::Error,
    },
    Parse {
        path: PathBuf,
        source: toml::de::Error,
    },
    Serialize(toml::ser::Error),
}

impl std::fmt::Display for ConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConfigError::CreateDir { path, source } => {
                write!(
                    f,
                    "failed to create config directory {}: {source}",
                    path.display()
                )
            }
            ConfigError::Read { path, source } => {
                write!(f, "failed to read config {}: {source}", path.display())
            }
            ConfigError::Write { path, source } => {
                write!(f, "failed to write config {}: {source}", path.display())
            }
            ConfigError::Parse { path, source } => {
                write!(f, "failed to parse config {}: {source}", path.display())
            }
            ConfigError::Serialize(source) => write!(f, "failed to serialize config: {source}"),
        }
    }
}

impl std::error::Error for ConfigError {}

pub fn default_config_path() -> PathBuf {
    if cfg!(target_os = "windows") {
        if let Some(appdata) = env::var_os("APPDATA") {
            return PathBuf::from(appdata).join("RustTop").join("config.toml");
        }
    } else if cfg!(target_os = "macos") {
        if let Some(home) = env::var_os("HOME") {
            return PathBuf::from(home)
                .join("Library")
                .join("Application Support")
                .join("RustTop")
                .join("config.toml");
        }
    } else if let Some(config_home) = env::var_os("XDG_CONFIG_HOME") {
        return PathBuf::from(config_home)
            .join("rust_top")
            .join("config.toml");
    } else if let Some(home) = env::var_os("HOME") {
        return PathBuf::from(home)
            .join(".config")
            .join("rust_top")
            .join("config.toml");
    }

    PathBuf::from("rust_top_config.toml")
}

fn parse_sort_field(value: &str) -> SortField {
    match value.to_ascii_lowercase().as_str() {
        "pid" => SortField::Pid,
        "name" => SortField::Name,
        "memory" | "mem" => SortField::Memory,
        "status" => SortField::Status,
        _ => SortField::Cpu,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cli_overrides_refresh_interval_and_gpu_panel() {
        let config = RustTopConfig::default();
        let cli = Cli {
            config: None,
            interval: Some(1_000),
            no_gpu: true,
            export_json: None,
            export_csv: None,
            record_history: false,
            incident_bundle: None,
            api: false,
            api_addr: None,
            api_token: None,
        };

        let runtime = RuntimeOptions::from_config_and_cli(config, &cli, None);

        assert_eq!(runtime.refresh_interval, Duration::from_millis(1_000));
        assert!(!runtime.panels.gpu);
        assert!(!runtime.gpu_allowed);
    }

    #[test]
    fn refresh_interval_is_clamped() {
        let config = RustTopConfig::default();
        let cli = Cli {
            config: None,
            interval: Some(1),
            no_gpu: false,
            export_json: None,
            export_csv: None,
            record_history: false,
            incident_bundle: None,
            api: false,
            api_addr: None,
            api_token: None,
        };

        let runtime = RuntimeOptions::from_config_and_cli(config, &cli, None);

        assert_eq!(
            runtime.refresh_interval,
            Duration::from_millis(MIN_REFRESH_INTERVAL_MS)
        );
    }

    #[test]
    fn config_toml_maps_expected_fields() {
        let config: RustTopConfig = toml::from_str(
            r#"
            [refresh]
            interval_ms = 750

            [panels]
            gpu = false
            network = false
            sensors = false

            [window]
            width = 1440.0
            height = 900.0

            [process_table]
            default_sort = "memory"
            sort_ascending = true
            saved_filters = ["rust", "cpu>50"]
            columns = ["name", "cpu", "memory"]

            [appearance]
            theme = "nord"
            layout_preset = "minimal"
            compact_mode = true

            [history]
            enabled = true
            interval_seconds = 30
            retention_samples = 12

            [alerts]
            enabled = true
            desktop_notifications = false
            min_duration_seconds = 5
            cpu_percent = 91.0
            memory_percent = 92.0
            swap_percent = 60.0
            disk_used_percent = 93.0
            sensor_warm_c = 70.0
            sensor_critical_c = 89.0
            gpu_temperature_c = 84.0
            gpu_vram_percent = 88.0
            battery_low_percent = 20.0
            battery_health_percent = 75.0

            [api]
            enabled = true
            address = "127.0.0.1:9999"
            token = "local-token"
            "#,
        )
        .expect("valid config");

        assert_eq!(config.refresh.interval_ms, 750);
        assert!(!config.panels.gpu);
        assert!(!config.panels.network);
        assert!(!config.panels.sensors);
        assert_eq!(config.window.width, 1440.0);
        assert_eq!(
            parse_sort_field(&config.process_table.default_sort),
            SortField::Memory
        );
        assert!(config.process_table.sort_ascending);
        assert_eq!(config.process_table.saved_filters, vec!["rust", "cpu>50"]);
        assert_eq!(config.process_table.columns, vec!["name", "cpu", "memory"]);
        assert_eq!(config.appearance.theme, "nord");
        assert_eq!(
            LayoutPreset::from_config_value(&config.appearance.layout_preset),
            LayoutPreset::Minimal
        );
        assert!(config.appearance.compact_mode);
        assert!(config.history.enabled);
        assert_eq!(config.history.interval_seconds, 30);
        assert_eq!(config.history.retention_samples, 12);
        assert!(config.alerts.enabled);
        assert!(!config.alerts.desktop_notifications);
        assert_eq!(config.alerts.min_duration_seconds, 5);
        assert_eq!(config.alerts.cpu_percent, 91.0);
        assert_eq!(config.alerts.memory_percent, 92.0);
        assert_eq!(config.alerts.swap_percent, 60.0);
        assert_eq!(config.alerts.disk_used_percent, 93.0);
        assert_eq!(config.alerts.sensor_warm_c, 70.0);
        assert_eq!(config.alerts.sensor_critical_c, 89.0);
        assert_eq!(config.alerts.gpu_temperature_c, 84.0);
        assert_eq!(config.alerts.gpu_vram_percent, 88.0);
        assert_eq!(config.alerts.battery_low_percent, 20.0);
        assert_eq!(config.alerts.battery_health_percent, 75.0);
        assert!(config.api.enabled);
        assert_eq!(config.api.address, "127.0.0.1:9999");
        assert_eq!(config.api.token.as_deref(), Some("local-token"));
    }

    #[test]
    fn alert_config_accepts_legacy_threshold_names() {
        let config: RustTopConfig = toml::from_str(
            r#"
            [alerts]
            disk_percent = 94.0
            temperature_celsius = 86.0
            "#,
        )
        .expect("legacy alert config");

        assert_eq!(config.alerts.disk_used_percent, 94.0);
        assert_eq!(config.alerts.sensor_critical_c, 86.0);
    }

    #[test]
    fn runtime_options_apply_layout_preset_and_appearance() {
        let config = RustTopConfig {
            appearance: AppearanceConfig {
                theme: "high-contrast".to_string(),
                layout_preset: "focus-processes".to_string(),
                compact_mode: true,
            },
            ..RustTopConfig::default()
        };
        let cli = Cli {
            config: None,
            interval: None,
            no_gpu: false,
            export_json: None,
            export_csv: None,
            record_history: false,
            incident_bundle: None,
            api: false,
            api_addr: None,
            api_token: None,
        };

        let runtime = RuntimeOptions::from_config_and_cli(config, &cli, None);

        assert_eq!(runtime.layout_preset, LayoutPreset::FocusProcesses);
        assert_eq!(runtime.theme, "high-contrast");
        assert!(runtime.compact_mode);
        assert!(runtime.panels.processes);
        assert!(!runtime.panels.gpu);
        assert!(!runtime.panels.disk);
    }

    #[test]
    fn no_gpu_cli_wins_after_layout_preset_application() {
        let config = RustTopConfig {
            appearance: AppearanceConfig {
                layout_preset: "balanced".to_string(),
                ..AppearanceConfig::default()
            },
            panels: PanelVisibility {
                gpu: true,
                ..PanelVisibility::default()
            },
            ..RustTopConfig::default()
        };
        let cli = Cli {
            config: None,
            interval: None,
            no_gpu: true,
            export_json: None,
            export_csv: None,
            record_history: false,
            incident_bundle: None,
            api: false,
            api_addr: None,
            api_token: None,
        };

        let runtime = RuntimeOptions::from_config_and_cli(config, &cli, None);

        assert!(!runtime.panels.gpu);
        assert!(!runtime.gpu_allowed);
    }

    #[test]
    fn process_column_visibility_parses_and_round_trips_names() {
        let columns = ProcessColumnVisibility::from_names(&[
            "name".to_string(),
            "cpu".to_string(),
            "mem".to_string(),
        ]);

        assert!(!columns.pid);
        assert!(columns.name);
        assert!(columns.cpu);
        assert!(columns.memory);
        assert!(!columns.status);
        assert_eq!(columns.to_names(), vec!["name", "cpu", "memory"]);
    }

    #[test]
    fn process_column_visibility_cycles_stable_presets() {
        let full = ProcessColumnVisibility::default();
        let compact = full.next_preset();
        let diagnostic = compact.next_preset();

        assert_eq!(full.label(), "Full");
        assert_eq!(compact.label(), "Compact");
        assert_eq!(diagnostic.label(), "Diag");
        assert_eq!(diagnostic.next_preset(), full);
    }

    #[test]
    fn load_or_create_writes_missing_config() {
        let dir = env::temp_dir().join(format!(
            "rust_top_config_test_{}_{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock after epoch")
                .as_nanos()
        ));
        let path = dir.join("config.toml");

        let config = RustTopConfig::load_or_create(Some(&path)).expect("config created");

        assert_eq!(config.refresh.interval_ms, DEFAULT_REFRESH_INTERVAL_MS);
        assert!(path.exists());

        let _ = fs::remove_dir_all(dir);
    }
}
