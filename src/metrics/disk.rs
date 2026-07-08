use std::time::{Duration, Instant};

use sysinfo::{DiskRefreshKind, Disks};

#[derive(Debug, Clone)]
pub struct DiskInfo {
    pub mount_point: String,
    pub total_space: u64,
    pub available_space: u64,
    pub used_space: u64,
    pub usage_percent: f32,
    pub fs_type: String,
    pub read_rate: u64,
    pub write_rate: u64,
}

#[derive(Debug)]
pub struct DiskMetrics {
    pub disks: Vec<DiskInfo>,
    disks_handle: Disks,
    last_refresh: Option<Instant>,
}

impl DiskMetrics {
    pub fn new() -> Self {
        let disks_handle = Disks::new_with_refreshed_list();
        let mut metrics = Self {
            disks: Vec::new(),
            disks_handle,
            last_refresh: Some(Instant::now()),
        };
        metrics.sync_disk_rows(Duration::ZERO);
        metrics
    }

    pub fn update_io(&mut self) {
        self.refresh_with(disk_refresh_kind(false), false);
    }

    pub fn update_full(&mut self) {
        self.refresh_with(disk_refresh_kind(true), true);
    }

    fn refresh_with(&mut self, refresh_kind: DiskRefreshKind, remove_not_listed_disks: bool) {
        let now = Instant::now();
        let elapsed = self
            .last_refresh
            .map(|last_refresh| now.duration_since(last_refresh))
            .unwrap_or(Duration::ZERO);
        self.disks_handle
            .refresh_specifics(remove_not_listed_disks, refresh_kind);
        self.last_refresh = Some(now);
        self.sync_disk_rows(elapsed);
    }

    fn sync_disk_rows(&mut self, elapsed: Duration) {
        self.disks = self
            .disks_handle
            .iter()
            .filter_map(|d| {
                let mount_point = d.mount_point().to_string_lossy().to_string();
                let fs_type = d.file_system().to_string_lossy().to_string();
                if cfg!(target_os = "macos")
                    && should_skip_macos_apfs_system_volume(&mount_point, &fs_type)
                {
                    return None;
                }

                let total = d.total_space();
                let available = d.available_space();
                let used = total.saturating_sub(available);
                let usage = d.usage();
                Some(DiskInfo {
                    mount_point,
                    total_space: total,
                    available_space: available,
                    used_space: used,
                    usage_percent: if total > 0 {
                        (used as f32 / total as f32) * 100.0
                    } else {
                        0.0
                    },
                    fs_type,
                    read_rate: calculate_disk_rate(usage.read_bytes, elapsed),
                    write_rate: calculate_disk_rate(usage.written_bytes, elapsed),
                })
            })
            .collect();
    }
}

fn calculate_disk_rate(bytes: u64, elapsed: Duration) -> u64 {
    let elapsed_secs = elapsed.as_secs_f64();
    if elapsed_secs <= 0.0 {
        0
    } else {
        (bytes as f64 / elapsed_secs).round() as u64
    }
}

fn disk_refresh_kind(full_refresh: bool) -> DiskRefreshKind {
    if full_refresh {
        DiskRefreshKind::everything()
    } else {
        DiskRefreshKind::nothing().with_io_usage()
    }
}

fn should_skip_macos_apfs_system_volume(mount_point: &str, fs_type: &str) -> bool {
    if !fs_type.eq_ignore_ascii_case("apfs") {
        return false;
    }

    matches!(
        mount_point,
        "/System/Volumes/Data"
            | "/System/Volumes/Preboot"
            | "/System/Volumes/Update"
            | "/System/Volumes/VM"
            | "/System/Volumes/xarts"
            | "/System/Volumes/iSCPreboot"
            | "/System/Volumes/Hardware"
    )
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::{
        calculate_disk_rate, disk_refresh_kind, should_skip_macos_apfs_system_volume, DiskMetrics,
    };

    #[test]
    fn calculates_disk_rate_from_elapsed_time() {
        assert_eq!(calculate_disk_rate(4096, Duration::from_secs(2)), 2048);
        assert_eq!(calculate_disk_rate(1024, Duration::from_millis(500)), 2048);
    }

    #[test]
    fn zero_elapsed_disk_rate_is_zero() {
        assert_eq!(calculate_disk_rate(4096, Duration::ZERO), 0);
    }

    #[test]
    fn disk_metrics_start_with_zero_rates() {
        let metrics = DiskMetrics::new();

        assert!(metrics
            .disks
            .iter()
            .all(|disk| disk.read_rate == 0 && disk.write_rate == 0));
    }

    #[test]
    fn disk_refresh_kind_splits_io_and_full_refreshes() {
        let io = disk_refresh_kind(false);
        assert!(!io.storage());
        assert!(!io.kind());
        assert!(io.io_usage());

        let full = disk_refresh_kind(true);
        assert!(full.storage());
        assert!(full.kind());
        assert!(full.io_usage());
    }

    #[test]
    fn macos_apfs_system_volume_filter_keeps_user_mounts() {
        assert!(should_skip_macos_apfs_system_volume(
            "/System/Volumes/Data",
            "apfs"
        ));
        assert!(should_skip_macos_apfs_system_volume(
            "/System/Volumes/Preboot",
            "APFS"
        ));
        assert!(!should_skip_macos_apfs_system_volume("/", "apfs"));
        assert!(!should_skip_macos_apfs_system_volume(
            "/System/Volumes/Data",
            "ext4"
        ));
    }
}
