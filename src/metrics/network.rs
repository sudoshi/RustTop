use sysinfo::Networks;

const HISTORY_SIZE: usize = 120;

#[derive(Debug, Clone)]
pub struct NetworkInterface {
    pub name: String,
    pub received_bytes: u64,
    pub transmitted_bytes: u64,
    pub rx_rate: u64, // bytes per second
    pub tx_rate: u64,
}

#[derive(Debug, Clone)]
pub struct NetworkMetrics {
    pub interfaces: Vec<NetworkInterface>,
    pub total_rx_rate: u64,
    pub total_tx_rate: u64,
    pub rx_history: Vec<f64>,
    pub tx_history: Vec<f64>,
    prev_received: std::collections::HashMap<String, u64>,
    prev_transmitted: std::collections::HashMap<String, u64>,
}

impl NetworkMetrics {
    pub fn new() -> Self {
        Self {
            interfaces: Vec::new(),
            total_rx_rate: 0,
            total_tx_rate: 0,
            rx_history: Vec::with_capacity(HISTORY_SIZE),
            tx_history: Vec::with_capacity(HISTORY_SIZE),
            prev_received: std::collections::HashMap::new(),
            prev_transmitted: std::collections::HashMap::new(),
        }
    }

    pub fn update(&mut self) {
        let networks = Networks::new_with_refreshed_list();
        let mut total_rx: u64 = 0;
        let mut total_tx: u64 = 0;

        self.interfaces = networks
            .iter()
            .map(|(name, data)| {
                let received = data.total_received();
                let transmitted = data.total_transmitted();

                let prev_rx = self.prev_received.get(name).copied().unwrap_or(received);
                let prev_tx = self.prev_transmitted.get(name).copied().unwrap_or(transmitted);

                let rx_rate = received.saturating_sub(prev_rx);
                let tx_rate = transmitted.saturating_sub(prev_tx);

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
        if self.rx_history.len() > HISTORY_SIZE {
            self.rx_history.remove(0);
        }
        self.tx_history.push(total_tx as f64);
        if self.tx_history.len() > HISTORY_SIZE {
            self.tx_history.remove(0);
        }
    }

    pub fn format_rate(bytes_per_sec: u64) -> String {
        const KIB: f64 = 1024.0;
        const MIB: f64 = KIB * 1024.0;
        const GIB: f64 = MIB * 1024.0;
        let b = bytes_per_sec as f64;

        if b >= GIB {
            format!("{:.1} GiB/s", b / GIB)
        } else if b >= MIB {
            format!("{:.1} MiB/s", b / MIB)
        } else if b >= KIB {
            format!("{:.1} KiB/s", b / KIB)
        } else {
            format!("{:.0} B/s", b)
        }
    }
}
