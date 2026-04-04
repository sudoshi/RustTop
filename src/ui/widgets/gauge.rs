use iced::widget::canvas::{self, Canvas, Frame, Geometry, Stroke};
use iced::{mouse, Element, Length, Rectangle, Renderer, Theme, Color};

use crate::theme::colors;

/// A beautiful arc gauge for CPU/Memory
#[derive(Debug)]
pub struct ArcGauge {
    percent: f32,
    color: Color,
    label: String,
    sub_label: String,
}

impl ArcGauge {
    pub fn new(percent: f32, color: Color, label: &str, sub_label: &str) -> Self {
        Self {
            percent: percent.clamp(0.0, 100.0),
            color,
            label: label.to_string(),
            sub_label: sub_label.to_string(),
        }
    }
}

impl<Message> canvas::Program<Message> for ArcGauge {
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
        let center_x = w / 2.0;
        let center_y = h / 2.0 + 10.0;
        let radius = (w.min(h) / 2.0 - 16.0).max(20.0);

        // Arc parameters
        let start_angle = std::f32::consts::PI * 0.75;
        let total_sweep = std::f32::consts::PI * 1.5;
        let value_sweep = total_sweep * (self.percent / 100.0);

        // Draw background arc
        draw_arc(
            &mut frame,
            center_x,
            center_y,
            radius,
            start_angle,
            total_sweep,
            colors::SURFACE_BORDER,
            6.0,
        );

        // Draw value arc with heat color
        let arc_color = colors::heat_color(self.percent);
        draw_arc(
            &mut frame,
            center_x,
            center_y,
            radius,
            start_angle,
            value_sweep,
            arc_color,
            6.0,
        );

        // Glow effect on the value arc
        draw_arc(
            &mut frame,
            center_x,
            center_y,
            radius,
            start_angle,
            value_sweep,
            colors::with_alpha(arc_color, 0.3),
            12.0,
        );

        // Center percentage text
        frame.fill_text(canvas::Text {
            content: format!("{:.0}%", self.percent),
            position: iced::Point::new(center_x, center_y - 8.0),
            color: colors::TEXT_PRIMARY,
            size: iced::Pixels(24.0),
            horizontal_alignment: iced::alignment::Horizontal::Center,
            vertical_alignment: iced::alignment::Vertical::Center,
            ..canvas::Text::default()
        });

        // Label below
        frame.fill_text(canvas::Text {
            content: self.label.clone(),
            position: iced::Point::new(center_x, center_y + 14.0),
            color: self.color,
            size: iced::Pixels(12.0),
            horizontal_alignment: iced::alignment::Horizontal::Center,
            vertical_alignment: iced::alignment::Vertical::Center,
            ..canvas::Text::default()
        });

        // Sub-label
        frame.fill_text(canvas::Text {
            content: self.sub_label.clone(),
            position: iced::Point::new(center_x, center_y + 28.0),
            color: colors::TEXT_DIM,
            size: iced::Pixels(10.0),
            horizontal_alignment: iced::alignment::Horizontal::Center,
            vertical_alignment: iced::alignment::Vertical::Center,
            ..canvas::Text::default()
        });

        vec![frame.into_geometry()]
    }
}

fn draw_arc(
    frame: &mut Frame,
    cx: f32,
    cy: f32,
    radius: f32,
    start: f32,
    sweep: f32,
    color: Color,
    width: f32,
) {
    if sweep <= 0.0 {
        return;
    }

    let segments = (sweep * 30.0).ceil() as usize; // smooth arc
    if segments == 0 {
        return;
    }

    let mut builder = canvas::path::Builder::new();
    let angle_step = sweep / segments as f32;

    let first_angle = start;
    builder.move_to(iced::Point::new(
        cx + radius * first_angle.cos(),
        cy + radius * first_angle.sin(),
    ));

    for i in 1..=segments {
        let angle = start + angle_step * i as f32;
        builder.line_to(iced::Point::new(
            cx + radius * angle.cos(),
            cy + radius * angle.sin(),
        ));
    }

    let path = builder.build();
    frame.stroke(
        &path,
        Stroke::default()
            .with_color(color)
            .with_width(width)
            .with_line_cap(canvas::LineCap::Round),
    );
}

pub fn gauge_view<'a, Message: 'a>(
    percent: f32,
    color: Color,
    label: &str,
    sub_label: &str,
) -> Element<'a, Message> {
    Canvas::new(ArcGauge::new(percent, color, label, sub_label))
        .width(Length::Fixed(140.0))
        .height(Length::Fixed(140.0))
        .into()
}
