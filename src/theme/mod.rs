pub mod colors;

use iced::Theme;

pub fn app_theme(theme_name: &str) -> Theme {
    let palette = match theme_name {
        "nord" => iced::theme::Palette {
            background: iced::Color::from_rgb(0.18, 0.20, 0.25),
            text: iced::Color::from_rgb(0.90, 0.93, 0.96),
            primary: iced::Color::from_rgb(0.53, 0.75, 0.82),
            success: iced::Color::from_rgb(0.64, 0.75, 0.55),
            danger: iced::Color::from_rgb(0.75, 0.38, 0.42),
        },
        "high-contrast" => iced::theme::Palette {
            background: iced::Color::BLACK,
            text: iced::Color::WHITE,
            primary: colors::ACCENT_CYAN,
            success: colors::ACCENT_GREEN,
            danger: colors::ACCENT_RED,
        },
        _ => iced::theme::Palette {
            background: colors::BACKGROUND,
            text: colors::TEXT_PRIMARY,
            primary: colors::ACCENT_BLUE,
            success: colors::ACCENT_GREEN,
            danger: colors::ACCENT_RED,
        },
    };

    Theme::custom(format!("RustTop {}", theme_label(theme_name)), palette)
}

pub fn next_theme(theme_name: &str) -> &'static str {
    match theme_name {
        "tokyo-night" => "nord",
        "nord" => "high-contrast",
        _ => "tokyo-night",
    }
}

pub fn theme_label(theme_name: &str) -> &'static str {
    match theme_name {
        "nord" => "Nord",
        "high-contrast" => "High Contrast",
        _ => "Tokyo Night",
    }
}

#[cfg(test)]
mod tests {
    use super::next_theme;

    #[test]
    fn theme_cycle_is_stable() {
        assert_eq!(next_theme("tokyo-night"), "nord");
        assert_eq!(next_theme("nord"), "high-contrast");
        assert_eq!(next_theme("high-contrast"), "tokyo-night");
    }
}
