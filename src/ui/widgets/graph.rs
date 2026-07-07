use iced::widget::canvas::{self, Canvas, Frame, Geometry, Path, Stroke};
use iced::{mouse, Color, Element, Length, Rectangle, Renderer, Size, Theme};

use crate::theme::colors;

/// A beautiful line graph with gradient fill
#[derive(Debug)]
pub struct Graph {
    data: Vec<f32>,
    max_value: f32,
    color: Color,
    label: String,
    current_value: String,
    value_position: ValuePosition,
}

#[derive(Debug, Clone, Copy)]
enum ValuePosition {
    TopRight,
    UnderLabel,
}

impl Graph {
    pub fn new(
        data: &[f32],
        max_value: f32,
        color: Color,
        label: &str,
        current_value: &str,
    ) -> Self {
        Self {
            data: data.to_vec(),
            max_value,
            color,
            label: label.to_string(),
            current_value: current_value.to_string(),
            value_position: ValuePosition::TopRight,
        }
    }

    fn value_under_label(mut self) -> Self {
        self.value_position = ValuePosition::UnderLabel;
        self
    }
}

impl<Message> canvas::Program<Message> for Graph {
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
        let padding = 8.0;
        let header_h = match self.value_position {
            ValuePosition::TopRight => 28.0,
            ValuePosition::UnderLabel => 44.0,
        };
        let graph_h = (h - padding * 2.0 - header_h).max(1.0);
        let graph_y = padding + header_h - 4.0;
        let radius = 6.0.into();

        // Background
        let bg = Path::rounded_rectangle(iced::Point::new(0.0, 0.0), bounds.size(), radius);
        frame.fill(&bg, colors::SURFACE);

        // Border
        let border = Path::rounded_rectangle(
            iced::Point::new(0.5, 0.5),
            Size::new(w - 1.0, h - 1.0),
            radius,
        );
        frame.stroke(
            &border,
            Stroke::default()
                .with_color(colors::SURFACE_BORDER)
                .with_width(1.0),
        );

        // Grid lines (horizontal)
        for i in 1..4 {
            let y = graph_y + graph_h * (i as f32 / 4.0);
            let grid_line = Path::line(
                iced::Point::new(padding, y),
                iced::Point::new(w - padding, y),
            );
            frame.stroke(
                &grid_line,
                Stroke::default()
                    .with_color(colors::with_alpha(colors::SURFACE_BORDER, 0.5))
                    .with_width(0.5),
            );
        }

        // Draw the data line and fill
        if self.data.len() >= 2 {
            let data_len = self.data.len();
            let graph_w = w - padding * 2.0;
            let step = graph_w / (data_len.max(2) - 1) as f32;

            // Build the line path
            let mut line_builder = canvas::path::Builder::new();
            let mut fill_builder = canvas::path::Builder::new();

            let first_x = padding;
            let first_val = (self.data[0] / self.max_value).clamp(0.0, 1.0);
            let first_y = graph_y + graph_h * (1.0 - first_val);

            line_builder.move_to(iced::Point::new(first_x, first_y));
            fill_builder.move_to(iced::Point::new(first_x, graph_y + graph_h));
            fill_builder.line_to(iced::Point::new(first_x, first_y));

            for i in 1..data_len {
                let x = padding + i as f32 * step;
                let val = (self.data[i] / self.max_value).clamp(0.0, 1.0);
                let y = graph_y + graph_h * (1.0 - val);

                line_builder.line_to(iced::Point::new(x, y));
                fill_builder.line_to(iced::Point::new(x, y));
            }

            // Close the fill path
            let last_x = padding + (data_len - 1) as f32 * step;
            fill_builder.line_to(iced::Point::new(last_x, graph_y + graph_h));
            fill_builder.close();

            // Draw gradient fill (simulated with semi-transparent color)
            let fill_path = fill_builder.build();
            frame.fill(
                &fill_path,
                colors::with_alpha(self.color, colors::GRAPH_FILL_OPACITY),
            );

            // Draw the line
            let line_path = line_builder.build();
            frame.stroke(
                &line_path,
                Stroke::default().with_color(self.color).with_width(2.0),
            );

            // Glow dot at the latest value
            let last_val = (self.data[data_len - 1] / self.max_value).clamp(0.0, 1.0);
            let dot_y = graph_y + graph_h * (1.0 - last_val);
            let dot = Path::circle(iced::Point::new(last_x, dot_y), 4.0);
            frame.fill(&dot, self.color);
            let glow = Path::circle(iced::Point::new(last_x, dot_y), 8.0);
            frame.fill(&glow, colors::with_alpha(self.color, 0.2));
        }

        // Label text
        frame.fill_text(canvas::Text {
            content: self.label.clone(),
            position: iced::Point::new(padding + 4.0, padding + 2.0),
            color: colors::TEXT_SECONDARY,
            size: iced::Pixels(12.0),
            ..canvas::Text::default()
        });

        match self.value_position {
            ValuePosition::TopRight => {
                frame.fill_text(canvas::Text {
                    content: self.current_value.clone(),
                    position: iced::Point::new(w - padding - 4.0, padding + 2.0),
                    color: self.color,
                    size: iced::Pixels(14.0),
                    horizontal_alignment: iced::alignment::Horizontal::Right,
                    ..canvas::Text::default()
                });
            }
            ValuePosition::UnderLabel => {
                frame.fill_text(canvas::Text {
                    content: self.current_value.clone(),
                    position: iced::Point::new(padding + 4.0, padding + 20.0),
                    color: self.color,
                    size: iced::Pixels(13.0),
                    ..canvas::Text::default()
                });
            }
        }

        vec![frame.into_geometry()]
    }
}

pub fn graph_view<'a, Message: 'a>(
    data: &[f32],
    max_value: f32,
    color: Color,
    label: &str,
    current_value: &str,
) -> Element<'a, Message> {
    Canvas::new(Graph::new(data, max_value, color, label, current_value))
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

pub fn graph_view_sized<'a, Message: 'a>(
    data: &[f32],
    max_value: f32,
    color: Color,
    label: &str,
    current_value: &str,
    height: f32,
) -> Element<'a, Message> {
    Canvas::new(Graph::new(data, max_value, color, label, current_value))
        .width(Length::Fill)
        .height(Length::Fixed(height))
        .into()
}

pub fn graph_view_sized_value_under_label<'a, Message: 'a>(
    data: &[f32],
    max_value: f32,
    color: Color,
    label: &str,
    current_value: &str,
    height: f32,
) -> Element<'a, Message> {
    Canvas::new(Graph::new(data, max_value, color, label, current_value).value_under_label())
        .width(Length::Fill)
        .height(Length::Fixed(height))
        .into()
}
