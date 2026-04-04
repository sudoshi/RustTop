use sysinfo::Disks;

#[derive(Debug, Clone)]
pub struct DiskInfo {
    pub name: String,
    pub mount_point: String,
    pub total_space: u64,
    pub available_space: u64,
    pub used_space: u64,
    pub usage_percent: f32,
    pub fs_type: String,
    pub is_removable: bool,
}

#[derive(Debug, Clone)]
pub struct DiskMetrics {
    pub disks: Vec<DiskInfo>,
}

impl DiskMetrics {
    pub fn new() -> Self {
        Self { disks: Vec::new() }
    }

    pub fn update(&mut self) {
        let disk_list = Disks::new_with_refreshed_list();
        self.disks = disk_list
            .iter()
            .map(|d| {
                let total = d.total_space();
                let available = d.available_space();
                let used = total.saturating_sub(available);
                DiskInfo {
                    name: d.name().to_string_lossy().to_string(),
                    mount_point: d.mount_point().to_string_lossy().to_string(),
                    total_space: total,
                    available_space: available,
                    used_space: used,
                    usage_percent: if total > 0 {
                        (used as f32 / total as f32) * 100.0
                    } else {
                        0.0
                    },
                    fs_type: d.file_system().to_string_lossy().to_string(),
                    is_removable: d.is_removable(),
                }
            })
            .collect();
    }
}
