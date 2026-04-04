mod metrics;
mod theme;
mod ui;

use iced::window;
use iced::{Size, Task};
use ui::app::RustTop;

fn main() -> iced::Result {
    let icon = window::icon::from_file_data(
        include_bytes!("../assets/icons/rust_top.png"),
        None,
    )
    .ok();

    let mut window_settings = window::Settings {
        size: Size::new(1200.0, 800.0),
        min_size: Some(Size::new(800.0, 500.0)),
        ..Default::default()
    };
    window_settings.icon = icon;

    iced::application("RustTop — System Monitor", RustTop::update, RustTop::view)
        .subscription(RustTop::subscription)
        .theme(RustTop::theme)
        .window(window_settings)
        .antialiasing(true)
        .run_with(|| {
            let app = RustTop::new();
            (app, Task::none())
        })
}
