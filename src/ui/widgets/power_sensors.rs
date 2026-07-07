use iced::widget::{column, container, row, text, Space};
use iced::{Element, Length, Padding};

use crate::metrics::battery::BatteryMetrics;
use crate::metrics::sensors::{temperature_status, SensorMetrics, SensorStatus};
use crate::theme::colors;

pub fn battery_panel_view<'a, Message: 'a>(battery: &'a BatteryMetrics) -> Element<'a, Message> {
    let title = text("Battery").size(14).color(colors::ACCENT_GREEN);

    let mut rows: Vec<Element<'a, Message>> = vec![title.into()];
    if battery.batteries.is_empty() {
        rows.push(
            text("No battery detected")
                .size(11)
                .color(colors::TEXT_DIM)
                .into(),
        );
    } else {
        for item in &battery.batteries {
            let capacity = item
                .capacity_percent
                .map(|value| format!("{value:.0}%"))
                .unwrap_or_else(|| "--".to_string());
            let health = item
                .health_percent
                .map(|value| format!("health {value:.0}%"))
                .unwrap_or_else(|| "health --".to_string());
            let capacity_color = item
                .capacity_percent
                .map(|value| colors::heat_color(100.0 - value))
                .unwrap_or(colors::TEXT_SECONDARY);

            rows.push(
                row![
                    text(format!("{} {}", item.name, item.status))
                        .size(11)
                        .color(colors::TEXT_SECONDARY),
                    Space::with_width(Length::Fill),
                    text(format!("{capacity}  {health}"))
                        .size(11)
                        .color(capacity_color),
                ]
                .spacing(8)
                .align_y(iced::Alignment::Center)
                .into(),
            );
        }
    }

    panel(rows)
}

pub fn sensors_panel_view<'a, Message: 'a>(sensors: &'a SensorMetrics) -> Element<'a, Message> {
    let title_value = sensors
        .highest_temperature()
        .map(|value| format!("{value:.0}C max"))
        .unwrap_or_else(|| "no readings".to_string());
    let title = row![
        text("Sensors").size(14).color(colors::ACCENT_YELLOW),
        Space::with_width(Length::Fill),
        text(title_value).size(11).color(colors::TEXT_DIM),
    ]
    .align_y(iced::Alignment::Center);

    let mut rows: Vec<Element<'a, Message>> = vec![title.into()];
    if sensors.components.is_empty() {
        rows.push(
            text("No thermal sensors exposed")
                .size(11)
                .color(colors::TEXT_DIM)
                .into(),
        );
    } else {
        for component in sensors.components.iter().take(4) {
            let temp = component
                .temperature
                .map(|value| format!("{value:.1}C"))
                .unwrap_or_else(|| "--".to_string());
            let limit = component
                .critical
                .or(component.max)
                .map(|value| format!("limit {value:.0}C"))
                .unwrap_or_default();
            let status = temperature_status(component.temperature, component.critical);

            rows.push(
                row![
                    text(&component.label)
                        .size(11)
                        .color(colors::TEXT_SECONDARY),
                    Space::with_width(Length::Fill),
                    text(format!("{temp} {limit}"))
                        .size(11)
                        .color(sensor_status_color(status)),
                ]
                .spacing(8)
                .align_y(iced::Alignment::Center)
                .into(),
            );
        }
    }

    panel(rows)
}

fn panel<'a, Message: 'a>(rows: Vec<Element<'a, Message>>) -> Element<'a, Message> {
    container(column(rows).spacing(4))
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
        .height(Length::Shrink)
        .into()
}

fn sensor_status_color(status: SensorStatus) -> iced::Color {
    match status {
        SensorStatus::Normal => colors::ACCENT_GREEN,
        SensorStatus::Warm => colors::ACCENT_YELLOW,
        SensorStatus::Critical => colors::ACCENT_RED,
        SensorStatus::Unknown => colors::TEXT_DIM,
    }
}
