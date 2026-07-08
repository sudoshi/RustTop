use std::time::{Duration, Instant, SystemTime};

use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System};

use super::battery::BatteryMetrics;
use super::cpu::CpuMetrics;
use super::disk::DiskMetrics;
use super::gpu::GpuMetrics;
use super::launchd::LaunchdMetrics;
use super::memory::MemoryMetrics;
use super::network::NetworkMetrics;
use super::process::{ProcessMetrics, SortField};
use super::sensors::SensorMetrics;

#[derive(Debug)]
pub struct SystemMetrics {
    pub cpu: CpuMetrics,
    pub memory: MemoryMetrics,
    pub disk: DiskMetrics,
    pub battery: BatteryMetrics,
    pub sensors: SensorMetrics,
    pub network: NetworkMetrics,
    pub gpu: GpuMetrics,
    pub launchd: LaunchdMetrics,
    pub processes: ProcessMetrics,
    pub hostname: String,
    pub os_name: String,
    pub os_version: String,
    pub kernel_version: String,
    pub uptime: u64,
    pub collector_status: CollectorStatus,
    pub last_refresh_duration: Option<Duration>,
    pub last_refresh_completed_at: Option<SystemTime>,
    system: System,
    tick_count: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CollectorStatus {
    Starting,
    Ok,
}

impl CollectorStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            CollectorStatus::Starting => "starting",
            CollectorStatus::Ok => "ok",
        }
    }
}

impl SystemMetrics {
    pub fn new(gpu_enabled: bool, default_sort: SortField, sort_ascending: bool) -> Self {
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
            battery: BatteryMetrics::new(),
            sensors: SensorMetrics::new(),
            network: NetworkMetrics::new(),
            gpu: if gpu_enabled {
                GpuMetrics::new()
            } else {
                GpuMetrics::disabled()
            },
            launchd: LaunchdMetrics::new(),
            processes: ProcessMetrics::new(default_sort, sort_ascending),
            hostname,
            os_name,
            os_version,
            kernel_version,
            uptime: 0,
            collector_status: CollectorStatus::Starting,
            last_refresh_duration: None,
            last_refresh_completed_at: None,
            system,
            tick_count: 0,
        }
    }

    pub fn refresh(&mut self) {
        let started = Instant::now();
        self.tick_count += 1;

        // Refresh CPU and memory every tick
        self.system.refresh_cpu_all();
        self.system.refresh_memory();
        self.system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::everything(),
        );

        self.cpu.update(&self.system);
        self.memory.update(&self.system);
        self.processes.update(&self.system);
        self.network.update();
        self.gpu.update();

        // Refresh slower hardware/list metadata less frequently.
        if self.tick_count.is_multiple_of(10) {
            self.disk.update_full();
            self.battery.update();
            self.sensors.update();
            self.launchd.update();
        } else {
            self.disk.update_io();
        }

        self.uptime = System::uptime();
        self.last_refresh_duration = Some(started.elapsed());
        self.last_refresh_completed_at = Some(SystemTime::now());
        self.collector_status = CollectorStatus::Ok;
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

#[cfg(test)]
mod tests {
    use super::CollectorStatus;

    #[test]
    fn collector_status_has_stable_labels() {
        assert_eq!(CollectorStatus::Starting.as_str(), "starting");
        assert_eq!(CollectorStatus::Ok.as_str(), "ok");
    }
}
