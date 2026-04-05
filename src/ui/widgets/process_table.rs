use iced::widget::{button, column, container, row, scrollable, text, text_input, Space};
use iced::{Element, Length, Padding};

use crate::metrics::memory::MemoryMetrics;
use crate::metrics::process::{ProcessMetrics, SortField};
use crate::theme::colors;
use crate::ui::app::Message;

const FILTER_INPUT_ID: &str = "process_filter";

fn header_button<'a>(label: &str, field: SortField, current: &SortField, ascending: bool) -> Element<'a, Message> {
    let arrow = if *current == field {
        if ascending { " ^" } else { " v" }
    } else {
        ""
    };

    button(
        text(format!("{}{}", label, arrow))
            .size(11)
            .color(if *current == field {
                colors::ACCENT_CYAN
            } else {
                colors::TEXT_SECONDARY
            }),
    )
    .on_press(Message::SortBy(field))
    .padding(Padding::from([2, 4]))
    .style(|_theme: &iced::Theme, _status| button::Style {
        background: None,
        text_color: colors::TEXT_SECONDARY,
        ..Default::default()
    })
    .into()
}

pub fn process_table_view<'a>(processes: &'a ProcessMetrics, selected: Option<usize>) -> Element<'a, Message> {
    let title_row = row![
        text("Processes").size(14).color(colors::ACCENT_BLUE),
        Space::with_width(Length::Fill),
        text(format!("{} total", processes.total_count))
            .size(11)
            .color(colors::TEXT_DIM),
    ]
    .align_y(iced::Alignment::Center);

    let filter_input = text_input("Filter processes... (/ to focus)", &processes.filter)
        .id(text_input::Id::new(FILTER_INPUT_ID))
        .on_input(Message::FilterChanged)
        .size(12)
        .padding(Padding::from([4, 8]))
        .width(Length::Fill);

    let headers = row![
        container(header_button("PID", SortField::Pid, &processes.sort_field, processes.sort_ascending))
            .width(Length::Fixed(70.0)),
        container(header_button("Name", SortField::Name, &processes.sort_field, processes.sort_ascending))
            .width(Length::Fill),
        container(header_button("CPU%", SortField::Cpu, &processes.sort_field, processes.sort_ascending))
            .width(Length::Fixed(70.0)),
        container(header_button("Memory", SortField::Memory, &processes.sort_field, processes.sort_ascending))
            .width(Length::Fixed(90.0)),
        container(header_button("Status", SortField::Status, &processes.sort_field, processes.sort_ascending))
            .width(Length::Fixed(80.0)),
    ]
    .spacing(4)
    .padding(Padding::from([4, 8]));

    let header_container = container(headers)
        .style(|_theme: &iced::Theme| container::Style {
            background: Some(colors::SURFACE_LIGHT.into()),
            border: iced::Border {
                color: colors::SURFACE_BORDER,
                width: 0.0,
                radius: 4.0.into(),
            },
            ..Default::default()
        })
        .width(Length::Fill);

    let filtered = processes.filtered_processes();
    let visible: Vec<&_> = filtered.iter().take(200).copied().collect();

    let mut proc_rows: Vec<Element<'a, Message>> = Vec::with_capacity(visible.len());

    for (idx, proc_info) in visible.iter().enumerate() {
        let is_selected = selected == Some(idx);

        let bg = if is_selected {
            colors::ACCENT_BLUE_DIM
        } else if idx % 2 == 0 {
            colors::SURFACE
        } else {
            colors::SURFACE_LIGHT
        };

        let name_color = if is_selected {
            colors::ACCENT_CYAN
        } else {
            colors::TEXT_PRIMARY
        };

        let cpu_color = colors::heat_color(proc_info.cpu_usage.min(100.0));

        let proc_row = container(
            row![
                container(text(format!("{}", proc_info.pid)).size(11).color(colors::TEXT_DIM))
                    .width(Length::Fixed(70.0)),
                container(text(&proc_info.name).size(11).color(name_color))
                    .width(Length::Fill),
                container(
                    text(format!("{:.1}", proc_info.cpu_usage))
                        .size(11)
                        .color(cpu_color)
                )
                .width(Length::Fixed(70.0)),
                container(
                    text(MemoryMetrics::format_bytes(proc_info.memory))
                        .size(11)
                        .color(colors::MEM_COLOR)
                )
                .width(Length::Fixed(90.0)),
                container(
                    text(&proc_info.status)
                        .size(11)
                        .color(colors::TEXT_SECONDARY)
                )
                .width(Length::Fixed(80.0)),
            ]
            .spacing(4)
            .padding(Padding::from([3, 8]))
            .align_y(iced::Alignment::Center),
        )
        .style(move |_theme: &iced::Theme| container::Style {
            background: Some(bg.into()),
            border: if is_selected {
                iced::Border {
                    color: colors::ACCENT_BLUE,
                    width: 1.0,
                    radius: 2.0.into(),
                }
            } else {
                iced::Border::default()
            },
            ..Default::default()
        })
        .width(Length::Fill);

        proc_rows.push(proc_row.into());
    }

    let process_list = scrollable(column(proc_rows).spacing(0))
        .height(Length::Fill);

    container(
        column![title_row, filter_input, header_container, process_list].spacing(6),
    )
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
    .height(Length::Fill)
    .into()
}
