use sysinfo::Components;

#[derive(Debug, Clone)]
pub struct SensorInfo {
    pub label: String,
    pub temperature: Option<f32>,
    pub max: Option<f32>,
    pub critical: Option<f32>,
}

pub struct SensorMetrics {
    pub components: Vec<SensorInfo>,
    components_handle: Components,
}

impl std::fmt::Debug for SensorMetrics {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SensorMetrics")
            .field("components", &self.components)
            .finish()
    }
}

impl SensorMetrics {
    pub fn new() -> Self {
        let components_handle = Components::new_with_refreshed_list();
        let mut metrics = Self {
            components: Vec::new(),
            components_handle,
        };
        metrics.sync_components();
        metrics
    }

    pub fn update(&mut self) {
        self.components_handle.refresh(true);
        self.sync_components();
    }

    fn sync_components(&mut self) {
        self.components = self
            .components_handle
            .iter()
            .map(|component| SensorInfo {
                label: component.label().to_string(),
                temperature: finite_temperature(component.temperature()),
                max: finite_temperature(component.max()),
                critical: finite_temperature(component.critical()),
            })
            .collect();
        self.components.sort_by(|a, b| {
            b.temperature
                .partial_cmp(&a.temperature)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
    }

    pub fn highest_temperature(&self) -> Option<f32> {
        self.components
            .iter()
            .filter_map(|component| component.temperature)
            .max_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal))
    }
}

fn finite_temperature(temperature: Option<f32>) -> Option<f32> {
    temperature.filter(|value| value.is_finite())
}

pub fn temperature_status(temperature: Option<f32>, critical: Option<f32>) -> SensorStatus {
    let Some(temperature) = temperature else {
        return SensorStatus::Unknown;
    };

    if critical.is_some_and(|critical| temperature >= critical) || temperature >= 90.0 {
        SensorStatus::Critical
    } else if temperature >= 75.0 {
        SensorStatus::Warm
    } else {
        SensorStatus::Normal
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SensorStatus {
    Normal,
    Warm,
    Critical,
    Unknown,
}

#[cfg(test)]
mod tests {
    use super::{finite_temperature, temperature_status, SensorStatus};

    #[test]
    fn finite_temperature_drops_nan_values() {
        assert_eq!(finite_temperature(Some(f32::NAN)), None);
        assert_eq!(finite_temperature(Some(42.0)), Some(42.0));
    }

    #[test]
    fn temperature_status_uses_critical_and_warm_thresholds() {
        assert_eq!(temperature_status(None, None), SensorStatus::Unknown);
        assert_eq!(temperature_status(Some(45.0), None), SensorStatus::Normal);
        assert_eq!(temperature_status(Some(80.0), None), SensorStatus::Warm);
        assert_eq!(temperature_status(Some(92.0), None), SensorStatus::Critical);
        assert_eq!(
            temperature_status(Some(70.0), Some(70.0)),
            SensorStatus::Critical
        );
    }
}
