use std::f32::consts::PI;

use iced::widget::canvas::{self, Canvas, Frame, Geometry, LineCap, Path, Stroke};
use iced::{mouse, Color, Element, Length, Point, Radians, Rectangle, Renderer, Size, Theme};

use crate::metrics::cpu::CpuMetrics;
use crate::metrics::gpu::GpuMetrics;
use crate::metrics::memory::MemoryMetrics;
use crate::theme::colors;

#[derive(Debug)]
struct SystemUsageGauges {
    gauges: Vec<UsageGauge>,
}

#[derive(Debug)]
struct UsageGauge {
    label: String,
    percent: Option<f32>,
    accent: Color,
}

#[derive(Debug, Clone, Copy)]
struct GaugeSegment {
    start_angle: f32,
    end_angle: f32,
    color: Color,
}

impl UsageGauge {
    fn active(label: &str, percent: f32, accent: Color) -> Self {
        Self {
            label: label.to_string(),
            percent: Some(percent.clamp(0.0, 100.0)),
            accent,
        }
    }

    fn unavailable(label: &str, accent: Color) -> Self {
        Self {
            label: label.to_string(),
            percent: None,
            accent,
        }
    }
}

impl SystemUsageGauges {
    fn new(
        cpu: &CpuMetrics,
        gpu: &GpuMetrics,
        memory: &MemoryMetrics,
        show_cpu: bool,
        show_gpu: bool,
        show_memory: bool,
    ) -> Self {
        let mut gauges = Vec::new();

        if show_cpu {
            gauges.push(UsageGauge::active(
                "CPU",
                cpu.global_usage,
                colors::CPU_COLOR,
            ));
        }

        if show_gpu {
            let gpu_percent = gpu.available.then_some(()).and_then(|_| {
                gpu.devices
                    .iter()
                    .map(|device| device.gpu_usage)
                    .max_by(|a, b| a.total_cmp(b))
            });

            gauges.push(match gpu_percent {
                Some(percent) => UsageGauge::active("GPU", percent, colors::ACCENT_GREEN),
                None => UsageGauge::unavailable("GPU", colors::ACCENT_GREEN),
            });
        }

        if show_memory {
            gauges.push(UsageGauge::active(
                "Memory",
                memory.mem_usage_percent,
                colors::MEM_COLOR,
            ));
        }

        Self { gauges }
    }
}

impl<Message> canvas::Program<Message> for SystemUsageGauges {
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
        let radius = 6.0.into();

        let bg = Path::rounded_rectangle(Point::new(0.0, 0.0), bounds.size(), radius);
        frame.fill(&bg, colors::SURFACE);

        let border = Path::rounded_rectangle(
            Point::new(0.5, 0.5),
            Size::new((w - 1.0).max(0.0), (h - 1.0).max(0.0)),
            radius,
        );
        frame.stroke(
            &border,
            Stroke::default()
                .with_color(colors::SURFACE_BORDER)
                .with_width(1.0),
        );

        frame.fill_text(canvas::Text {
            content: "System Load".to_string(),
            position: Point::new(12.0, 10.0),
            color: colors::ACCENT_CYAN,
            size: iced::Pixels(14.0),
            ..canvas::Text::default()
        });

        if self.gauges.is_empty() {
            frame.fill_text(canvas::Text {
                content: "No CPU, GPU, or memory panels enabled".to_string(),
                position: Point::new(w / 2.0, h / 2.0),
                color: colors::TEXT_DIM,
                size: iced::Pixels(12.0),
                horizontal_alignment: iced::alignment::Horizontal::Center,
                vertical_alignment: iced::alignment::Vertical::Center,
                ..canvas::Text::default()
            });
            return vec![frame.into_geometry()];
        }

        let count = self.gauges.len() as f32;
        let padding = 14.0;
        let title_h = 26.0;
        let available_w = (w - padding * 2.0).max(1.0);
        let slot_w = available_w / count;

        for (index, gauge) in self.gauges.iter().enumerate() {
            let slot_x = padding + index as f32 * slot_w;
            draw_speedometer(
                &mut frame,
                gauge,
                Rectangle {
                    x: slot_x,
                    y: title_h,
                    width: slot_w,
                    height: (h - title_h - 8.0).max(1.0),
                },
            );
        }

        vec![frame.into_geometry()]
    }
}

fn draw_speedometer(frame: &mut Frame, gauge: &UsageGauge, area: Rectangle) {
    const START_ANGLE: f32 = PI * 0.78;
    const END_ANGLE: f32 = PI * 2.22;

    let span = END_ANGLE - START_ANGLE;
    let center = Point::new(area.x + area.width / 2.0, area.y + area.height * 0.58);
    let radius = (area.width * 0.30).min(area.height * 0.46).max(24.0);
    let stroke_width = (radius * 0.14).clamp(8.0, 12.0);
    let enabled = gauge.percent.is_some();
    let face = Path::circle(center, radius + stroke_width * 0.85);
    frame.fill(&face, colors::with_alpha(colors::SURFACE_LIGHT, 0.18));

    draw_segment(
        frame,
        center,
        radius,
        GaugeSegment {
            start_angle: START_ANGLE,
            end_angle: END_ANGLE,
            color: colors::with_alpha(colors::SURFACE_LIGHT, 0.92),
        },
        true,
        stroke_width + 6.0,
    );

    draw_segment(
        frame,
        center,
        radius,
        GaugeSegment {
            start_angle: START_ANGLE,
            end_angle: START_ANGLE + span * 0.60,
            color: colors::ACCENT_GREEN,
        },
        enabled,
        stroke_width,
    );
    draw_segment(
        frame,
        center,
        radius,
        GaugeSegment {
            start_angle: START_ANGLE + span * 0.62,
            end_angle: START_ANGLE + span * 0.84,
            color: colors::ACCENT_YELLOW,
        },
        enabled,
        stroke_width,
    );
    draw_segment(
        frame,
        center,
        radius,
        GaugeSegment {
            start_angle: START_ANGLE + span * 0.86,
            end_angle: END_ANGLE,
            color: colors::ACCENT_RED,
        },
        enabled,
        stroke_width,
    );

    for tick in 0..=10 {
        let percent = tick as f32 * 10.0;
        let angle = START_ANGLE + span * (percent / 100.0);
        let major = tick % 5 == 0;
        let outer = point_on_circle(center, radius - stroke_width * 0.25, angle);
        let inner = point_on_circle(
            center,
            radius - stroke_width * if major { 1.95 } else { 1.35 },
            angle,
        );
        let tick = Path::line(inner, outer);
        frame.stroke(
            &tick,
            Stroke::default()
                .with_color(colors::with_alpha(
                    colors::TEXT_SECONDARY,
                    if major { 0.70 } else { 0.36 },
                ))
                .with_width(if major { 1.3 } else { 0.8 })
                .with_line_cap(LineCap::Round),
        );
    }

    for (label, percent) in [("0", 0.0), ("50", 50.0), ("100", 100.0)] {
        let angle = START_ANGLE + span * (percent / 100.0);
        let position = point_on_circle(center, radius - stroke_width * 3.2, angle);
        frame.fill_text(canvas::Text {
            content: label.to_string(),
            position,
            color: colors::TEXT_DIM,
            size: iced::Pixels(8.5),
            horizontal_alignment: iced::alignment::Horizontal::Center,
            vertical_alignment: iced::alignment::Vertical::Center,
            ..canvas::Text::default()
        });
    }

    let display = match gauge.percent {
        Some(percent) => {
            let angle = START_ANGLE + span * (percent / 100.0);
            let needle_color = colors::heat_color(percent);
            let needle_shadow = needle_path(center, angle, radius - stroke_width * 1.15, 5.8, 1.5);
            frame.fill(&needle_shadow, colors::with_alpha(colors::BACKGROUND, 0.42));

            let needle = needle_path(center, angle, radius - stroke_width * 1.35, 4.6, 0.0);
            frame.fill(&needle, needle_color);

            let hub_shadow = Path::circle(Point::new(center.x, center.y + 1.0), 7.0);
            frame.fill(&hub_shadow, colors::with_alpha(colors::BACKGROUND, 0.45));
            let hub = Path::circle(center, 6.0);
            frame.fill(&hub, colors::SURFACE);
            let hub_core = Path::circle(center, 3.5);
            frame.fill(&hub_core, needle_color);

            (format!("{percent:.0}%"), needle_color)
        }
        None => {
            let hub = Path::circle(center, 5.5);
            frame.fill(&hub, colors::TEXT_DIM);
            ("N/A".to_string(), colors::TEXT_DIM)
        }
    };

    frame.fill_text(canvas::Text {
        content: display.0,
        position: Point::new(center.x, center.y - radius * 0.42),
        color: display.1,
        size: iced::Pixels((radius * 0.30).clamp(17.0, 22.0)),
        horizontal_alignment: iced::alignment::Horizontal::Center,
        vertical_alignment: iced::alignment::Vertical::Center,
        ..canvas::Text::default()
    });

    frame.fill_text(canvas::Text {
        content: gauge.label.clone(),
        position: Point::new(center.x, area.y + area.height - 3.0),
        color: if enabled {
            gauge.accent
        } else {
            colors::TEXT_DIM
        },
        size: iced::Pixels(12.0),
        horizontal_alignment: iced::alignment::Horizontal::Center,
        vertical_alignment: iced::alignment::Vertical::Bottom,
        ..canvas::Text::default()
    });
}

fn draw_segment(
    frame: &mut Frame,
    center: Point,
    radius: f32,
    segment: GaugeSegment,
    enabled: bool,
    width: f32,
) {
    let segment_path = Path::new(|builder| {
        builder.arc(canvas::path::Arc {
            center,
            radius,
            start_angle: Radians(segment.start_angle),
            end_angle: Radians(segment.end_angle),
        });
    });
    frame.stroke(
        &segment_path,
        Stroke::default()
            .with_color(if enabled {
                segment.color
            } else {
                colors::with_alpha(colors::SURFACE_LIGHT, 0.9)
            })
            .with_width(width)
            .with_line_cap(LineCap::Round),
    );
}

fn point_on_circle(center: Point, radius: f32, angle: f32) -> Point {
    Point::new(
        center.x + radius * angle.cos(),
        center.y + radius * angle.sin(),
    )
}

fn needle_path(center: Point, angle: f32, length: f32, half_width: f32, y_offset: f32) -> Path {
    let adjusted_center = Point::new(center.x, center.y + y_offset);
    let tip = point_on_circle(adjusted_center, length, angle);
    let left = point_on_circle(adjusted_center, half_width, angle + PI / 2.0);
    let right = point_on_circle(adjusted_center, half_width, angle - PI / 2.0);

    Path::new(|builder| {
        builder.move_to(tip);
        builder.line_to(left);
        builder.line_to(right);
        builder.close();
    })
}

pub fn utilization_gauges_view<'a, Message: 'a>(
    cpu: &CpuMetrics,
    gpu: &GpuMetrics,
    memory: &MemoryMetrics,
    show_cpu: bool,
    show_gpu: bool,
    show_memory: bool,
) -> Element<'a, Message> {
    Canvas::new(SystemUsageGauges::new(
        cpu,
        gpu,
        memory,
        show_cpu,
        show_gpu,
        show_memory,
    ))
    .width(Length::Fill)
    .height(Length::Fixed(164.0))
    .into()
}
