use std::fs;
use std::path::{Path, PathBuf};

const HISTORY_SIZE: usize = 120;

#[derive(Debug, Clone)]
pub struct GpuDevice {
    pub card_path: PathBuf,
    pub hwmon_path: Option<PathBuf>,
    pub name: String,
    pub pci_id: String,
}

#[derive(Debug, Clone)]
pub struct GpuMetrics {
    pub available: bool,
    pub devices: Vec<GpuDeviceMetrics>,
}

#[derive(Debug, Clone)]
pub struct GpuDeviceMetrics {
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
    device: GpuDevice,
}

impl GpuMetrics {
    pub fn new() -> Self {
        let devices = discover_amd_gpus();
        let available = !devices.is_empty();
        let device_metrics = devices
            .into_iter()
            .map(|dev| GpuDeviceMetrics {
                name: dev.name.clone(),
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
                device: dev,
            })
            .collect();

        Self {
            available,
            devices: device_metrics,
        }
    }

    pub fn update(&mut self) {
        for dev in &mut self.devices {
            dev.update();
        }
    }
}

impl GpuDeviceMetrics {
    fn update(&mut self) {
        let card = &self.device.card_path;

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
        if let Some(hwmon) = &self.device.hwmon_path {
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

        // If no hwmon but on Linux, try reading clocks from pp_dpm_sclk/pp_dpm_mclk
        if self.gpu_clock_mhz.is_none() {
            self.gpu_clock_mhz = read_active_dpm_clock(&card.join("device/pp_dpm_sclk"));
        }
        if self.vram_clock_mhz.is_none() {
            self.vram_clock_mhz = read_active_dpm_clock(&card.join("device/pp_dpm_mclk"));
        }

        // Update histories
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
            // Format: "1: 1800Mhz *"
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 {
                let freq_str = parts[1].trim_end_matches("Mhz").trim_end_matches("MHz");
                return freq_str.parse().ok();
            }
        }
    }
    None
}

/// Discover AMD GPUs by scanning /sys/class/drm/card*
fn discover_amd_gpus() -> Vec<GpuDevice> {
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
        // Only look at cardN, not card0-DP-1 etc.
        if !name.starts_with("card") || name.contains('-') {
            continue;
        }

        let card_path = entry.path();
        let device_path = card_path.join("device");

        // Check if this is an AMD GPU by reading the vendor ID
        let vendor = read_sysfs_string(&device_path.join("vendor"));
        match vendor.as_deref() {
            Some("0x1002") => {} // AMD vendor ID
            _ => continue,
        }

        // Get device name from uevent or use PCI ID
        let pci_id = read_sysfs_string(&device_path.join("device"))
            .unwrap_or_else(|| "unknown".to_string());

        let gpu_name = read_gpu_name(&device_path).unwrap_or_else(|| {
            format!("AMD GPU ({})", pci_id)
        });

        // Find hwmon path
        let hwmon_path = find_hwmon_path(&device_path);

        devices.push(GpuDevice {
            card_path,
            hwmon_path,
            name: gpu_name,
            pci_id,
        });
    }

    devices
}

fn read_gpu_name(device_path: &Path) -> Option<String> {
    // Try reading from uevent for a product name
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

    // Just return the first hwmon if none matched specifically
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
