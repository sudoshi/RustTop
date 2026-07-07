use iced::Color;

// Base colors — dark theme inspired by Tokyo Night / Catppuccin
pub const BACKGROUND: Color = Color::from_rgb(0.10, 0.10, 0.14);
pub const SURFACE: Color = Color::from_rgb(0.13, 0.14, 0.18);
pub const SURFACE_LIGHT: Color = Color::from_rgb(0.17, 0.18, 0.23);
pub const SURFACE_BORDER: Color = Color::from_rgb(0.22, 0.23, 0.29);

// Text
pub const TEXT_PRIMARY: Color = Color::from_rgb(0.90, 0.91, 0.95);
pub const TEXT_SECONDARY: Color = Color::from_rgb(0.58, 0.60, 0.68);
pub const TEXT_DIM: Color = Color::from_rgb(0.40, 0.42, 0.50);

// Accent colors — vibrant neons for graphs
pub const ACCENT_BLUE: Color = Color::from_rgb(0.47, 0.56, 1.0);
pub const ACCENT_CYAN: Color = Color::from_rgb(0.47, 0.87, 0.94);
pub const ACCENT_GREEN: Color = Color::from_rgb(0.47, 0.94, 0.60);
pub const ACCENT_YELLOW: Color = Color::from_rgb(0.94, 0.84, 0.47);
pub const ACCENT_ORANGE: Color = Color::from_rgb(0.94, 0.60, 0.33);
pub const ACCENT_RED: Color = Color::from_rgb(0.94, 0.39, 0.47);
pub const ACCENT_MAGENTA: Color = Color::from_rgb(0.80, 0.47, 0.94);

// Selection
pub const ACCENT_BLUE_DIM: Color = Color::from_rgb(0.18, 0.22, 0.35);

// Semantic
pub const CPU_COLOR: Color = ACCENT_CYAN;
pub const MEM_COLOR: Color = ACCENT_MAGENTA;
pub const NET_RX_COLOR: Color = ACCENT_GREEN;
pub const NET_TX_COLOR: Color = ACCENT_RED;

// Graph gradient stops
pub const GRAPH_FILL_OPACITY: f32 = 0.25;

/// Return a color with modified alpha
pub fn with_alpha(color: Color, alpha: f32) -> Color {
    Color { a: alpha, ..color }
}

/// Interpolate between two colors
pub fn lerp_color(a: Color, b: Color, t: f32) -> Color {
    let t = t.clamp(0.0, 1.0);
    Color {
        r: a.r + (b.r - a.r) * t,
        g: a.g + (b.g - a.g) * t,
        b: a.b + (b.b - a.b) * t,
        a: a.a + (b.a - a.a) * t,
    }
}

/// Get a heat color from green -> yellow -> red based on percentage (0-100)
pub fn heat_color(percent: f32) -> Color {
    if percent < 50.0 {
        lerp_color(ACCENT_GREEN, ACCENT_YELLOW, percent / 50.0)
    } else {
        lerp_color(ACCENT_YELLOW, ACCENT_RED, (percent - 50.0) / 50.0)
    }
}
