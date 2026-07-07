use sysinfo::System;

use super::history::HistoryBuffer;

const HISTORY_SIZE: usize = 120;

#[derive(Debug, Clone)]
pub struct CpuMetrics {
    pub global_usage: f32,
    pub per_core_usage: Vec<f32>,
    pub core_count: usize,
    pub brand: String,
    pub frequency_mhz: u64,
    pub history: HistoryBuffer<f32>,
    pub per_core_history: Vec<HistoryBuffer<f32>>,
}

impl CpuMetrics {
    pub fn new() -> Self {
        Self {
            global_usage: 0.0,
            per_core_usage: Vec::new(),
            core_count: 0,
            brand: String::new(),
            frequency_mhz: 0,
            history: HistoryBuffer::new(HISTORY_SIZE),
            per_core_history: Vec::new(),
        }
    }

    pub fn update(&mut self, sys: &System) {
        let cpus = sys.cpus();
        self.core_count = cpus.len();
        self.global_usage = sys.global_cpu_usage();

        if !cpus.is_empty() {
            self.brand = cpus[0].brand().to_string();
            self.frequency_mhz = cpus[0].frequency();
        }

        self.per_core_usage = cpus.iter().map(|cpu| cpu.cpu_usage()).collect();

        // Update global history
        self.history.push(self.global_usage);

        // Update per-core history
        if self.per_core_history.len() != self.core_count {
            self.per_core_history = vec![HistoryBuffer::new(HISTORY_SIZE); self.core_count];
        }
        for (i, usage) in self.per_core_usage.iter().enumerate() {
            if let Some(history) = self.per_core_history.get_mut(i) {
                history.push(*usage);
            }
        }
    }
}
