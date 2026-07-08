use std::env;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LaunchdJob {
    pub label: String,
    pub domain: String,
    pub kind: String,
    pub path: String,
    pub state: String,
}

#[derive(Debug, Clone, Default)]
pub struct LaunchdMetrics {
    pub jobs: Vec<LaunchdJob>,
}

impl LaunchdMetrics {
    pub fn new() -> Self {
        let mut metrics = Self::default();
        metrics.update();
        metrics
    }

    pub fn update(&mut self) {
        self.jobs = discover_launchd_jobs();
    }
}

fn discover_launchd_jobs() -> Vec<LaunchdJob> {
    if !cfg!(target_os = "macos") {
        return Vec::new();
    }

    discover_launchd_jobs_from_roots(default_launchd_roots())
}

fn default_launchd_roots() -> Vec<LaunchdRoot> {
    let mut roots = vec![
        LaunchdRoot::new(
            PathBuf::from("/System/Library/LaunchDaemons"),
            "System",
            "Daemon",
        ),
        LaunchdRoot::new(
            PathBuf::from("/System/Library/LaunchAgents"),
            "System",
            "Agent",
        ),
        LaunchdRoot::new(PathBuf::from("/Library/LaunchDaemons"), "Global", "Daemon"),
        LaunchdRoot::new(PathBuf::from("/Library/LaunchAgents"), "Global", "Agent"),
    ];

    if let Some(home) = env::var_os("HOME") {
        roots.push(LaunchdRoot::new(
            PathBuf::from(home).join("Library").join("LaunchAgents"),
            "User",
            "Agent",
        ));
    }

    roots
}

fn discover_launchd_jobs_from_roots(roots: Vec<LaunchdRoot>) -> Vec<LaunchdJob> {
    let mut jobs: Vec<LaunchdJob> = roots
        .iter()
        .flat_map(discover_launchd_jobs_in_root)
        .collect();

    jobs.sort_by(|lhs, rhs| {
        lhs.domain
            .cmp(&rhs.domain)
            .then(lhs.kind.cmp(&rhs.kind))
            .then(lhs.label.cmp(&rhs.label))
            .then(lhs.path.cmp(&rhs.path))
    });
    jobs
}

fn discover_launchd_jobs_in_root(root: &LaunchdRoot) -> Vec<LaunchdJob> {
    let entries = match fs::read_dir(&root.path) {
        Ok(entries) => entries,
        Err(_) => return Vec::new(),
    };

    entries
        .filter_map(Result::ok)
        .filter_map(|entry| launchd_job_from_path(entry.path(), root))
        .collect()
}

fn launchd_job_from_path(path: PathBuf, root: &LaunchdRoot) -> Option<LaunchdJob> {
    let metadata = fs::metadata(&path).ok()?;
    if !metadata.is_file() || path.extension().and_then(|value| value.to_str()) != Some("plist") {
        return None;
    }

    Some(LaunchdJob {
        label: launchd_label_from_path(&path)?,
        domain: root.domain.to_string(),
        kind: root.kind.to_string(),
        path: path.to_string_lossy().to_string(),
        state: "Installed".to_string(),
    })
}

fn launchd_label_from_path(path: &Path) -> Option<String> {
    path.file_stem()
        .and_then(|value| value.to_str())
        .map(str::trim)
        .filter(|label| !label.is_empty())
        .map(ToOwned::to_owned)
}

#[derive(Debug, Clone)]
struct LaunchdRoot {
    path: PathBuf,
    domain: &'static str,
    kind: &'static str,
}

impl LaunchdRoot {
    fn new(path: PathBuf, domain: &'static str, kind: &'static str) -> Self {
        Self { path, domain, kind }
    }
}

#[cfg(test)]
mod tests {
    use super::{discover_launchd_jobs_from_roots, LaunchdRoot};
    use std::fs;
    use std::path::PathBuf;

    #[test]
    fn fixture_roots_discover_only_plist_files() {
        let root = temp_dir("rusttop-launchd-fixture");
        let agents = root.join("LaunchAgents");
        fs::create_dir_all(&agents).unwrap();
        fs::write(agents.join("com.example.agent.plist"), "<plist />").unwrap();
        fs::write(agents.join("README.txt"), "not a launchd job").unwrap();
        fs::create_dir_all(agents.join("com.example.directory.plist")).unwrap();

        let jobs = discover_launchd_jobs_from_roots(vec![LaunchdRoot::new(
            agents.clone(),
            "User",
            "Agent",
        )]);

        assert_eq!(jobs.len(), 1);
        assert_eq!(jobs[0].label, "com.example.agent");
        assert_eq!(jobs[0].domain, "User");
        assert_eq!(jobs[0].kind, "Agent");
        assert_eq!(jobs[0].state, "Installed");

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn missing_roots_are_empty() {
        let jobs = discover_launchd_jobs_from_roots(vec![LaunchdRoot::new(
            PathBuf::from("/path/that/does/not/exist"),
            "System",
            "Daemon",
        )]);

        assert!(jobs.is_empty());
    }

    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }
}
