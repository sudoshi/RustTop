use std::f32::consts::{FRAC_PI_2, TAU};

use iced::widget::canvas::{self, Canvas, Frame, Geometry, Path, Stroke};
use iced::widget::{column, container, row, text, Space};
use iced::{mouse, Element, Length, Padding, Point, Radians, Rectangle, Renderer, Theme};

use crate::metrics::disk::{DiskInfo, DiskMetrics};
use crate::metrics::units::{format_binary_bytes, format_binary_rate};
use crate::theme::colors;

#[derive(Debug)]
struct DiskGauge {
    percent: f32,
}

impl DiskGauge {
    fn new(percent: f32) -> Self {
        Self {
            percent: percent.clamp(0.0, 100.0),
        }
    }
}

impl<Message> canvas::Program<Message> for DiskGauge {
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
        let radius = ((w.min(h) - 16.0) / 2.0).max(18.0);
        let center = Point::new(w / 2.0, h / 2.0);
        let percent = self.percent.clamp(0.0, 100.0);
        let used_color = colors::heat_color(percent);
        let available_color = colors::with_alpha(colors::ACCENT_GREEN, 0.22);

        let available_slice = Path::circle(center, radius);
        frame.fill(&available_slice, available_color);

        let start = -FRAC_PI_2;
        if percent > 0.0 {
            let end = start + TAU * (percent / 100.0);
            if percent >= 99.95 {
                frame.fill(&Path::circle(center, radius), used_color);
            } else {
                frame.fill(&pie_slice(center, radius, start, end), used_color);

                let separator = Path::line(center, point_on_circle(center, radius, end));
                frame.stroke(
                    &separator,
                    Stroke::default()
                        .with_color(colors::with_alpha(colors::SURFACE, 0.8))
                        .with_width(1.0),
                );
            }
        }

        let border = Path::circle(center, radius);
        frame.stroke(
            &border,
            Stroke::default()
                .with_color(colors::SURFACE_BORDER)
                .with_width(1.0),
        );

        vec![frame.into_geometry()]
    }
}

pub fn disk_view<'a, Message: 'a>(disks: &'a DiskMetrics) -> Element<'a, Message> {
    let title = text("Disks").size(14).color(colors::ACCENT_ORANGE);
    let visible_disks: Vec<_> = disks
        .disks
        .iter()
        .filter(|disk| disk.total_space > 0)
        .collect();

    let mut content = column![title].spacing(8);

    if visible_disks.is_empty() {
        content = content.push(text("No disks detected").size(12).color(colors::TEXT_DIM));
    } else {
        for disk in visible_disks {
            content = content.push(disk_row_view::<Message>(disk));
        }
    }

    container(content)
        .padding(Padding::from([8, 12]))
        .style(|_theme: &Theme| container::Style {
            background: Some(colors::SURFACE.into()),
            border: iced::Border {
                color: colors::SURFACE_BORDER,
                width: 1.0,
                radius: 6.0.into(),
            },
            ..Default::default()
        })
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

fn disk_row_view<'a, Message: 'a>(disk: &'a DiskInfo) -> Element<'a, Message> {
    let used = format_binary_bytes(disk.used_space);
    let total = format_binary_bytes(disk.total_space);
    let available = format_binary_bytes(disk.available_space);
    let fs_type = if disk.fs_type.trim().is_empty() {
        "unknown"
    } else {
        disk.fs_type.as_str()
    };
    let pressure_color = colors::heat_color(disk.usage_percent);

    let details = column![
        row![
            text(compact_mount_label(&disk.mount_point))
                .size(12)
                .color(colors::TEXT_PRIMARY),
            Space::with_width(Length::Fill),
            text(fs_type).size(10).color(colors::TEXT_DIM),
        ]
        .spacing(8)
        .align_y(iced::Alignment::Center),
        row![
            text(format!("{used} / {total}"))
                .size(11)
                .color(colors::TEXT_SECONDARY),
            Space::with_width(Length::Fill),
            text(format!("{:.0}% used", disk.usage_percent))
                .size(11)
                .color(pressure_color),
        ]
        .spacing(8)
        .align_y(iced::Alignment::Center),
        row![
            text(format!("{available} free"))
                .size(10)
                .color(colors::TEXT_DIM),
            Space::with_width(Length::Fill),
            text(format!(
                "R {}  W {}",
                format_binary_rate(disk.read_rate),
                format_binary_rate(disk.write_rate),
            ))
            .size(10)
            .color(colors::TEXT_DIM),
        ]
        .spacing(8)
        .align_y(iced::Alignment::Center),
    ]
    .spacing(3)
    .width(Length::Fill);

    row![disk_gauge_view::<Message>(disk.usage_percent), details]
        .spacing(10)
        .align_y(iced::Alignment::Center)
        .width(Length::Fill)
        .into()
}

fn disk_gauge_view<'a, Message: 'a>(percent: f32) -> Element<'a, Message> {
    Canvas::new(DiskGauge::new(percent))
        .width(Length::Fixed(74.0))
        .height(Length::Fixed(74.0))
        .into()
}

fn pie_slice(center: Point, radius: f32, start: f32, end: f32) -> Path {
    Path::new(|builder| {
        builder.move_to(center);
        builder.line_to(point_on_circle(center, radius, start));
        builder.arc(canvas::path::Arc {
            center,
            radius,
            start_angle: Radians(start),
            end_angle: Radians(end),
        });
        builder.close();
    })
}

fn point_on_circle(center: Point, radius: f32, angle: f32) -> Point {
    Point::new(
        center.x + radius * angle.cos(),
        center.y + radius * angle.sin(),
    )
}

fn compact_mount_label(mount_point: &str) -> String {
    const MAX_CHARS: usize = 22;

    if mount_point.chars().count() <= MAX_CHARS {
        return mount_point.to_string();
    }

    let mut compact: String = mount_point.chars().take(MAX_CHARS - 3).collect();
    compact.push_str("...");
    compact
}
