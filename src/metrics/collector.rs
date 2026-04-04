use sysinfo::System;

use super::cpu::CpuMetrics;
use super::disk::DiskMetrics;
use super::gpu::GpuMetrics;
use super::memory::MemoryMetrics;
use super::network::NetworkMetrics;
use super::process::ProcessMetrics;

#[derive(Debug)]
pub struct SystemMetrics {
    pub cpu: CpuMetrics,
    pub memory: MemoryMetrics,
    pub disk: DiskMetrics,
    pub network: NetworkMetrics,
    pub gpu: GpuMetrics,
    pub processes: ProcessMetrics,
    pub hostname: String,
    pub os_name: String,
    pub os_version: String,
    pub kernel_version: String,
    pub uptime: u64,
    system: System,
    tick_count: u64,
}

impl SystemMetrics {
    pub fn new() -> Self {
        let mut system = System::new_all();
        system.refresh_all();

        let hostname = System::host_name().unwrap_or_else(|| "unknown".to_string());
        let os_name = System::name().unwrap_or_else(|| "unknown".to_string());
        let os_version = System::os_version().unwrap_or_else(|| "unknown".to_string());
        let kernel_version = System::kernel_version().unwrap_or_else(|| "unknown".to_string());

        Self {
            cpu: CpuMetrics::new(),
            memory: MemoryMetrics::new(),
            disk: DiskMetrics::new(),
            network: NetworkMetrics::new(),
            gpu: GpuMetrics::new(),
            processes: ProcessMetrics::new(),
            hostname,
            os_name,
            os_version,
            kernel_version,
            uptime: 0,
            system,
            tick_count: 0,
        }
    }

    pub fn refresh(&mut self) {
        self.tick_count += 1;

        // Refresh CPU and memory every tick
        self.system.refresh_cpu_all();
        self.system.refresh_memory();
        self.system.refresh_processes(sysinfo::ProcessesToUpdate::All, true);

        self.cpu.update(&self.system);
        self.memory.update(&self.system);
        self.processes.update(&self.system);
        self.network.update();
        self.gpu.update();

        // Refresh disks less frequently (every 10 ticks)
        if self.tick_count % 10 == 0 {
            self.disk.update();
        }

        self.uptime = System::uptime();
    }

    pub fn format_uptime(&self) -> String {
        let days = self.uptime / 86400;
        let hours = (self.uptime % 86400) / 3600;
        let minutes = (self.uptime % 3600) / 60;
        let seconds = self.uptime % 60;

        if days > 0 {
            format!("{}d {}h {}m {}s", days, hours, minutes, seconds)
        } else if hours > 0 {
            format!("{}h {}m {}s", hours, minutes, seconds)
        } else {
            format!("{}m {}s", minutes, seconds)
        }
    }
}
