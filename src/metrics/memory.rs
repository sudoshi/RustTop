use sysinfo::System;

use super::history::HistoryBuffer;
use super::units;

const HISTORY_SIZE: usize = 120;

#[derive(Debug, Clone)]
pub struct MemoryMetrics {
    pub total_mem: u64,
    pub used_mem: u64,
    pub available_mem: u64,
    pub total_swap: u64,
    pub used_swap: u64,
    pub mem_usage_percent: f32,
    pub swap_usage_percent: f32,
    pub mem_history: HistoryBuffer<f32>,
    pub swap_history: HistoryBuffer<f32>,
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
            mem_history: HistoryBuffer::new(HISTORY_SIZE),
            swap_history: HistoryBuffer::new(HISTORY_SIZE),
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
    }

    pub fn format_bytes(bytes: u64) -> String {
        units::format_binary_bytes(bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::MemoryMetrics;

    #[test]
    fn formats_bytes_at_binary_boundaries() {
        assert_eq!(MemoryMetrics::format_bytes(512), "512 B");
        assert_eq!(MemoryMetrics::format_bytes(1024), "1.0 KiB");
        assert_eq!(MemoryMetrics::format_bytes(1024 * 1024), "1.0 MiB");
        assert_eq!(MemoryMetrics::format_bytes(1024 * 1024 * 1024), "1.0 GiB");
    }
}
