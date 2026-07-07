use iced::widget::canvas::{self, Canvas, Frame, Geometry, Path, Stroke};
use iced::widget::{column, container, row, text, Space};
use iced::{mouse, Element, Length, Padding, Rectangle, Renderer, Size, Theme};

use crate::metrics::battery::BatteryMetrics;
use crate::metrics::SystemMetrics;
use crate::theme::colors;

#[derive(Debug)]
struct BatteryIndicator {
    percent: Option<f32>,
}

impl BatteryIndicator {
    fn new(metrics: &BatteryMetrics) -> Option<Self> {
        let percent = metrics
            .batteries
            .iter()
            .find_map(|battery| battery.capacity_percent);

        percent.map(|percent| Self {
            percent: Some(percent.clamp(0.0, 100.0)),
        })
    }
}

impl<Message> canvas::Program<Message> for BatteryIndicator {
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
        let body_w = (w - 8.0).max(1.0);
        let body_h = (h - 4.0).max(1.0);
        let body_y = 2.0;
        let radius = 4.0.into();
        let percent = self.percent.unwrap_or(0.0).clamp(0.0, 100.0);
        let fill_color = colors::heat_color(100.0 - percent);

        let body = Path::rounded_rectangle(
            iced::Point::new(0.5, body_y + 0.5),
            Size::new(body_w - 1.0, body_h - 1.0),
            radius,
        );
        frame.stroke(
            &body,
            Stroke::default()
                .with_color(colors::TEXT_SECONDARY)
                .with_width(1.2),
        );

        let terminal = Path::rounded_rectangle(
            iced::Point::new(body_w + 1.0, h * 0.35),
            Size::new(5.0, h * 0.30),
            2.0.into(),
        );
        frame.fill(&terminal, colors::TEXT_SECONDARY);

        let fill_w = ((body_w - 6.0) * (percent / 100.0)).max(0.0);
        if fill_w > 0.0 {
            let fill = Path::rounded_rectangle(
                iced::Point::new(3.0, body_y + 3.0),
                Size::new(fill_w, (body_h - 6.0).max(1.0)),
                3.0.into(),
            );
            frame.fill(&fill, colors::with_alpha(fill_color, 0.35));
        }

        frame.fill_text(canvas::Text {
            content: format!("{percent:.0}%"),
            position: iced::Point::new(body_w / 2.0, h / 2.0),
            color: fill_color,
            size: iced::Pixels(11.0),
            horizontal_alignment: iced::alignment::Horizontal::Center,
            vertical_alignment: iced::alignment::Vertical::Center,
            ..canvas::Text::default()
        });

        vec![frame.into_geometry()]
    }
}

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

    let mut header_row =
        row![left, Space::with_width(Length::Fill)].align_y(iced::Alignment::Center);
    if let Some(indicator) = BatteryIndicator::new(&metrics.battery) {
        header_row = header_row.push(
            Canvas::new(indicator)
                .width(Length::Fixed(54.0))
                .height(Length::Fixed(24.0)),
        );
    }
    header_row = header_row.push(right);

    container(header_row.spacing(12))
        .padding(Padding::from([8, 16]))
        .style(|_theme: &iced::Theme| container::Style {
            background: Some(colors::SURFACE.into()),
            border: iced::Border {
                color: colors::SURFACE_BORDER,
                width: 0.0,
                radius: 6.0.into(),
            },
            ..Default::default()
        })
        .width(Length::Fill)
        .into()
}
