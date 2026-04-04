pub mod colors;

use iced::Theme;

pub fn app_theme() -> Theme {
    Theme::custom(
        "RustTop Dark".to_string(),
        iced::theme::Palette {
            background: colors::BACKGROUND.into(),
            text: colors::TEXT_PRIMARY.into(),
            primary: colors::ACCENT_BLUE.into(),
            success: colors::ACCENT_GREEN.into(),
            danger: colors::ACCENT_RED.into(),
        },
    )
}
