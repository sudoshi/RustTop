use sysinfo::System;

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
    pub mem_history: Vec<f32>,
    pub swap_history: Vec<f32>,
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
            mem_history: Vec::with_capacity(HISTORY_SIZE),
            swap_history: Vec::with_capacity(HISTORY_SIZE),
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
        if self.mem_history.len() > HISTORY_SIZE {
            self.mem_history.remove(0);
        }

        self.swap_history.push(self.swap_usage_percent);
        if self.swap_history.len() > HISTORY_SIZE {
            self.swap_history.remove(0);
        }
    }

    pub fn format_bytes(bytes: u64) -> String {
        const KIB: u64 = 1024;
        const MIB: u64 = KIB * 1024;
        const GIB: u64 = MIB * 1024;
        const TIB: u64 = GIB * 1024;

        if bytes >= TIB {
            format!("{:.1} TiB", bytes as f64 / TIB as f64)
        } else if bytes >= GIB {
            format!("{:.1} GiB", bytes as f64 / GIB as f64)
        } else if bytes >= MIB {
            format!("{:.1} MiB", bytes as f64 / MIB as f64)
        } else if bytes >= KIB {
            format!("{:.1} KiB", bytes as f64 / KIB as f64)
        } else {
            format!("{} B", bytes)
        }
    }
}
