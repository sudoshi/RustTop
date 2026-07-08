use sysinfo::System;

use super::history::HistoryBuffer;
use super::units;

const HISTORY_SIZE: usize = 120;
#[cfg(target_os = "macos")]
const MACOS_MEMORY_DETAILS_INTERVAL: std::time::Duration = std::time::Duration::from_secs(5);

#[derive(Debug, Clone)]
pub struct MemoryMetrics {
    pub total_mem: u64,
    pub used_mem: u64,
    pub available_mem: u64,
    pub total_swap: u64,
    pub used_swap: u64,
    pub mem_usage_percent: f32,
    pub swap_usage_percent: f32,
    pub app_memory: Option<u64>,
    pub wired_memory: Option<u64>,
    pub compressed_memory: Option<u64>,
    pub file_cache: Option<u64>,
    pub pressure_percent: Option<f32>,
    pub pressure_level: Option<MemoryPressureLevel>,
    pub mem_history: HistoryBuffer<f32>,
    pub swap_history: HistoryBuffer<f32>,
    #[cfg(target_os = "macos")]
    last_macos_details_refresh: Option<std::time::Instant>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemoryPressureLevel {
    Normal,
    Warning,
    Critical,
}

impl MemoryPressureLevel {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Normal => "normal",
            Self::Warning => "warning",
            Self::Critical => "critical",
        }
    }
}

impl MemoryMetrics {
    pub fn new() -> Self {
        Self {
            total_mem: 0,
            used_mem: 0,
            available_mem: 0,
            total_swap: 0,
            used_swap: 0,
            mem_usage_percent: 0.0,
            swap_usage_percent: 0.0,
            app_memory: None,
            wired_memory: None,
            compressed_memory: None,
            file_cache: None,
            pressure_percent: None,
            pressure_level: None,
            mem_history: HistoryBuffer::new(HISTORY_SIZE),
            swap_history: HistoryBuffer::new(HISTORY_SIZE),
            #[cfg(target_os = "macos")]
            last_macos_details_refresh: None,
        }
    }

    pub fn update(&mut self, sys: &System) {
        self.total_mem = sys.total_memory();
        self.used_mem = sys.used_memory();
        self.available_mem = sys.available_memory();
        self.total_swap = sys.total_swap();
        self.used_swap = sys.used_swap();

        self.mem_usage_percent = if self.total_mem > 0 {
            (self.used_mem as f32 / self.total_mem as f32) * 100.0
        } else {
            0.0
        };

        self.swap_usage_percent = if self.total_swap > 0 {
            (self.used_swap as f32 / self.total_swap as f32) * 100.0
        } else {
            0.0
        };

        self.mem_history.push(self.mem_usage_percent);

        self.swap_history.push(self.swap_usage_percent);
        self.update_platform_details();
    }

    pub fn format_bytes(bytes: u64) -> String {
        units::format_binary_bytes(bytes)
    }

    fn update_platform_details(&mut self) {
        #[cfg(target_os = "macos")]
        {
            let due = self
                .last_macos_details_refresh
                .is_none_or(|last| last.elapsed() >= MACOS_MEMORY_DETAILS_INTERVAL);

            if due {
                self.apply_macos_memory_details(read_macos_memory_details(self.total_mem));
                self.last_macos_details_refresh = Some(std::time::Instant::now());
            }
        }
    }

    #[cfg(target_os = "macos")]
    fn apply_macos_memory_details(&mut self, details: Option<MacOsMemoryDetails>) {
        self.app_memory = details.map(|details| details.app_memory);
        self.wired_memory = details.map(|details| details.wired_memory);
        self.compressed_memory = details.map(|details| details.compressed_memory);
        self.file_cache = details.map(|details| details.file_cache);
        self.pressure_percent = details.map(|details| details.pressure_percent);
        self.pressure_level = details.map(|details| details.pressure_level);
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct MacOsMemoryDetails {
    app_memory: u64,
    wired_memory: u64,
    compressed_memory: u64,
    file_cache: u64,
    pressure_percent: f32,
    pressure_level: MemoryPressureLevel,
}

#[cfg(target_os = "macos")]
fn read_macos_memory_details(total_mem: u64) -> Option<MacOsMemoryDetails> {
    let output = std::process::Command::new("vm_stat").output().ok()?;
    let stdout = String::from_utf8(output.stdout).ok()?;
    parse_macos_vm_stat(&stdout, total_mem)
}

fn parse_macos_vm_stat(output: &str, total_mem: u64) -> Option<MacOsMemoryDetails> {
    let page_size = parse_macos_page_size(output)?;
    let pages = |label: &str| parse_macos_page_count(output, label).unwrap_or(0);

    let app_pages = pages("Anonymous pages");
    let wired_pages = pages("Pages wired down");
    let compressed_pages = pages("Pages occupied by compressor");
    let file_cache_pages = pages("File-backed pages") + pages("Pages purgeable");
    let free_pages = pages("Pages free") + pages("Pages speculative");

    let app_memory = app_pages.saturating_mul(page_size);
    let wired_memory = wired_pages.saturating_mul(page_size);
    let compressed_memory = compressed_pages.saturating_mul(page_size);
    let file_cache = file_cache_pages.saturating_mul(page_size);
    let free_memory = free_pages.saturating_mul(page_size);

    let denominator = if total_mem > 0 {
        total_mem
    } else {
        app_memory
            .saturating_add(wired_memory)
            .saturating_add(compressed_memory)
            .saturating_add(file_cache)
            .saturating_add(free_memory)
    };

    if denominator == 0 {
        return None;
    }

    let pressure_memory = app_memory
        .saturating_add(wired_memory)
        .saturating_add(compressed_memory);
    let pressure_percent =
        ((pressure_memory as f32 / denominator as f32) * 100.0).clamp(0.0, 100.0);
    let pressure_level = match pressure_percent {
        value if value >= 85.0 => MemoryPressureLevel::Critical,
        value if value >= 70.0 => MemoryPressureLevel::Warning,
        _ => MemoryPressureLevel::Normal,
    };

    Some(MacOsMemoryDetails {
        app_memory,
        wired_memory,
        compressed_memory,
        file_cache,
        pressure_percent,
        pressure_level,
    })
}

fn parse_macos_page_size(output: &str) -> Option<u64> {
    let marker = "page size of ";
    let start = output.find(marker)? + marker.len();
    let value = output[start..]
        .chars()
        .take_while(|ch| ch.is_ascii_digit())
        .collect::<String>();
    value.parse().ok()
}

fn parse_macos_page_count(output: &str, label: &str) -> Option<u64> {
    output.lines().find_map(|line| {
        let (candidate, value) = line.split_once(':')?;
        if candidate.trim().trim_matches('"') != label {
            return None;
        }

        let digits = value
            .trim()
            .trim_end_matches('.')
            .chars()
            .filter(|ch| ch.is_ascii_digit())
            .collect::<String>();
        digits.parse().ok()
    })
}

#[cfg(test)]
mod tests {
    use super::{parse_macos_vm_stat, MemoryMetrics, MemoryPressureLevel};

    #[test]
    fn formats_bytes_at_binary_boundaries() {
        assert_eq!(MemoryMetrics::format_bytes(512), "512 B");
        assert_eq!(MemoryMetrics::format_bytes(1024), "1.0 KiB");
        assert_eq!(MemoryMetrics::format_bytes(1024 * 1024), "1.0 MiB");
        assert_eq!(MemoryMetrics::format_bytes(1024 * 1024 * 1024), "1.0 GiB");
    }

    #[test]
    fn parses_macos_vm_stat_breakdown() {
        let details = parse_macos_vm_stat(
            r#"Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                               1000.
Pages active:                             4000.
Pages inactive:                           2000.
Pages speculative:                         500.
Pages wired down:                         3000.
Pages purgeable:                           250.
File-backed pages:                        1500.
Anonymous pages:                          5000.
Pages stored in compressor:               2200.
Pages occupied by compressor:             1000.
"Translation faults":                  12345678.
"#,
            16_384 * 12_000,
        )
        .expect("vm_stat sample should parse");

        assert_eq!(details.app_memory, 16_384 * 5_000);
        assert_eq!(details.wired_memory, 16_384 * 3_000);
        assert_eq!(details.compressed_memory, 16_384 * 1_000);
        assert_eq!(details.file_cache, 16_384 * 1_750);
        assert_eq!(details.pressure_level, MemoryPressureLevel::Warning);
    }

    #[test]
    fn rejects_macos_vm_stat_without_page_size() {
        assert!(parse_macos_vm_stat("Pages free: 100.", 4096).is_none());
    }
}
