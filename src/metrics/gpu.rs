use std::fs;
use std::path::{Path, PathBuf};

use nvml_wrapper::Nvml;

const HISTORY_SIZE: usize = 120;

#[derive(Debug, Clone)]
pub enum GpuVendor {
    Amd,
    Nvidia,
}

#[derive(Debug, Clone)]
struct AmdDevice {
    card_path: PathBuf,
    hwmon_path: Option<PathBuf>,
}

#[derive(Debug, Clone)]
enum GpuBackend {
    Amd(AmdDevice),
    Nvidia { device_index: u32 },
}

#[derive(Debug, Clone)]
pub struct GpuDeviceMetrics {
    pub vendor: GpuVendor,
    pub name: String,
    pub gpu_usage: f32,
    pub vram_total: u64,
    pub vram_used: u64,
    pub vram_usage_percent: f32,
    pub temperature_edge: Option<f32>,
    pub temperature_junction: Option<f32>,
    pub temperature_memory: Option<f32>,
    pub gpu_clock_mhz: Option<u64>,
    pub vram_clock_mhz: Option<u64>,
    pub power_watts: Option<f32>,
    pub power_cap_watts: Option<f32>,
    pub fan_rpm: Option<u64>,
    pub fan_max_rpm: Option<u64>,
    pub gpu_history: Vec<f32>,
    pub vram_history: Vec<f32>,
    pub temp_history: Vec<f32>,
    pub power_history: Vec<f32>,
    backend: GpuBackend,
}

pub struct GpuMetrics {
    pub available: bool,
    pub devices: Vec<GpuDeviceMetrics>,
    nvml: Option<Nvml>,
}

// Manual Debug because Nvml doesn't implement Debug
impl std::fmt::Debug for GpuMetrics {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("GpuMetrics")
            .field("available", &self.available)
            .field("devices", &self.devices)
            .field("nvml", &self.nvml.is_some())
            .finish()
    }
}

// Manual Clone because Nvml doesn't implement Clone
impl Clone for GpuMetrics {
    fn clone(&self) -> Self {
        Self {
            available: self.available,
            devices: self.devices.clone(),
            // Re-init NVML for the clone if we had it
            nvml: Nvml::init().ok(),
        }
    }
}

impl GpuMetrics {
    pub fn new() -> Self {
        let mut device_metrics = Vec::new();

        // Discover AMD GPUs via sysfs
        let amd_devices = discover_amd_gpus();
        for dev in amd_devices {
            device_metrics.push(GpuDeviceMetrics::new_amd(dev));
        }

        // Discover NVIDIA GPUs via NVML
        let nvml = Nvml::init().ok();
        if let Some(ref nvml_handle) = nvml {
            if let Ok(count) = nvml_handle.device_count() {
                for i in 0..count {
                    if let Ok(device) = nvml_handle.device_by_index(i) {
                        let name = device.name().unwrap_or_else(|_| format!("NVIDIA GPU {}", i));
                        device_metrics.push(GpuDeviceMetrics::new_nvidia(name, i));
                    }
                }
            }
        }

        let available = !device_metrics.is_empty();

        Self {
            available,
            devices: device_metrics,
            nvml,
        }
    }

    pub fn update(&mut self) {
        for dev in &mut self.devices {
            match &dev.backend {
                GpuBackend::Amd(_) => dev.update_amd(),
                GpuBackend::Nvidia { device_index } => {
                    if let Some(ref nvml) = self.nvml {
                        let idx = *device_index;
                        dev.update_nvidia(nvml, idx);
                    }
                }
            }
        }
    }
}

impl GpuDeviceMetrics {
    fn new_amd(amd_dev: AmdGpuDiscovery) -> Self {
        Self {
            vendor: GpuVendor::Amd,
            name: amd_dev.name,
            gpu_usage: 0.0,
            vram_total: 0,
            vram_used: 0,
            vram_usage_percent: 0.0,
            temperature_edge: None,
            temperature_junction: None,
            temperature_memory: None,
            gpu_clock_mhz: None,
            vram_clock_mhz: None,
            power_watts: None,
            power_cap_watts: None,
            fan_rpm: None,
            fan_max_rpm: None,
            gpu_history: Vec::with_capacity(HISTORY_SIZE),
            vram_history: Vec::with_capacity(HISTORY_SIZE),
            temp_history: Vec::with_capacity(HISTORY_SIZE),
            power_history: Vec::with_capacity(HISTORY_SIZE),
            backend: GpuBackend::Amd(AmdDevice {
                card_path: amd_dev.card_path,
                hwmon_path: amd_dev.hwmon_path,
            }),
        }
    }

    fn new_nvidia(name: String, device_index: u32) -> Self {
        Self {
            vendor: GpuVendor::Nvidia,
            name,
            gpu_usage: 0.0,
            vram_total: 0,
            vram_used: 0,
            vram_usage_percent: 0.0,
            temperature_edge: None,
            temperature_junction: None,
            temperature_memory: None,
            gpu_clock_mhz: None,
            vram_clock_mhz: None,
            power_watts: None,
            power_cap_watts: None,
            fan_rpm: None,
            fan_max_rpm: None,
            gpu_history: Vec::with_capacity(HISTORY_SIZE),
            vram_history: Vec::with_capacity(HISTORY_SIZE),
            temp_history: Vec::with_capacity(HISTORY_SIZE),
            power_history: Vec::with_capacity(HISTORY_SIZE),
            backend: GpuBackend::Nvidia { device_index },
        }
    }

    fn update_amd(&mut self) {
        let amd = match &self.backend {
            GpuBackend::Amd(dev) => dev,
            _ => return,
        };
        let card = &amd.card_path;

        // GPU utilization
        self.gpu_usage = read_sysfs_f32(&card.join("device/gpu_busy_percent")).unwrap_or(0.0);

        // VRAM
        self.vram_total = read_sysfs_u64(&card.join("device/mem_info_vram_total")).unwrap_or(0);
        self.vram_used = read_sysfs_u64(&card.join("device/mem_info_vram_used")).unwrap_or(0);
        self.vram_usage_percent = if self.vram_total > 0 {
            (self.vram_used as f32 / self.vram_total as f32) * 100.0
        } else {
            0.0
        };

        // Temperature (millidegrees -> degrees)
        if let Some(hwmon) = &amd.hwmon_path {
            self.temperature_edge =
                read_sysfs_f32(&hwmon.join("temp1_input")).map(|v| v / 1000.0);
            self.temperature_junction =
                read_sysfs_f32(&hwmon.join("temp2_input")).map(|v| v / 1000.0);
            self.temperature_memory =
                read_sysfs_f32(&hwmon.join("temp3_input")).map(|v| v / 1000.0);

            // Clock frequencies (Hz -> MHz)
            self.gpu_clock_mhz =
                read_sysfs_u64(&hwmon.join("freq1_input")).map(|v| v / 1_000_000);
            self.vram_clock_mhz =
                read_sysfs_u64(&hwmon.join("freq2_input")).map(|v| v / 1_000_000);

            // Power (microwatts -> watts)
            self.power_watts = read_sysfs_f32(&hwmon.join("power1_average"))
                .or_else(|| read_sysfs_f32(&hwmon.join("power1_input")))
                .map(|v| v / 1_000_000.0);
            self.power_cap_watts =
                read_sysfs_f32(&hwmon.join("power1_cap")).map(|v| v / 1_000_000.0);

            // Fan
            self.fan_rpm = read_sysfs_u64(&hwmon.join("fan1_input"));
            self.fan_max_rpm = read_sysfs_u64(&hwmon.join("fan1_max"));
        }

        // If no hwmon, try reading clocks from pp_dpm_sclk/pp_dpm_mclk
        if self.gpu_clock_mhz.is_none() {
            self.gpu_clock_mhz = read_active_dpm_clock(&card.join("device/pp_dpm_sclk"));
        }
        if self.vram_clock_mhz.is_none() {
            self.vram_clock_mhz = read_active_dpm_clock(&card.join("device/pp_dpm_mclk"));
        }

        self.update_histories();
    }

    fn update_nvidia(&mut self, nvml: &Nvml, device_index: u32) {
        let device = match nvml.device_by_index(device_index) {
            Ok(d) => d,
            Err(_) => return,
        };

        // GPU + memory utilization
        if let Ok(util) = device.utilization_rates() {
            self.gpu_usage = util.gpu as f32;
        }

        // VRAM
        if let Ok(mem) = device.memory_info() {
            self.vram_total = mem.total;
            self.vram_used = mem.used;
            self.vram_usage_percent = if mem.total > 0 {
                (mem.used as f32 / mem.total as f32) * 100.0
            } else {
                0.0
            };
        }

        // Temperature
        if let Ok(temp) = device.temperature(nvml_wrapper::enum_wrappers::device::TemperatureSensor::Gpu) {
            self.temperature_edge = Some(temp as f32);
        }

        // Clocks
        if let Ok(clock) = device.clock_info(nvml_wrapper::enum_wrappers::device::Clock::Graphics) {
            self.gpu_clock_mhz = Some(clock as u64);
        }
        if let Ok(clock) = device.clock_info(nvml_wrapper::enum_wrappers::device::Clock::Memory) {
            self.vram_clock_mhz = Some(clock as u64);
        }

        // Power (milliwatts -> watts)
        if let Ok(power) = device.power_usage() {
            self.power_watts = Some(power as f32 / 1000.0);
        }
        if let Ok(limit) = device.enforced_power_limit() {
            self.power_cap_watts = Some(limit as f32 / 1000.0);
        }

        // Fan speed (percentage, convert to approximate RPM is not available — show percentage)
        if let Ok(fan) = device.fan_speed(0) {
            // NVML gives percentage, not RPM. Store as percentage in fan_rpm field
            // and set max to 100 so the UI can show "XX%"
            self.fan_rpm = Some(fan as u64);
            self.fan_max_rpm = Some(100);
        }

        self.update_histories();
    }

    fn update_histories(&mut self) {
        push_history(&mut self.gpu_history, self.gpu_usage);
        push_history(&mut self.vram_history, self.vram_usage_percent);
        if let Some(temp) = self.temperature_edge.or(self.temperature_junction) {
            push_history(&mut self.temp_history, temp);
        }
        if let Some(power) = self.power_watts {
            push_history(&mut self.power_history, power);
        }
    }
}

fn push_history(history: &mut Vec<f32>, value: f32) {
    history.push(value);
    if history.len() > HISTORY_SIZE {
        history.remove(0);
    }
}

fn read_sysfs_string(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

fn read_sysfs_u64(path: &Path) -> Option<u64> {
    read_sysfs_string(path)?.parse().ok()
}

fn read_sysfs_f32(path: &Path) -> Option<f32> {
    read_sysfs_string(path)?.parse().ok()
}

/// Parse pp_dpm_sclk/pp_dpm_mclk: find the line with '*' and extract MHz
fn read_active_dpm_clock(path: &Path) -> Option<u64> {
    let content = fs::read_to_string(path).ok()?;
    for line in content.lines() {
        if line.contains('*') {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 {
                let freq_str = parts[1].trim_end_matches("Mhz").trim_end_matches("MHz");
                return freq_str.parse().ok();
            }
        }
    }
    None
}

// AMD GPU discovery types and functions

struct AmdGpuDiscovery {
    card_path: PathBuf,
    hwmon_path: Option<PathBuf>,
    name: String,
}

fn discover_amd_gpus() -> Vec<AmdGpuDiscovery> {
    let mut devices = Vec::new();

    let drm_path = Path::new("/sys/class/drm");
    if !drm_path.exists() {
        return devices;
    }

    let entries = match fs::read_dir(drm_path) {
        Ok(e) => e,
        Err(_) => return devices,
    };

    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if !name.starts_with("card") || name.contains('-') {
            continue;
        }

        let card_path = entry.path();
        let device_path = card_path.join("device");

        let vendor = read_sysfs_string(&device_path.join("vendor"));
        match vendor.as_deref() {
            Some("0x1002") => {}
            _ => continue,
        }

        let pci_id = read_sysfs_string(&device_path.join("device"))
            .unwrap_or_else(|| "unknown".to_string());

        let gpu_name = read_gpu_name(&device_path)
            .unwrap_or_else(|| format!("AMD GPU ({})", pci_id));

        let hwmon_path = find_hwmon_path(&device_path);

        devices.push(AmdGpuDiscovery {
            card_path,
            hwmon_path,
            name: gpu_name,
        });
    }

    devices
}

fn read_gpu_name(device_path: &Path) -> Option<String> {
    let uevent = read_sysfs_string(&device_path.join("uevent"))?;
    for line in uevent.lines() {
        if line.starts_with("PCI_SLOT_NAME=") || line.starts_with("DRIVER=") {
            continue;
        }
        if let Some(name) = line.strip_prefix("PCI_ID=") {
            return Some(format!("AMD GPU [{}]", name));
        }
    }
    None
}

fn find_hwmon_path(device_path: &Path) -> Option<PathBuf> {
    let hwmon_dir = device_path.join("hwmon");
    if !hwmon_dir.exists() {
        return None;
    }

    let entries = fs::read_dir(&hwmon_dir).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.join("temp1_input").exists() || path.join("power1_average").exists() {
            return Some(path);
        }
    }

    fs::read_dir(&hwmon_dir)
        .ok()?
        .flatten()
        .next()
        .map(|e| e.path())
}

pub fn format_vram(bytes: u64) -> String {
    const MIB: u64 = 1024 * 1024;
    const GIB: u64 = MIB * 1024;

    if bytes >= GIB {
        format!("{:.1} GiB", bytes as f64 / GIB as f64)
    } else if bytes >= MIB {
        format!("{:.0} MiB", bytes as f64 / MIB as f64)
    } else {
        format!("{} B", bytes)
    }
}
