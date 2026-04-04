use std::time::Duration;

use iced::widget::{column, container, row, scrollable};
use iced::{Element, Length, Padding, Subscription, Theme};

use crate::metrics::SystemMetrics;
use crate::metrics::memory::MemoryMetrics;
use crate::metrics::process::SortField;
use crate::theme;
use crate::theme::colors;
use crate::ui::widgets::{
    cpu_cores::cpu_cores_view,
    disk_bar::disk_view,
    gpu_view::gpu_panel_view,
    graph::graph_view,
    header::header_view,
    network_view::network_view,
    process_table::process_table_view,
};

#[derive(Debug, Clone)]
pub enum Message {
    Tick,
    SortBy(SortField),
    FilterChanged(String),
}

pub struct RustTop {
    metrics: SystemMetrics,
}

impl RustTop {
    pub fn new() -> Self {
        let mut metrics = SystemMetrics::new();
        metrics.refresh();
        Self { metrics }
    }

    pub fn update(&mut self, message: Message) -> iced::Task<Message> {
        match message {
            Message::Tick => {
                self.metrics.refresh();
            }
            Message::SortBy(field) => {
                self.metrics.processes.toggle_sort(field);
            }
            Message::FilterChanged(filter) => {
                self.metrics.processes.filter = filter;
            }
        }
        iced::Task::none()
    }

    pub fn view(&self) -> Element<'_, Message> {
        let m = &self.metrics;

        // Header bar
        let header = header_view(m);

        // CPU graph
        let cpu_graph = graph_view(
            &m.cpu.history,
            100.0,
            colors::CPU_COLOR,
            &format!("CPU — {}", m.cpu.brand),
            &format!("{:.1}%", m.cpu.global_usage),
        );

        // Memory graph
        let mem_graph = graph_view(
            &m.memory.mem_history,
            100.0,
            colors::MEM_COLOR,
            "Memory",
            &format!(
                "{:.1}% — {} / {}",
                m.memory.mem_usage_percent,
                MemoryMetrics::format_bytes(m.memory.used_mem),
                MemoryMetrics::format_bytes(m.memory.total_mem),
            ),
        );

        // Per-core CPU view with btop-style dots
        let cores_view = cpu_cores_view(&m.cpu);

        // GPU panel
        let gpu_panel = gpu_panel_view(&m.gpu);

        // Network + Disk row
        let net_view = network_view(&m.network);
        let disks = disk_view(&m.disk);

        // Left panel: graphs + cores + GPU + network/disk
        let left_content = column![
            cpu_graph,
            cores_view,
            mem_graph,
            gpu_panel,
            row![
                container(net_view).width(Length::FillPortion(1)),
                container(disks).width(Length::FillPortion(1)),
            ]
            .spacing(8),
        ]
        .spacing(8);

        let left_panel = scrollable(left_content)
            .width(Length::FillPortion(3))
            .height(Length::Fill);

        // Right panel: process table
        let right_panel = container(process_table_view(&m.processes))
            .width(Length::FillPortion(2))
            .height(Length::Fill);

        // Main layout
        let content = column![
            header,
            container(
                row![left_panel, right_panel].spacing(8)
            )
            .padding(Padding::from([8, 12]))
            .width(Length::Fill)
            .height(Length::Fill),
        ]
        .spacing(0);

        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .style(|_theme: &Theme| container::Style {
                background: Some(colors::BACKGROUND.into()),
                ..Default::default()
            })
            .into()
    }

    pub fn subscription(&self) -> Subscription<Message> {
        iced::time::every(Duration::from_millis(500)).map(|_| Message::Tick)
    }

    pub fn theme(&self) -> Theme {
        theme::app_theme()
    }
}
