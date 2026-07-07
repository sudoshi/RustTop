#[derive(Debug, Clone)]
pub struct BatteryInfo {
    pub name: String,
    pub status: String,
    pub capacity_percent: Option<f32>,
    pub health_percent: Option<f32>,
}

#[derive(Debug, Clone)]
pub struct BatteryMetrics {
    pub batteries: Vec<BatteryInfo>,
}

impl BatteryMetrics {
    pub fn new() -> Self {
        let mut metrics = Self {
            batteries: Vec::new(),
        };
        metrics.update();
        metrics
    }

    pub fn update(&mut self) {
        self.batteries = read_batteries();
    }
}

#[cfg(target_os = "linux")]
fn read_batteries() -> Vec<BatteryInfo> {
    read_batteries_in(std::path::Path::new("/sys/class/power_supply"))
}

#[cfg(not(target_os = "linux"))]
fn read_batteries() -> Vec<BatteryInfo> {
    Vec::new()
}

#[cfg(target_os = "linux")]
fn read_batteries_in(root: &std::path::Path) -> Vec<BatteryInfo> {
    let Ok(entries) = std::fs::read_dir(root) else {
        return Vec::new();
    };

    let mut batteries = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        let power_type = read_trimmed(path.join("type"));
        if power_type.as_deref() != Some("Battery") {
            continue;
        }

        let name = path
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
            .unwrap_or_else(|| "Battery".to_string());
        let capacity_percent = read_number(path.join("capacity")).map(|value| value as f32);
        let status = read_trimmed(path.join("status")).unwrap_or_else(|| "Unknown".to_string());
        let health_percent = battery_health_percent(&path);

        batteries.push(BatteryInfo {
            name,
            status,
            capacity_percent,
            health_percent,
        });
    }

    batteries
}

#[cfg(target_os = "linux")]
fn battery_health_percent(path: &std::path::Path) -> Option<f32> {
    let full =
        read_number(path.join("energy_full")).or_else(|| read_number(path.join("charge_full")))?;
    let design = read_number(path.join("energy_full_design"))
        .or_else(|| read_number(path.join("charge_full_design")))?;

    if design == 0 {
        None
    } else {
        Some((full as f32 / design as f32) * 100.0)
    }
}

#[cfg(target_os = "linux")]
fn read_number(path: std::path::PathBuf) -> Option<u64> {
    read_trimmed(path)?.parse().ok()
}

#[cfg(target_os = "linux")]
fn read_trimmed(path: std::path::PathBuf) -> Option<String> {
    std::fs::read_to_string(path)
        .ok()
        .map(|value| value.trim().to_string())
}

#[cfg(test)]
#[cfg(target_os = "linux")]
mod tests {
    use std::fs;

    use super::read_batteries_in;

    #[test]
    fn reads_linux_power_supply_battery_fixture() {
        let dir = std::env::temp_dir().join(format!(
            "rust_top_battery_test_{}_{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock after epoch")
                .as_nanos()
        ));
        let bat = dir.join("BAT0");
        fs::create_dir_all(&bat).expect("fixture directory");
        fs::write(bat.join("type"), "Battery\n").expect("type");
        fs::write(bat.join("capacity"), "87\n").expect("capacity");
        fs::write(bat.join("status"), "Charging\n").expect("status");
        fs::write(bat.join("energy_full"), "8700\n").expect("full");
        fs::write(bat.join("energy_full_design"), "10000\n").expect("design");

        let batteries = read_batteries_in(&dir);

        assert_eq!(batteries.len(), 1);
        assert_eq!(batteries[0].name, "BAT0");
        assert_eq!(batteries[0].status, "Charging");
        assert_eq!(batteries[0].capacity_percent, Some(87.0));
        assert_eq!(batteries[0].health_percent, Some(87.0));

        let _ = fs::remove_dir_all(dir);
    }
}
