use iced::widget::{column, container, row, text, Space};
use iced::{Element, Length, Padding};

use crate::metrics::disk::DiskMetrics;
use crate::metrics::memory::MemoryMetrics;
use crate::theme::colors;


pub fn disk_view<'a, Message: 'a>(disks: &DiskMetrics) -> Element<'a, Message> {
    let mut disk_rows: Vec<Element<'a, Message>> = Vec::new();

    let title = text("Disks").size(14).color(colors::ACCENT_ORANGE);
    disk_rows.push(title.into());

    for disk in &disks.disks {
        if disk.total_space == 0 {
            continue;
        }

        let name = text(format!("{} ({})", disk.mount_point, disk.fs_type))
            .size(11)
            .color(colors::TEXT_SECONDARY);

        let usage = text(format!(
            "{} / {}  ({:.0}%)",
            MemoryMetrics::format_bytes(disk.used_space),
            MemoryMetrics::format_bytes(disk.total_space),
            disk.usage_percent,
        ))
        .size(11)
        .color(colors::heat_color(disk.usage_percent));

        let disk_row = row![name, Space::with_width(Length::Fill), usage]
            .spacing(8)
            .align_y(iced::Alignment::Center);

        disk_rows.push(disk_row.into());
    }

    container(column(disk_rows).spacing(4))
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
