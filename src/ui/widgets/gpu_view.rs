use iced::widget::canvas::{self, Canvas, Frame, Geometry, Path, Stroke};
use iced::widget::{column, container, row, text};
use iced::{mouse, Element, Length, Padding, Rectangle, Renderer, Theme};

use crate::metrics::gpu::{self, GpuMetrics};
use crate::theme::colors;
use crate::ui::widgets::graph::graph_view;

/// Compact horizontal bar for GPU metrics
#[derive(Debug)]
struct HorizontalBar {
    percent: f32,
    color: iced::Color,
    label: String,
    detail: String,
}

impl HorizontalBar {
    fn new(percent: f32, color: iced::Color, label: &str, detail: &str) -> Self {
        Self {
            percent: percent.clamp(0.0, 100.0),
            color,
            label: label.to_string(),
            detail: detail.to_string(),
        }
    }
}

impl<Message> canvas::Program<Message> for HorizontalBar {
    type State = ();

    fn draw(
        &self,
        _state: &Self::State,
        renderer: &Renderer,
        _theme: &Theme,
        bounds: Rectangle,
        _cursor: mouse::Cursor,
    ) -> Vec<Geometry> {
        let mut frame = Frame::new(renderer, bounds.size());
        let w = bounds.width;
        let h = bounds.height;
        let bar_h = 12.0;
        let bar_y = (h - bar_h) / 2.0;

        // Label on the left
        frame.fill_text(canvas::Text {
            content: self.label.clone(),
            position: iced::Point::new(0.0, bar_y + bar_h / 2.0),
            color: colors::TEXT_SECONDARY,
            size: iced::Pixels(11.0),
            vertical_alignment: iced::alignment::Vertical::Center,
            ..canvas::Text::default()
        });

        let label_w = 48.0;
        let detail_w = 100.0;
        let bar_x = label_w;
        let bar_w = w - label_w - detail_w - 8.0;

        // Bar background
        let bg = Path::rectangle(
            iced::Point::new(bar_x, bar_y),
            iced::Size::new(bar_w.max(0.0), bar_h),
        );
        frame.fill(&bg, colors::SURFACE_LIGHT);

        // Bar fill
        let fill_w = bar_w * (self.percent / 100.0);
        if fill_w > 0.0 {
            let bar_color = colors::heat_color(self.percent);
            let fill = Path::rectangle(
                iced::Point::new(bar_x, bar_y),
                iced::Size::new(fill_w.max(0.0), bar_h),
            );
            frame.fill(&fill, colors::with_alpha(bar_color, 0.7));

            // Bright tip
            if fill_w > 2.0 {
                let tip = Path::rectangle(
                    iced::Point::new(bar_x + fill_w - 2.0, bar_y),
                    iced::Size::new(2.0, bar_h),
                );
                frame.fill(&tip, bar_color);
            }
        }

        // Border around bar
        let bar_border = Path::rectangle(
            iced::Point::new(bar_x + 0.5, bar_y + 0.5),
            iced::Size::new((bar_w - 1.0).max(0.0), bar_h - 1.0),
        );
        frame.stroke(
            &bar_border,
            Stroke::default()
                .with_color(colors::SURFACE_BORDER)
                .with_width(0.5),
        );

        // Percentage + detail on the right
        let detail_text = format!("{:.0}%  {}", self.percent, self.detail);
        frame.fill_text(canvas::Text {
            content: detail_text,
            position: iced::Point::new(bar_x + bar_w + 8.0, bar_y + bar_h / 2.0),
            color: self.color,
            size: iced::Pixels(11.0),
            vertical_alignment: iced::alignment::Vertical::Center,
            ..canvas::Text::default()
        });

        vec![frame.into_geometry()]
    }
}

fn horizontal_bar_view<'a, Message: 'a>(
    percent: f32,
    color: iced::Color,
    label: &str,
    detail: &str,
) -> Element<'a, Message> {
    Canvas::new(HorizontalBar::new(percent, color, label, detail))
        .width(Length::Fill)
        .height(Length::Fixed(24.0))
        .into()
}

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

        // Horizontal bars for GPU and VRAM usage
        let gpu_bar = horizontal_bar_view(
            dev.gpu_usage,
            colors::ACCENT_GREEN,
            "GPU",
            &format!("{:.0}%", dev.gpu_usage),
        );
        let vram_bar = horizontal_bar_view(
            dev.vram_usage_percent,
            colors::ACCENT_MAGENTA,
            "VRAM",
            &format!(
                "{} / {}",
                gpu::format_vram(dev.vram_used),
                gpu::format_vram(dev.vram_total),
            ),
        );

        // Compact stats row
        let mut stats: Vec<Element<'a, Message>> = Vec::new();

        if let Some(temp) = dev.temperature_edge {
            let temp_color = colors::heat_color((temp / 100.0 * 100.0).min(100.0));
            stats.push(
                text(format!("{:.0}°C", temp))
                    .size(10)
                    .color(temp_color)
                    .into(),
            );
        }
        if let Some(clock) = dev.gpu_clock_mhz {
            stats.push(
                text(format!("{} MHz", clock))
                    .size(10)
                    .color(colors::ACCENT_CYAN)
                    .into(),
            );
        }
        if let Some(power) = dev.power_watts {
            let cap_str = dev
                .power_cap_watts
                .map(|c| format!("/{:.0}W", c))
                .unwrap_or_default();
            stats.push(
                text(format!("{:.1}W{}", power, cap_str))
                    .size(10)
                    .color(colors::ACCENT_ORANGE)
                    .into(),
            );
        }
        if let Some(rpm) = dev.fan_rpm {
            stats.push(
                text(format!("{} RPM", rpm))
                    .size(10)
                    .color(colors::TEXT_SECONDARY)
                    .into(),
            );
        }

        let mut stats_row = row![].spacing(12);
        for stat in stats {
            stats_row = stats_row.push(stat);
        }

        // Single GPU utilization graph (compact)
        let gpu_graph = graph_view(
            &dev.gpu_history,
            100.0,
            colors::ACCENT_GREEN,
            "GPU Utilization",
            &format!("{:.0}%", dev.gpu_usage),
        );

        let gpu_col = column![title, gpu_bar, vram_bar, stats_row, gpu_graph].spacing(4);
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
