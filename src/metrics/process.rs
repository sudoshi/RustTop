use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};

use sysinfo::{Pid, ProcessRefreshKind, ProcessesToUpdate, Signal, System};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SortField {
    Pid,
    Name,
    Cpu,
    Memory,
    Status,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProcessSignal {
    Term,
    Kill,
    Stop,
    Continue,
}

impl ProcessSignal {
    pub fn default_action() -> Self {
        if cfg!(target_os = "windows") {
            ProcessSignal::Kill
        } else {
            ProcessSignal::Term
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            ProcessSignal::Term => "TERM",
            ProcessSignal::Kill => "KILL",
            ProcessSignal::Stop => "STOP",
            ProcessSignal::Continue => "CONT",
        }
    }

    pub fn next(self) -> Self {
        match self {
            ProcessSignal::Term => ProcessSignal::Kill,
            ProcessSignal::Kill => ProcessSignal::Stop,
            ProcessSignal::Stop => ProcessSignal::Continue,
            ProcessSignal::Continue => ProcessSignal::Term,
        }
    }

    fn to_sysinfo(self) -> Signal {
        match self {
            ProcessSignal::Term => Signal::Term,
            ProcessSignal::Kill => Signal::Kill,
            ProcessSignal::Stop => Signal::Stop,
            ProcessSignal::Continue => Signal::Continue,
        }
    }
}

#[derive(Debug, Clone)]
pub struct ProcessInfo {
    pub pid: u32,
    pub parent_pid: Option<u32>,
    pub name: String,
    pub cpu_usage: f32,
    pub memory: u64,
    pub status: String,
    pub user: String,
    pub virtual_memory: u64,
    pub run_time: u64,
    pub start_time: u64,
    pub exe: Option<String>,
    pub cwd: Option<String>,
    pub thread_count: Option<usize>,
    pub depth: usize,
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
    pub tree_mode: bool,
}

impl ProcessMetrics {
    pub fn new(sort_field: SortField, sort_ascending: bool) -> Self {
        Self {
            processes: Vec::new(),
            total_count: 0,
            running_count: 0,
            sleeping_count: 0,
            sort_field,
            sort_ascending,
            filter: String::new(),
            tree_mode: false,
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
                    parent_pid: proc_info.parent().map(|pid| pid.as_u32()),
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
                    start_time: proc_info.start_time(),
                    exe: proc_info
                        .exe()
                        .map(|path| path.to_string_lossy().to_string()),
                    cwd: proc_info
                        .cwd()
                        .map(|path| path.to_string_lossy().to_string()),
                    thread_count: proc_info.tasks().map(|tasks| tasks.len()),
                    depth: 0,
                    cmd: proc_info
                        .cmd()
                        .iter()
                        .map(|s| s.to_string_lossy().to_string())
                        .collect::<Vec<_>>()
                        .join(" "),
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
        let field = self.sort_field.clone();
        self.processes
            .sort_by(|a, b| compare_processes(a, b, &field, ascending));

        if self.tree_mode {
            self.apply_tree_order();
        } else {
            for process in &mut self.processes {
                process.depth = 0;
            }
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

    pub fn signal_process(&self, pid: u32, signal: ProcessSignal) -> Option<bool> {
        let mut sys = System::new();
        let pid = Pid::from_u32(pid);
        sys.refresh_processes_specifics(
            ProcessesToUpdate::Some(&[pid]),
            true,
            ProcessRefreshKind::everything(),
        );
        sys.process(pid)
            .and_then(|process| process.kill_with(signal.to_sysinfo()))
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

    pub fn toggle_sort_direction(&mut self) {
        self.sort_ascending = !self.sort_ascending;
        self.sort_processes();
    }

    pub fn toggle_tree_mode(&mut self) {
        self.tree_mode = !self.tree_mode;
        self.sort_processes();
    }

    fn apply_tree_order(&mut self) {
        let known_pids: HashSet<u32> = self.processes.iter().map(|process| process.pid).collect();
        let mut children: HashMap<Option<u32>, Vec<ProcessInfo>> = HashMap::new();

        for process in self.processes.drain(..) {
            let parent_key = match process.parent_pid {
                Some(parent_pid) if known_pids.contains(&parent_pid) => Some(parent_pid),
                _ => None,
            };
            children.entry(parent_key).or_default().push(process);
        }

        let mut ordered = Vec::with_capacity(known_pids.len());
        append_tree_children(None, 0, &mut children, &mut ordered);

        for (_, mut remaining) in children {
            for process in &mut remaining {
                process.depth = 0;
            }
            ordered.extend(remaining);
        }

        self.processes = ordered;
    }
}

fn append_tree_children(
    parent_pid: Option<u32>,
    depth: usize,
    children: &mut HashMap<Option<u32>, Vec<ProcessInfo>>,
    ordered: &mut Vec<ProcessInfo>,
) {
    let Some(mut current_children) = children.remove(&parent_pid) else {
        return;
    };

    for mut child in current_children.drain(..) {
        child.depth = depth;
        let child_pid = child.pid;
        ordered.push(child);
        append_tree_children(Some(child_pid), depth + 1, children, ordered);
    }
}

fn compare_processes(
    a: &ProcessInfo,
    b: &ProcessInfo,
    field: &SortField,
    ascending: bool,
) -> Ordering {
    let ordering = match field {
        SortField::Pid => a.pid.cmp(&b.pid),
        SortField::Name => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
        SortField::Cpu => a
            .cpu_usage
            .partial_cmp(&b.cpu_usage)
            .unwrap_or(Ordering::Equal),
        SortField::Memory => a.memory.cmp(&b.memory),
        SortField::Status => a.status.cmp(&b.status),
    };

    if ascending {
        ordering
    } else {
        ordering.reverse()
    }
}

#[cfg(test)]
mod tests {
    use super::{ProcessInfo, ProcessMetrics, ProcessSignal, SortField};

    #[test]
    fn process_signal_cycles_through_safe_action_set() {
        assert_eq!(ProcessSignal::Term.label(), "TERM");
        assert_eq!(ProcessSignal::Term.next(), ProcessSignal::Kill);
        assert_eq!(ProcessSignal::Kill.next(), ProcessSignal::Stop);
        assert_eq!(ProcessSignal::Stop.next(), ProcessSignal::Continue);
        assert_eq!(ProcessSignal::Continue.next(), ProcessSignal::Term);
    }

    #[cfg(unix)]
    #[test]
    fn signal_process_can_kill_existing_process() {
        use std::process::Command;
        use std::thread;
        use std::time::Duration;

        let mut child = Command::new("sleep")
            .arg("30")
            .spawn()
            .expect("spawn sleep process");
        thread::sleep(Duration::from_millis(100));

        let processes = ProcessMetrics::new(SortField::Cpu, false);
        assert_eq!(
            processes.signal_process(child.id(), ProcessSignal::Kill),
            Some(true)
        );

        let _ = child.wait();
    }

    #[test]
    fn tree_mode_orders_children_under_parents() {
        let mut metrics = ProcessMetrics::new(SortField::Pid, true);
        metrics.processes = vec![
            process(3, Some(2), "grandchild"),
            process(1, None, "root"),
            process(2, Some(1), "child"),
            process(4, None, "other-root"),
        ];

        metrics.toggle_tree_mode();

        let pids: Vec<u32> = metrics
            .processes
            .iter()
            .map(|process| process.pid)
            .collect();
        let depths: Vec<usize> = metrics
            .processes
            .iter()
            .map(|process| process.depth)
            .collect();

        assert_eq!(pids, vec![1, 2, 3, 4]);
        assert_eq!(depths, vec![0, 1, 2, 0]);
    }

    #[test]
    fn flat_mode_resets_tree_depth() {
        let mut metrics = ProcessMetrics::new(SortField::Pid, true);
        metrics.processes = vec![process(2, Some(1), "child"), process(1, None, "root")];

        metrics.toggle_tree_mode();
        metrics.toggle_tree_mode();

        assert!(metrics.processes.iter().all(|process| process.depth == 0));
    }

    #[test]
    fn toggling_sort_direction_reorders_immediately() {
        let mut metrics = ProcessMetrics::new(SortField::Pid, true);
        metrics.processes = vec![process(2, None, "second"), process(1, None, "first")];

        metrics.toggle_sort_direction();

        let pids: Vec<u32> = metrics
            .processes
            .iter()
            .map(|process| process.pid)
            .collect();
        assert_eq!(pids, vec![2, 1]);
    }

    fn process(pid: u32, parent_pid: Option<u32>, name: &str) -> ProcessInfo {
        ProcessInfo {
            pid,
            parent_pid,
            name: name.to_string(),
            cpu_usage: 0.0,
            memory: 0,
            status: "Run".to_string(),
            user: String::new(),
            virtual_memory: 0,
            run_time: 0,
            start_time: 0,
            exe: None,
            cwd: None,
            thread_count: None,
            depth: 0,
            cmd: String::new(),
        }
    }
}
