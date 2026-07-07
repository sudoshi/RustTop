use std::time::{Duration, Instant};

use sysinfo::Networks;

use super::history::HistoryBuffer;
use super::units;

const HISTORY_SIZE: usize = 120;

#[derive(Debug, Clone)]
pub struct NetworkInterface {
    pub name: String,
    pub received_bytes: u64,
    pub transmitted_bytes: u64,
    pub rx_rate: u64, // bytes per second
    pub tx_rate: u64,
}

#[derive(Debug)]
pub struct NetworkMetrics {
    pub interfaces: Vec<NetworkInterface>,
    pub total_rx_rate: u64,
    pub total_tx_rate: u64,
    pub rx_history: HistoryBuffer<f64>,
    pub tx_history: HistoryBuffer<f64>,
    prev_received: std::collections::HashMap<String, u64>,
    prev_transmitted: std::collections::HashMap<String, u64>,
    networks: Networks,
    last_sample: Option<Instant>,
}

impl NetworkMetrics {
    pub fn new() -> Self {
        Self {
            interfaces: Vec::new(),
            total_rx_rate: 0,
            total_tx_rate: 0,
            rx_history: HistoryBuffer::new(HISTORY_SIZE),
            tx_history: HistoryBuffer::new(HISTORY_SIZE),
            prev_received: std::collections::HashMap::new(),
            prev_transmitted: std::collections::HashMap::new(),
            networks: Networks::new_with_refreshed_list(),
            last_sample: None,
        }
    }

    pub fn update(&mut self) {
        let now = Instant::now();
        let elapsed = self
            .last_sample
            .map(|last| now.saturating_duration_since(last))
            .unwrap_or(Duration::ZERO);
        self.last_sample = Some(now);
        self.networks.refresh(true);

        let mut total_rx: u64 = 0;
        let mut total_tx: u64 = 0;

        self.interfaces = self
            .networks
            .iter()
            .map(|(name, data)| {
                let received = data.total_received();
                let transmitted = data.total_transmitted();

                let prev_rx = self.prev_received.get(name).copied().unwrap_or(received);
                let prev_tx = self
                    .prev_transmitted
                    .get(name)
                    .copied()
                    .unwrap_or(transmitted);

                let rx_rate = calculate_counter_rate(prev_rx, received, elapsed);
                let tx_rate = calculate_counter_rate(prev_tx, transmitted, elapsed);

                self.prev_received.insert(name.clone(), received);
                self.prev_transmitted.insert(name.clone(), transmitted);

                total_rx += rx_rate;
                total_tx += tx_rate;

                NetworkInterface {
                    name: name.clone(),
                    received_bytes: received,
                    transmitted_bytes: transmitted,
                    rx_rate,
                    tx_rate,
                }
            })
            .collect();

        self.total_rx_rate = total_rx;
        self.total_tx_rate = total_tx;

        self.rx_history.push(total_rx as f64);
        self.tx_history.push(total_tx as f64);
    }

    pub fn format_rate(bytes_per_sec: u64) -> String {
        units::format_binary_rate(bytes_per_sec)
    }
}

pub(crate) fn calculate_rate(delta_bytes: u64, elapsed: Duration) -> u64 {
    let seconds = elapsed.as_secs_f64();
    if seconds <= 0.0 {
        0
    } else {
        (delta_bytes as f64 / seconds).round() as u64
    }
}

pub(crate) fn calculate_counter_rate(previous: u64, current: u64, elapsed: Duration) -> u64 {
    calculate_rate(current.saturating_sub(previous), elapsed)
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::{calculate_counter_rate, calculate_rate, NetworkMetrics};

    #[test]
    fn calculates_rates_from_elapsed_time() {
        assert_eq!(calculate_rate(512, Duration::from_millis(500)), 1024);
        assert_eq!(calculate_rate(1_000, Duration::from_secs(2)), 500);
        assert_eq!(calculate_rate(0, Duration::from_secs(2)), 0);
    }

    #[test]
    fn zero_elapsed_time_reports_zero_rate() {
        assert_eq!(calculate_rate(1_000, Duration::ZERO), 0);
    }

    #[test]
    fn counter_reset_reports_zero_rate() {
        assert_eq!(
            calculate_counter_rate(2_000, 1_000, Duration::from_secs(1)),
            0
        );
    }

    #[test]
    fn formats_rates_at_binary_boundaries() {
        assert_eq!(NetworkMetrics::format_rate(512), "512 B/s");
        assert_eq!(NetworkMetrics::format_rate(1024), "1.0 KiB/s");
        assert_eq!(NetworkMetrics::format_rate(1024 * 1024), "1.0 MiB/s");
        assert_eq!(NetworkMetrics::format_rate(1024 * 1024 * 1024), "1.0 GiB/s");
    }
}
