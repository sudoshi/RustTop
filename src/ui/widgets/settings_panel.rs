use iced::widget::{button, container, row, text, Space};
use iced::{Element, Length, Padding};

use crate::config::{LayoutPreset, RuntimeOptions};
use crate::theme;
use crate::theme::colors;
use crate::ui::app::Message;

pub fn settings_panel_view(settings: &RuntimeOptions) -> Element<'_, Message> {
    let content = row![
        text("Settings").size(13).color(colors::ACCENT_CYAN),
        text("Layout").size(11).color(colors::TEXT_DIM),
        layout_button("Balanced", LayoutPreset::Balanced, settings.layout_preset),
        layout_button(
            "Process",
            LayoutPreset::FocusProcesses,
            settings.layout_preset,
        ),
        layout_button("Minimal", LayoutPreset::Minimal, settings.layout_preset),
        Space::with_width(Length::Fill),
        button(
            text(theme::theme_label(&settings.theme))
                .size(11)
                .color(colors::TEXT_SECONDARY)
        )
        .on_press(Message::CycleTheme)
        .padding(Padding::from([3, 8]))
        .style(inactive_button_style),
        button(
            text(if settings.compact_mode {
                "Compact On"
            } else {
                "Compact Off"
            })
            .size(11)
            .color(if settings.compact_mode {
                colors::BACKGROUND
            } else {
                colors::TEXT_SECONDARY
            })
        )
        .on_press(Message::ToggleCompactMode)
        .padding(Padding::from([3, 8]))
        .style(move |_theme: &iced::Theme, _status| {
            if settings.compact_mode {
                active_button_style(_theme, _status)
            } else {
                inactive_button_style(_theme, _status)
            }
        }),
        button(
            text(if settings.alerts.enabled {
                "Alerts On"
            } else {
                "Alerts Off"
            })
            .size(11)
            .color(if settings.alerts.enabled {
                colors::BACKGROUND
            } else {
                colors::TEXT_SECONDARY
            })
        )
        .on_press(Message::ToggleAlerts)
        .padding(Padding::from([3, 8]))
        .style(move |_theme: &iced::Theme, _status| {
            if settings.alerts.enabled {
                active_button_style(_theme, _status)
            } else {
                inactive_button_style(_theme, _status)
            }
        }),
        button(text("Close").size(11).color(colors::TEXT_SECONDARY))
            .on_press(Message::ToggleSettings)
            .padding(Padding::from([3, 8]))
            .style(inactive_button_style),
    ]
    .spacing(8)
    .align_y(iced::Alignment::Center);

    container(content)
        .padding(Padding::from([6, 12]))
        .width(Length::Fill)
        .style(|_theme: &iced::Theme| container::Style {
            background: Some(colors::SURFACE_LIGHT.into()),
            border: iced::Border {
                color: colors::SURFACE_BORDER,
                width: 1.0,
                radius: 6.0.into(),
            },
            ..Default::default()
        })
        .into()
}

fn layout_button<'a>(
    label: &'static str,
    preset: LayoutPreset,
    current: LayoutPreset,
) -> Element<'a, Message> {
    let active = preset == current;
    button(text(label).size(11).color(if active {
        colors::BACKGROUND
    } else {
        colors::TEXT_SECONDARY
    }))
    .on_press(Message::ApplyLayoutPreset(preset))
    .padding(Padding::from([3, 8]))
    .style(move |_theme: &iced::Theme, _status| {
        if active {
            active_button_style(_theme, _status)
        } else {
            inactive_button_style(_theme, _status)
        }
    })
    .into()
}

fn active_button_style(_theme: &iced::Theme, _status: button::Status) -> button::Style {
    button::Style {
        background: Some(colors::ACCENT_CYAN.into()),
        text_color: colors::BACKGROUND,
        border: iced::Border {
            color: colors::ACCENT_CYAN,
            width: 1.0,
            radius: 4.0.into(),
        },
        ..Default::default()
    }
}

fn inactive_button_style(_theme: &iced::Theme, _status: button::Status) -> button::Style {
    button::Style {
        background: Some(colors::SURFACE.into()),
        text_color: colors::TEXT_SECONDARY,
        border: iced::Border {
            color: colors::SURFACE_BORDER,
            width: 1.0,
            radius: 4.0.into(),
        },
        ..Default::default()
    }
}
