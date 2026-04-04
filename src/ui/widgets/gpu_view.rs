use iced::widget::{column, container, row, text};
use iced::{Element, Length, Padding};

use crate::metrics::gpu::{self, GpuMetrics};
use crate::theme::colors;
use crate::ui::widgets::gauge::gauge_view;
use crate::ui::widgets::graph::graph_view;

pub fn gpu_panel_view<'a, Message: 'a>(gpu: &GpuMetrics) -> Element<'a, Message> {
    if !gpu.available || gpu.devices.is_empty() {
        return container(
            column![
                text("GPU").size(14).color(colors::ACCENT_GREEN),
                text("No AMD GPU detected")
                    .size(12)
                    .color(colors::TEXT_DIM),
                text("(AMD sysfs monitoring requires Linux)")
                    .size(10)
                    .color(colors::TEXT_DIM),
            ]
            .spacing(4),
        )
        .padding(Padding::from([8, 12]))
        .style(|_theme: &iced::Theme| container::Style {
            background: Some(colors::SURFACE.into()),
            border: iced::Border {
                color: colors::SURFACE_BORDER,
                width: 1.0,
                radius: 6.0.into(),
            },
            ..Default::default()
        })
        .width(Length::Fill)
        .into();
    }

    let mut panels: Vec<Element<'a, Message>> = Vec::new();

    for dev in &gpu.devices {
        let title = text(format!("GPU — {}", dev.name))
            .size(14)
            .color(colors::ACCENT_GREEN);

        // Gauges: GPU usage + VRAM usage
        let gpu_gauge = gauge_view(
            dev.gpu_usage,
            colors::ACCENT_GREEN,
            "GPU",
            &format!("{:.0}%", dev.gpu_usage),
        );
        let vram_gauge = gauge_view(
            dev.vram_usage_percent,
            colors::ACCENT_MAGENTA,
            "VRAM",
            &format!(
                "{} / {}",
                gpu::format_vram(dev.vram_used),
                gpu::format_vram(dev.vram_total),
            ),
        );
        let gauges = row![gpu_gauge, vram_gauge]
            .spacing(12)
            .align_y(iced::Alignment::Center);

        // Stats row
        let mut stats: Vec<Element<'a, Message>> = Vec::new();

        if let Some(temp) = dev.temperature_edge {
            let temp_color = colors::heat_color((temp / 100.0 * 100.0).min(100.0));
            stats.push(
                text(format!("Edge: {:.0}°C", temp))
                    .size(11)
                    .color(temp_color)
                    .into(),
            );
        }
        if let Some(temp) = dev.temperature_junction {
            let temp_color = colors::heat_color((temp / 110.0 * 100.0).min(100.0));
            stats.push(
                text(format!("Junction: {:.0}°C", temp))
                    .size(11)
                    .color(temp_color)
                    .into(),
            );
        }
        if let Some(clock) = dev.gpu_clock_mhz {
            stats.push(
                text(format!("SCLK: {} MHz", clock))
                    .size(11)
                    .color(colors::ACCENT_CYAN)
                    .into(),
            );
        }
        if let Some(clock) = dev.vram_clock_mhz {
            stats.push(
                text(format!("MCLK: {} MHz", clock))
                    .size(11)
                    .color(colors::ACCENT_BLUE)
                    .into(),
            );
        }
        if let Some(power) = dev.power_watts {
            let cap_str = dev
                .power_cap_watts
                .map(|c| format!(" / {:.0}W", c))
                .unwrap_or_default();
            stats.push(
                text(format!("Power: {:.1}W{}", power, cap_str))
                    .size(11)
                    .color(colors::ACCENT_ORANGE)
                    .into(),
            );
        }
        if let Some(rpm) = dev.fan_rpm {
            let max_str = dev
                .fan_max_rpm
                .map(|m| format!(" / {} RPM", m))
                .unwrap_or_default();
            stats.push(
                text(format!("Fan: {} RPM{}", rpm, max_str))
                    .size(11)
                    .color(colors::TEXT_SECONDARY)
                    .into(),
            );
        }

        let mut stats_row = row![].spacing(12);
        for stat in stats {
            stats_row = stats_row.push(stat);
        }

        // GPU usage graph
        let gpu_graph = graph_view(
            &dev.gpu_history,
            100.0,
            colors::ACCENT_GREEN,
            "GPU Utilization",
            &format!("{:.0}%", dev.gpu_usage),
        );

        // VRAM usage graph
        let vram_graph = graph_view(
            &dev.vram_history,
            100.0,
            colors::ACCENT_MAGENTA,
            "VRAM Usage",
            &format!(
                "{:.0}% — {}",
                dev.vram_usage_percent,
                gpu::format_vram(dev.vram_used),
            ),
        );

        // Temperature graph (if available)
        let mut gpu_col = column![title, gauges, stats_row, gpu_graph, vram_graph].spacing(6);

        if !dev.temp_history.is_empty() {
            let max_temp = dev
                .temp_history
                .iter()
                .cloned()
                .fold(80.0_f32, f32::max);
            let current_temp = dev.temperature_edge.or(dev.temperature_junction).unwrap_or(0.0);
            let temp_graph = graph_view(
                &dev.temp_history,
                max_temp.max(1.0),
                colors::ACCENT_ORANGE,
                "Temperature",
                &format!("{:.0}°C", current_temp),
            );
            gpu_col = gpu_col.push(temp_graph);
        }

        // Power graph (if available)
        if !dev.power_history.is_empty() {
            let max_power = dev
                .power_cap_watts
                .unwrap_or_else(|| {
                    dev.power_history
                        .iter()
                        .cloned()
                        .fold(100.0_f32, f32::max)
                });
            let current_power = dev.power_watts.unwrap_or(0.0);
            let power_graph = graph_view(
                &dev.power_history,
                max_power.max(1.0),
                colors::ACCENT_YELLOW,
                "Power Draw",
                &format!("{:.1}W", current_power),
            );
            gpu_col = gpu_col.push(power_graph);
        }

        panels.push(gpu_col.into());
    }

    container(column(panels).spacing(8))
        .padding(Padding::from([8, 12]))
        .style(|_theme: &iced::Theme| container::Style {
            background: Some(colors::SURFACE.into()),
            border: iced::Border {
                color: colors::SURFACE_BORDER,
                width: 1.0,
                radius: 6.0.into(),
            },
            ..Default::default()
        })
        .width(Length::Fill)
        .into()
}
