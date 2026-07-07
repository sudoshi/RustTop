use iced::widget::{container, row, text, Space};
use iced::{Element, Length, Padding};

use crate::alerts::{Alert, AlertSeverity, AlertUnit};
use crate::theme::colors;

pub fn alerts_panel_view<'a, Message: 'a>(alerts: &'a [Alert]) -> Option<Element<'a, Message>> {
    if alerts.is_empty() {
        return None;
    }

    let mut content = row![
        text("Alerts").size(12).color(colors::ACCENT_RED),
        Space::with_width(Length::Fixed(4.0)),
    ]
    .spacing(8)
    .align_y(iced::Alignment::Center);

    for alert in alerts.iter().take(4) {
        let color = match alert.severity {
            AlertSeverity::Warning => colors::ACCENT_YELLOW,
            AlertSeverity::Critical => colors::ACCENT_RED,
        };
        content = content.push(
            text(format!(
                "{} {:.0}{}/{}{} {}s",
                alert.label,
                alert.value,
                unit_suffix(alert.unit),
                alert.threshold,
                unit_suffix(alert.unit),
                alert.active_seconds
            ))
            .size(11)
            .color(color),
        );
    }

    if alerts.len() > 4 {
        content = content.push(
            text(format!("+{}", alerts.len() - 4))
                .size(11)
                .color(colors::TEXT_DIM),
        );
    }

    Some(
        container(content)
            .padding(Padding::from([4, 12]))
            .width(Length::Fill)
            .style(|_theme: &iced::Theme| container::Style {
                background: Some(colors::SURFACE_LIGHT.into()),
                border: iced::Border {
                    color: colors::ACCENT_RED,
                    width: 1.0,
                    radius: 0.0.into(),
                },
                ..Default::default()
            })
            .into(),
    )
}

fn unit_suffix(unit: AlertUnit) -> &'static str {
    match unit {
        AlertUnit::Percent => "%",
        AlertUnit::Celsius => "C",
    }
}
