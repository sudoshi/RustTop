use iced::widget::canvas::{self, Canvas, Frame, Geometry, Path, Stroke};
use iced::{mouse, Element, Length, Rectangle, Renderer, Theme};

use crate::metrics::cpu::CpuMetrics;
use crate::theme::colors;

const CORE_COLUMNS: usize = 4;
const CORE_ROW_HEIGHT: f32 = 18.0;
const CORE_PANEL_PADDING: f32 = 8.0;
const CORE_TITLE_HEIGHT: f32 = 20.0;
const CORE_BOTTOM_PADDING: f32 = 12.0;

/// btop-style per-core view with usage bars and activity dots
#[derive(Debug)]
struct CpuCoresView {
    per_core_usage: Vec<f32>,
    per_core_history: Vec<Vec<f32>>,
    core_count: usize,
}

impl CpuCoresView {
    fn new(cpu: &CpuMetrics) -> Self {
        Self {
            per_core_usage: cpu.per_core_usage.clone(),
            per_core_history: cpu
                .per_core_history
                .iter()
                .map(|history| history.values())
                .collect(),
            core_count: cpu.core_count,
        }
    }
}

impl<Message> canvas::Program<Message> for CpuCoresView {
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

        // Background
        let bg = Path::rounded_rectangle(iced::Point::new(0.0, 0.0), bounds.size(), radius);
        frame.fill(&bg, colors::SURFACE);

        // Border
        let border = Path::rounded_rectangle(
            iced::Point::new(0.5, 0.5),
            iced::Size::new(w - 1.0, h - 1.0),
            radius,
        );
        frame.stroke(
            &border,
            Stroke::default()
                .with_color(colors::SURFACE_BORDER)
                .with_width(1.0),
        );

        if self.core_count == 0 {
            return vec![frame.into_geometry()];
        }

        let padding = CORE_PANEL_PADDING;
        let title_h = CORE_TITLE_HEIGHT;

        // Title
        frame.fill_text(canvas::Text {
            content: format!("CPU Cores ({})", self.core_count),
            position: iced::Point::new(padding + 4.0, padding),
            color: colors::ACCENT_CYAN,
            size: iced::Pixels(13.0),
            ..canvas::Text::default()
        });

        // Layout: 4 columns of cores
        let cols = CORE_COLUMNS;
        let rows_per_col = self.core_count.div_ceil(cols);
        let col_w = (w - padding * 3.0) / cols as f32;
        let row_h = CORE_ROW_HEIGHT;
        let bar_h = 10.0;
        let dot_section_w = 50.0; // space for activity dots
        let bar_w = col_w - dot_section_w - 50.0; // label + bar + dots

        let start_y = padding + title_h;

        for i in 0..self.core_count {
            let col = i / rows_per_col;
            let row = i % rows_per_col;

            let x = padding + col as f32 * (col_w + padding);
            let y = start_y + row as f32 * row_h;

            let usage = self.per_core_usage.get(i).copied().unwrap_or(0.0);
            let bar_color = colors::heat_color(usage);

            // Core label
            frame.fill_text(canvas::Text {
                content: format!("{:>2}", i),
                position: iced::Point::new(x, y),
                color: colors::TEXT_DIM,
                size: iced::Pixels(10.0),
                ..canvas::Text::default()
            });

            // Usage bar background
            let bar_x = x + 22.0;
            let bar_bg = Path::rounded_rectangle(
                iced::Point::new(bar_x, y + 1.0),
                iced::Size::new(bar_w, bar_h),
                3.0.into(),
            );
            frame.fill(&bar_bg, colors::SURFACE_LIGHT);

            // Usage bar fill
            let fill_w = bar_w * (usage / 100.0).min(1.0);
            if fill_w > 0.0 {
                let bar_fill = Path::rounded_rectangle(
                    iced::Point::new(bar_x, y + 1.0),
                    iced::Size::new(fill_w, bar_h),
                    3.0.into(),
                );
                frame.fill(&bar_fill, colors::with_alpha(bar_color, 0.7));

                // Bright edge at the tip
                if fill_w > 2.0 {
                    let tip = Path::rounded_rectangle(
                        iced::Point::new(bar_x + fill_w - 2.0, y + 1.0),
                        iced::Size::new(2.0, bar_h),
                        1.0.into(),
                    );
                    frame.fill(&tip, bar_color);
                }
            }

            // Percentage text
            frame.fill_text(canvas::Text {
                content: format!("{:>5.1}%", usage),
                position: iced::Point::new(bar_x + bar_w + 3.0, y),
                color: bar_color,
                size: iced::Pixels(10.0),
                ..canvas::Text::default()
            });

            // Activity dots (mini sparkline from history)
            let dots_x = bar_x + bar_w + 42.0;
            if let Some(history) = self.per_core_history.get(i) {
                let num_dots = 20.min(history.len());
                let start = history.len().saturating_sub(num_dots);
                let dot_spacing = 2.2;

                for (j, &val) in history[start..].iter().enumerate() {
                    let dx = dots_x + j as f32 * dot_spacing;
                    let dot_color = colors::heat_color(val);
                    let brightness = (val / 100.0).clamp(0.15, 1.0);

                    let dot = Path::circle(iced::Point::new(dx, y + bar_h / 2.0 + 1.0), 1.2);
                    frame.fill(&dot, colors::with_alpha(dot_color, brightness));
                }
            }
        }

        vec![frame.into_geometry()]
    }
}

pub fn cpu_cores_view<'a, Message: 'a>(cpu: &CpuMetrics) -> Element<'a, Message> {
    Canvas::new(CpuCoresView::new(cpu))
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

pub fn cpu_cores_preferred_height(cpu: &CpuMetrics) -> f32 {
    let rows = cpu.core_count.max(1).div_ceil(CORE_COLUMNS);
    CORE_PANEL_PADDING + CORE_TITLE_HEIGHT + rows as f32 * CORE_ROW_HEIGHT + CORE_BOTTOM_PADDING
}
