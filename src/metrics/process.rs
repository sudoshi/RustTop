use sysinfo::{System, Pid};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SortField {
    Pid,
    Name,
    Cpu,
    Memory,
    Status,
}

#[derive(Debug, Clone)]
pub struct ProcessInfo {
    pub pid: u32,
    pub name: String,
    pub cpu_usage: f32,
    pub memory: u64,
    pub status: String,
    pub user: String,
    pub virtual_memory: u64,
    pub run_time: u64,
    pub cmd: String,
}

#[derive(Debug, Clone)]
pub struct ProcessMetrics {
    pub processes: Vec<ProcessInfo>,
    pub total_count: usize,
    pub running_count: usize,
    pub sleeping_count: usize,
    pub sort_field: SortField,
    pub sort_ascending: bool,
    pub filter: String,
}

impl ProcessMetrics {
    pub fn new() -> Self {
        Self {
            processes: Vec::new(),
            total_count: 0,
            running_count: 0,
            sleeping_count: 0,
            sort_field: SortField::Cpu,
            sort_ascending: false,
            filter: String::new(),
        }
    }

    pub fn update(&mut self, sys: &System) {
        self.processes = sys
            .processes()
            .iter()
            .map(|(pid, proc_info)| {
                let status_str = format!("{:?}", proc_info.status());
                ProcessInfo {
                    pid: pid.as_u32(),
                    name: proc_info.name().to_string_lossy().to_string(),
                    cpu_usage: proc_info.cpu_usage(),
                    memory: proc_info.memory(),
                    status: status_str,
                    user: proc_info
                        .user_id()
                        .map(|uid| format!("{uid:?}"))
                        .unwrap_or_default(),
                    virtual_memory: proc_info.virtual_memory(),
                    run_time: proc_info.run_time(),
                    cmd: proc_info.cmd().iter().map(|s| s.to_string_lossy().to_string()).collect::<Vec<_>>().join(" "),
                }
            })
            .collect();

        self.total_count = self.processes.len();
        self.running_count = self
            .processes
            .iter()
            .filter(|p| p.status.contains("Run"))
            .count();
        self.sleeping_count = self
            .processes
            .iter()
            .filter(|p| p.status.contains("Sleep"))
            .count();

        self.sort_processes();
    }

    fn sort_processes(&mut self) {
        let ascending = self.sort_ascending;
        match self.sort_field {
            SortField::Pid => self.processes.sort_by(|a, b| {
                if ascending { a.pid.cmp(&b.pid) } else { b.pid.cmp(&a.pid) }
            }),
            SortField::Name => self.processes.sort_by(|a, b| {
                if ascending {
                    a.name.to_lowercase().cmp(&b.name.to_lowercase())
                } else {
                    b.name.to_lowercase().cmp(&a.name.to_lowercase())
                }
            }),
            SortField::Cpu => self.processes.sort_by(|a, b| {
                if ascending {
                    a.cpu_usage.partial_cmp(&b.cpu_usage).unwrap_or(std::cmp::Ordering::Equal)
                } else {
                    b.cpu_usage.partial_cmp(&a.cpu_usage).unwrap_or(std::cmp::Ordering::Equal)
                }
            }),
            SortField::Memory => self.processes.sort_by(|a, b| {
                if ascending { a.memory.cmp(&b.memory) } else { b.memory.cmp(&a.memory) }
            }),
            SortField::Status => self.processes.sort_by(|a, b| {
                if ascending { a.status.cmp(&b.status) } else { b.status.cmp(&a.status) }
            }),
        }
    }

    pub fn filtered_processes(&self) -> Vec<&ProcessInfo> {
        if self.filter.is_empty() {
            self.processes.iter().collect()
        } else {
            let filter_lower = self.filter.to_lowercase();
            self.processes
                .iter()
                .filter(|p| {
                    p.name.to_lowercase().contains(&filter_lower)
                        || p.pid.to_string().contains(&filter_lower)
                        || p.cmd.to_lowercase().contains(&filter_lower)
                })
                .collect()
        }
    }

    pub fn kill_process(&self, pid: u32) -> bool {
        let sys = System::new();
        if let Some(process) = sys.process(Pid::from_u32(pid)) {
            process.kill()
        } else {
            false
        }
    }

    pub fn toggle_sort(&mut self, field: SortField) {
        if self.sort_field == field {
            self.sort_ascending = !self.sort_ascending;
        } else {
            self.sort_field = field;
            self.sort_ascending = false;
        }
        self.sort_processes();
    }
}
