mod metrics;
mod theme;
mod ui;

use iced::window;
use iced::{Size, Task};
use ui::app::RustTop;

fn main() -> iced::Result {
    iced::application("RustTop — System Monitor", RustTop::update, RustTop::view)
        .subscription(RustTop::subscription)
        .theme(RustTop::theme)
        .window(window::Settings {
            size: Size::new(1200.0, 800.0),
            min_size: Some(Size::new(800.0, 500.0)),
            ..Default::default()
        })
        .antialiasing(true)
        .run_with(|| {
            let app = RustTop::new();
            (app, Task::none())
        })
}
