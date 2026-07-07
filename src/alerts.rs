use std::collections::{HashMap, HashSet};
use std::time::Instant;

use serde::Serialize;

use crate::config::AlertConfig;
use crate::metrics::SystemMetrics;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Alert {
    pub key: String,
    pub label: String,
    pub value: f32,
    pub threshold: f32,
    pub unit: AlertUnit,
    pub severity: AlertSeverity,
    pub active_seconds: u64,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
pub enum AlertSeverity {
    Warning,
    Critical,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
pub enum AlertUnit {
    Percent,
    Celsius,
}

#[derive(Debug, Clone)]
struct AlertCandidate {
    key: String,
    label: String,
    value: f32,
    threshold: f32,
    unit: AlertUnit,
    severity: AlertSeverity,
}

#[derive(Debug, Default)]
pub struct AlertEngine {
    first_seen: HashMap<String, Instant>,
}

impl AlertEngine {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn evaluate(
        &mut self,
        metrics: &SystemMetrics,
        config: &AlertConfig,
        now: Instant,
    ) -> Vec<Alert> {
        if !config.enabled {
            self.first_seen.clear();
            return Vec::new();
        }

        let candidates = alert_candidates(metrics, config);
        self.promote_candidates(candidates, config.min_duration_seconds, now)
    }

    fn promote_candidates(
        &mut self,
        candidates: Vec<AlertCandidate>,
        min_duration_seconds: u64,
        now: Instant,
    ) -> Vec<Alert> {
        let active_keys: HashSet<String> = candidates
            .iter()
            .map(|candidate| candidate.key.clone())
            .collect();
        self.first_seen
            .retain(|key, _first_seen| active_keys.contains(key));

        let mut alerts = Vec::new();
        for candidate in candidates {
            let first_seen = *self.first_seen.entry(candidate.key.clone()).or_insert(now);
            let active_seconds = now.duration_since(first_seen).as_secs();
            if active_seconds < min_duration_seconds {
                continue;
            }

            alerts.push(Alert {
                key: candidate.key,
                label: candidate.label,
                value: candidate.value,
                threshold: candidate.threshold,
                unit: candidate.unit,
                severity: candidate.severity,
                active_seconds,
            });
        }
        alerts
    }
}

fn alert_candidates(metrics: &SystemMetrics, config: &AlertConfig) -> Vec<AlertCandidate> {
    let mut alerts = Vec::new();
    push_percent_candidate(
        &mut alerts,
        "cpu",
        "CPU",
        metrics.cpu.global_usage,
        config.cpu_percent,
    );
    push_percent_candidate(
        &mut alerts,
        "memory",
        "Memory",
        metrics.memory.mem_usage_percent,
        config.memory_percent,
    );
    push_percent_candidate(
        &mut alerts,
        "swap",
        "Swap",
        metrics.memory.swap_usage_percent,
        config.swap_percent,
    );

    for disk in &metrics.disk.disks {
        push_percent_candidate(
            &mut alerts,
            &format!("disk:{}", disk.mount_point),
            &format!("Disk {}", disk.mount_point),
            disk.usage_percent,
            config.disk_used_percent,
        );
    }

    for gpu in &metrics.gpu.devices {
        if let Some(temp) = gpu.temperature_edge.or(gpu.temperature_junction) {
            push_temperature_candidate(
                &mut alerts,
                &format!("gpu-temp:{}", gpu.name),
                &format!("GPU {}", gpu.name),
                temp,
                config.gpu_temperature_c,
                config.gpu_temperature_c + 10.0,
            );
        }
        push_percent_candidate(
            &mut alerts,
            &format!("gpu-vram:{}", gpu.name),
            &format!("GPU VRAM {}", gpu.name),
            gpu.vram_usage_percent,
            config.gpu_vram_percent,
        );
    }

    for sensor in &metrics.sensors.components {
        if let Some(temp) = sensor.temperature {
            let critical_threshold = sensor
                .critical
                .unwrap_or(config.sensor_critical_c)
                .min(config.sensor_critical_c);
            let warning_threshold = config.sensor_warm_c.min(critical_threshold);
            push_temperature_candidate(
                &mut alerts,
                &format!("sensor:{}", sensor.label),
                &sensor.label,
                temp,
                warning_threshold,
                critical_threshold,
            );
        }
    }

    for battery in &metrics.battery.batteries {
        if let Some(capacity) = battery.capacity_percent {
            push_low_percent_candidate(
                &mut alerts,
                &format!("battery-low:{}", battery.name),
                &format!("Battery {}", battery.name),
                capacity,
                config.battery_low_percent,
            );
        }
        if let Some(health) = battery.health_percent {
            push_low_percent_candidate(
                &mut alerts,
                &format!("battery-health:{}", battery.name),
                &format!("Battery health {}", battery.name),
                health,
                config.battery_health_percent,
            );
        }
    }

    alerts
}

fn push_percent_candidate(
    alerts: &mut Vec<AlertCandidate>,
    key: &str,
    label: &str,
    value: f32,
    threshold: f32,
) {
    if value >= threshold {
        alerts.push(AlertCandidate {
            key: key.to_string(),
            label: label.to_string(),
            value,
            threshold,
            unit: AlertUnit::Percent,
            severity: severity_for_percent(value, threshold),
        });
    }
}

fn push_low_percent_candidate(
    alerts: &mut Vec<AlertCandidate>,
    key: &str,
    label: &str,
    value: f32,
    threshold: f32,
) {
    if value <= threshold {
        alerts.push(AlertCandidate {
            key: key.to_string(),
            label: label.to_string(),
            value,
            threshold,
            unit: AlertUnit::Percent,
            severity: if value <= threshold / 2.0 {
                AlertSeverity::Critical
            } else {
                AlertSeverity::Warning
            },
        });
    }
}

fn push_temperature_candidate(
    alerts: &mut Vec<AlertCandidate>,
    key: &str,
    label: &str,
    value: f32,
    threshold: f32,
    critical_threshold: f32,
) {
    if value >= threshold {
        alerts.push(AlertCandidate {
            key: key.to_string(),
            label: label.to_string(),
            value,
            threshold,
            unit: AlertUnit::Celsius,
            severity: if value >= critical_threshold {
                AlertSeverity::Critical
            } else {
                AlertSeverity::Warning
            },
        });
    }
}

fn severity_for_percent(value: f32, threshold: f32) -> AlertSeverity {
    if value >= (threshold + 10.0).min(100.0) {
        AlertSeverity::Critical
    } else {
        AlertSeverity::Warning
    }
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, Instant};

    use super::{severity_for_percent, AlertCandidate, AlertEngine, AlertSeverity, AlertUnit};

    #[test]
    fn percent_severity_promotes_above_threshold_margin() {
        assert_eq!(severity_for_percent(90.0, 85.0), AlertSeverity::Warning);
        assert_eq!(severity_for_percent(96.0, 85.0), AlertSeverity::Critical);
        assert_eq!(severity_for_percent(100.0, 95.0), AlertSeverity::Critical);
    }

    #[test]
    fn engine_waits_for_min_duration_and_clears_on_recovery() {
        let start = Instant::now();
        let mut engine = AlertEngine::new();
        let candidate = || {
            vec![AlertCandidate {
                key: "cpu".to_string(),
                label: "CPU".to_string(),
                value: 95.0,
                threshold: 90.0,
                unit: AlertUnit::Percent,
                severity: AlertSeverity::Warning,
            }]
        };

        assert!(engine.promote_candidates(candidate(), 10, start).is_empty());
        assert!(engine
            .promote_candidates(candidate(), 10, start + Duration::from_secs(9))
            .is_empty());
        assert_eq!(
            engine
                .promote_candidates(candidate(), 10, start + Duration::from_secs(10))
                .len(),
            1
        );

        assert!(engine
            .promote_candidates(Vec::new(), 10, start + Duration::from_secs(11))
            .is_empty());
        assert!(engine
            .promote_candidates(candidate(), 10, start + Duration::from_secs(12))
            .is_empty());
    }
}
