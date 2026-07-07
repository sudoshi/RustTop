use iced::widget::{column, container, row, text, Space};
use iced::{Element, Length, Padding};

use crate::metrics::SystemMetrics;
use crate::theme::colors;

pub fn header_view<'a, Message: 'a>(metrics: &SystemMetrics) -> Element<'a, Message> {
    let host_info = text(format!(
        "{}  |  {} {}  |  Kernel {}",
        metrics.hostname, metrics.os_name, metrics.os_version, metrics.kernel_version,
    ))
    .size(12)
    .color(colors::TEXT_SECONDARY);

    let uptime_text = text(format!("Uptime: {}", metrics.format_uptime()))
        .size(12)
        .color(colors::TEXT_DIM);
    let refresh_text = text(format!(
        "Collector: {}{}",
        metrics.collector_status.as_str(),
        metrics
            .last_refresh_duration
            .map(|duration| format!("  |  {:.1} ms", duration.as_secs_f64() * 1000.0))
            .unwrap_or_default(),
    ))
    .size(12)
    .color(colors::TEXT_DIM);

    let title = text("RustTop").size(18).color(colors::ACCENT_CYAN);

    let proc_summary = text(format!(
        "Tasks: {}  |  Running: {}  |  Sleeping: {}",
        metrics.processes.total_count,
        metrics.processes.running_count,
        metrics.processes.sleeping_count,
    ))
    .size(12)
    .color(colors::TEXT_SECONDARY);

    let left = column![title, host_info].spacing(2);
    let right = column![uptime_text, proc_summary, refresh_text]
        .spacing(2)
        .align_x(iced::Alignment::End);

    container(row![left, Space::with_width(Length::Fill), right].align_y(iced::Alignment::Center))
        .padding(Padding::from([8, 16]))
        .style(|_theme: &iced::Theme| container::Style {
            background: Some(colors::SURFACE.into()),
            border: iced::Border {
                color: colors::SURFACE_BORDER,
                width: 0.0,
                radius: 0.0.into(),
            },
            ..Default::default()
        })
        .width(Length::Fill)
        .into()
}
