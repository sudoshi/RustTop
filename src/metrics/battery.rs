#[derive(Debug, Clone)]
pub struct BatteryInfo {
    pub name: String,
    pub status: String,
    pub capacity_percent: Option<f32>,
    pub health_percent: Option<f32>,
    pub cycle_count: Option<u32>,
    pub power_source: Option<String>,
    pub adapter_watts: Option<f32>,
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

#[cfg(target_os = "macos")]
fn read_batteries() -> Vec<BatteryInfo> {
    let output = std::process::Command::new("ioreg")
        .args(["-r", "-c", "AppleSmartBattery", "-d", "1", "-l", "-w", "0"])
        .output()
        .ok();

    output
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|stdout| read_macos_batteries_from_ioreg(&stdout))
        .unwrap_or_default()
}

#[cfg(not(any(target_os = "linux", target_os = "macos")))]
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
            cycle_count: None,
            power_source: None,
            adapter_watts: None,
        });
    }

    batteries
}

fn read_macos_batteries_from_ioreg(output: &str) -> Vec<BatteryInfo> {
    if !output.contains("AppleSmartBattery") {
        return Vec::new();
    }

    let current_capacity = parse_ioreg_u64(output, "CurrentCapacity");
    let max_capacity = parse_ioreg_u64(output, "MaxCapacity");
    let design_capacity = parse_ioreg_u64(output, "DesignCapacity");
    let is_charging = parse_ioreg_bool(output, "IsCharging");
    let fully_charged = parse_ioreg_bool(output, "FullyCharged");
    let external_connected = parse_ioreg_bool(output, "ExternalConnected");

    let capacity_percent = match (current_capacity, max_capacity) {
        (Some(current), Some(max)) if max > 0 => Some((current as f32 / max as f32) * 100.0),
        _ => None,
    };
    let health_percent = match (max_capacity, design_capacity) {
        (Some(max), Some(design)) if design > 0 => Some((max as f32 / design as f32) * 100.0),
        _ => None,
    };
    let status = match (fully_charged, is_charging, external_connected) {
        (Some(true), _, _) => "Full",
        (_, Some(true), _) => "Charging",
        (_, Some(false), Some(false)) => "Discharging",
        (_, Some(false), Some(true)) => "Not Charging",
        _ => "Unknown",
    }
    .to_string();

    let battery = BatteryInfo {
        name: parse_ioreg_string(output, "DeviceName").unwrap_or_else(|| "Internal Battery".into()),
        status,
        capacity_percent,
        health_percent,
        cycle_count: parse_ioreg_u64(output, "CycleCount").and_then(|value| value.try_into().ok()),
        power_source: external_connected.map(|connected| {
            if connected {
                "AC Power".to_string()
            } else {
                "Battery Power".to_string()
            }
        }),
        adapter_watts: parse_ioreg_u64(output, "Watts").map(|value| value as f32),
    };

    Vec::from([battery])
}

fn parse_ioreg_u64(output: &str, key: &str) -> Option<u64> {
    let value = parse_ioreg_value(output, key)?;
    value
        .chars()
        .skip_while(|ch| !ch.is_ascii_digit())
        .take_while(|ch| ch.is_ascii_digit())
        .collect::<String>()
        .parse()
        .ok()
}

fn parse_ioreg_bool(output: &str, key: &str) -> Option<bool> {
    match parse_ioreg_value(output, key)?.trim() {
        "Yes" | "true" | "True" => Some(true),
        "No" | "false" | "False" => Some(false),
        _ => None,
    }
}

fn parse_ioreg_string(output: &str, key: &str) -> Option<String> {
    let value = parse_ioreg_value(output, key)?.trim();
    Some(value.trim_matches('"').to_string()).filter(|value| !value.is_empty())
}

fn parse_ioreg_value<'a>(output: &'a str, key: &str) -> Option<&'a str> {
    let quoted_key = format!("\"{key}\"");
    output.lines().find_map(|line| {
        let trimmed = line.trim();
        if !trimmed.starts_with(&quoted_key) {
            return None;
        }
        let (_, value) = trimmed.split_once('=')?;
        Some(value.trim())
    })
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
mod macos_parser_tests {
    use super::read_macos_batteries_from_ioreg;

    #[test]
    fn reads_macos_ioreg_battery_fixture() {
        let batteries = read_macos_batteries_from_ioreg(
            r#"+-o AppleSmartBattery  <class AppleSmartBattery, id 0x100000000, registered, matched, active, busy 0 (0 ms), retain 8>
{
  "DeviceName" = "bq40z651"
  "CurrentCapacity" = 7120
  "MaxCapacity" = 8000
  "DesignCapacity" = 8500
  "CycleCount" = 321
  "FullyCharged" = No
  "IsCharging" = Yes
  "ExternalConnected" = Yes
  "AdapterDetails" = {"Watts"=96,"Description"="USB-C"}
  "Watts" = 96
}
"#,
        );

        assert_eq!(batteries.len(), 1);
        assert_eq!(batteries[0].name, "bq40z651");
        assert_eq!(batteries[0].status, "Charging");
        assert_eq!(batteries[0].capacity_percent, Some(89.0));
        assert_eq!(batteries[0].health_percent, Some(94.117645));
        assert_eq!(batteries[0].cycle_count, Some(321));
        assert_eq!(batteries[0].power_source.as_deref(), Some("AC Power"));
        assert_eq!(batteries[0].adapter_watts, Some(96.0));
    }

    #[test]
    fn ignores_ioreg_output_without_smart_battery() {
        assert!(read_macos_batteries_from_ioreg("{}").is_empty());
    }
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
