use iced::widget::{
    button, column, container, row, scrollable, text, text_input, Column, Row, Space,
};
use iced::{Element, Length, Padding};

use crate::config::ProcessColumnVisibility;
use crate::metrics::memory::MemoryMetrics;
use crate::metrics::process::{ProcessInfo, ProcessMetrics, SortField};
use crate::theme::colors;
use crate::ui::app::Message;

const FILTER_INPUT_ID: &str = "process_filter";
pub const PROCESS_TABLE_SCROLL_ID: &str = "process_table";
pub const PROCESS_ROW_HEIGHT: f32 = 28.0;
const PROCESS_OVERSCAN_ROWS: usize = 8;
const INITIAL_PROCESS_WINDOW_ROWS: usize = 80;

#[derive(Debug, Clone, Copy, PartialEq)]
struct ProcessWindow {
    start: usize,
    end: usize,
    top_spacer_height: f32,
    bottom_spacer_height: f32,
}

pub struct ProcessTableViewOptions<'a> {
    pub selected: Option<usize>,
    pub pending_kill_pid: Option<u32>,
    pub pending_signal_label: &'static str,
    pub saved_filters: &'a [String],
    pub columns: &'a ProcessColumnVisibility,
    pub scroll_y: f32,
    pub viewport_height: f32,
    pub show_details: bool,
}

fn header_button<'a>(
    label: &str,
    field: SortField,
    current: &SortField,
    ascending: bool,
) -> Element<'a, Message> {
    let arrow = if *current == field {
        if ascending {
            " ^"
        } else {
            " v"
        }
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

pub fn process_table_view<'a>(
    processes: &'a ProcessMetrics,
    options: ProcessTableViewOptions<'a>,
) -> Element<'a, Message> {
    let title_row = row![
        text(if processes.tree_mode {
            "Processes - Tree"
        } else {
            "Processes"
        })
        .size(14)
        .color(colors::ACCENT_BLUE),
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
    let saved_filter_row = saved_filter_bar(options.saved_filters, &processes.filter);

    let mut headers = Row::new().spacing(4).padding(Padding::from([4, 8]));

    if options.columns.pid {
        headers = headers.push(
            container(header_button(
                "PID",
                SortField::Pid,
                &processes.sort_field,
                processes.sort_ascending,
            ))
            .width(Length::Fixed(70.0)),
        );
    }

    headers = headers.push(
        container(header_button(
            "Name",
            SortField::Name,
            &processes.sort_field,
            processes.sort_ascending,
        ))
        .width(Length::Fill),
    );

    if options.columns.cpu {
        headers = headers.push(
            container(header_button(
                "CPU%",
                SortField::Cpu,
                &processes.sort_field,
                processes.sort_ascending,
            ))
            .width(Length::Fixed(70.0)),
        );
    }

    if options.columns.memory {
        headers = headers.push(
            container(header_button(
                "Memory",
                SortField::Memory,
                &processes.sort_field,
                processes.sort_ascending,
            ))
            .width(Length::Fixed(90.0)),
        );
    }

    if options.columns.status {
        headers = headers.push(
            container(header_button(
                "Status",
                SortField::Status,
                &processes.sort_field,
                processes.sort_ascending,
            ))
            .width(Length::Fixed(80.0)),
        );
    }

    let headers = headers
        .push(Space::with_width(Length::Shrink))
        .align_y(iced::Alignment::Center);

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
    let window = process_window(filtered.len(), options.scroll_y, options.viewport_height);

    let mut proc_rows: Vec<Element<'a, Message>> =
        Vec::with_capacity(window.end.saturating_sub(window.start) + 2);

    if window.top_spacer_height > 0.0 {
        proc_rows.push(Space::with_height(Length::Fixed(window.top_spacer_height)).into());
    }

    for (window_idx, proc_info) in filtered[window.start..window.end].iter().enumerate() {
        let idx = window.start + window_idx;
        let is_selected = options.selected == Some(idx);
        let is_filter_match =
            !processes.filter.is_empty() && process_matches_filter(proc_info, &processes.filter);

        let bg = if is_selected {
            colors::ACCENT_BLUE_DIM
        } else if is_filter_match {
            colors::with_alpha(colors::ACCENT_YELLOW, 0.12)
        } else if idx.is_multiple_of(2) {
            colors::SURFACE
        } else {
            colors::SURFACE_LIGHT
        };

        let name_color = if field_contains_filter(&proc_info.name, &processes.filter) {
            colors::ACCENT_YELLOW
        } else if is_selected {
            colors::ACCENT_CYAN
        } else {
            colors::TEXT_PRIMARY
        };

        let cpu_color = colors::heat_color(proc_info.cpu_usage.min(100.0));

        let process_name = if proc_info.user.is_empty() {
            proc_info.name.clone()
        } else {
            format!("{} [{}]", proc_info.name, proc_info.user)
        };
        let memory_text = format!(
            "{} / {}",
            MemoryMetrics::format_bytes(proc_info.memory),
            MemoryMetrics::format_bytes(proc_info.virtual_memory),
        );
        let status_text = format!(
            "{} {}",
            proc_info.status,
            format_runtime(proc_info.run_time),
        );

        let mut row_content = Row::new()
            .spacing(4)
            .padding(Padding::from([3, 8]))
            .align_y(iced::Alignment::Center);

        if options.columns.pid {
            row_content = row_content.push(
                container(text(format!("{}", proc_info.pid)).size(11).color(
                    if !processes.filter.is_empty()
                        && proc_info.pid.to_string().contains(&processes.filter)
                    {
                        colors::ACCENT_YELLOW
                    } else {
                        colors::TEXT_DIM
                    },
                ))
                .width(Length::Fixed(70.0)),
            );
        }

        row_content = row_content.push(
            container(
                row![
                    Space::with_width(Length::Fixed((proc_info.depth * 14) as f32)),
                    text(process_name).size(11).color(name_color),
                ]
                .spacing(2)
                .align_y(iced::Alignment::Center),
            )
            .width(Length::Fill),
        );

        if options.columns.cpu {
            row_content = row_content.push(
                container(
                    text(format!("{:.1}", proc_info.cpu_usage))
                        .size(11)
                        .color(cpu_color),
                )
                .width(Length::Fixed(70.0)),
            );
        }

        if options.columns.memory {
            row_content = row_content.push(
                container(text(memory_text).size(11).color(colors::MEM_COLOR))
                    .width(Length::Fixed(90.0)),
            );
        }

        if options.columns.status {
            row_content = row_content.push(
                container(text(status_text).size(11).color(colors::TEXT_SECONDARY))
                    .width(Length::Fixed(80.0)),
            );
        }

        let proc_row = container(row_content)
            .height(Length::Fixed(PROCESS_ROW_HEIGHT))
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

    if window.bottom_spacer_height > 0.0 {
        proc_rows.push(Space::with_height(Length::Fixed(window.bottom_spacer_height)).into());
    }

    let process_list = scrollable(column(proc_rows).spacing(0))
        .id(iced::widget::scrollable::Id::new(PROCESS_TABLE_SCROLL_ID))
        .on_scroll(|viewport| Message::ProcessTableScrolled {
            offset_y: viewport.absolute_offset().y,
            viewport_height: viewport.bounds().height,
        })
        .height(Length::Fill);

    let mut content = Column::new().spacing(6).push(title_row).push(filter_input);

    if let Some(saved_filter_row) = saved_filter_row {
        content = content.push(saved_filter_row);
    }

    if let Some(pid) = options.pending_kill_pid {
        content = content.push(
            container(
                text(format!(
                    "Press k or Delete again to send {} to PID {pid}",
                    options.pending_signal_label
                ))
                .size(11)
                .color(colors::ACCENT_RED),
            )
            .padding(Padding::from([3, 8]))
            .style(|_theme: &iced::Theme| container::Style {
                background: Some(colors::SURFACE_LIGHT.into()),
                border: iced::Border {
                    color: colors::ACCENT_RED,
                    width: 1.0,
                    radius: 4.0.into(),
                },
                ..Default::default()
            })
            .width(Length::Fill),
        );
    }

    if options.show_details {
        if let Some(selected_process) = options.selected.and_then(|idx| filtered.get(idx)).copied()
        {
            content = content.push(process_detail_view(selected_process, &processes.filter));
        }
    }

    content = content.push(header_container).push(process_list);

    container(content)
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

fn process_detail_view<'a>(
    process: &'a crate::metrics::process::ProcessInfo,
    filter: &str,
) -> Element<'a, Message> {
    let parent = process
        .parent_pid
        .map(|pid| pid.to_string())
        .unwrap_or_else(|| "-".to_string());
    let threads = process
        .thread_count
        .map(|count| count.to_string())
        .unwrap_or_else(|| "-".to_string());
    let exe = process.exe.as_deref().unwrap_or("-");
    let cwd = process.cwd.as_deref().unwrap_or("-");
    let command = if process.cmd.is_empty() {
        "-"
    } else {
        process.cmd.as_str()
    };

    container(
        column![
            row![
                text(format!("PID {}", process.pid))
                    .size(11)
                    .color(colors::ACCENT_CYAN),
                text(format!("PPID {parent}"))
                    .size(11)
                    .color(colors::TEXT_SECONDARY),
                text(format!("Threads {threads}"))
                    .size(11)
                    .color(colors::TEXT_SECONDARY),
                text(format!("Started {}", process.start_time))
                    .size(11)
                    .color(colors::TEXT_SECONDARY),
            ]
            .spacing(12),
            text(format!("Exe: {exe}"))
                .size(10)
                .color(colors::TEXT_SECONDARY),
            text(format!("Cwd: {cwd}"))
                .size(10)
                .color(colors::TEXT_SECONDARY),
            text(format!("Cmd: {command}")).size(10).color(
                if field_contains_filter(command, filter) {
                    colors::ACCENT_YELLOW
                } else {
                    colors::TEXT_DIM
                }
            ),
        ]
        .spacing(3),
    )
    .padding(Padding::from([6, 8]))
    .style(|_theme: &iced::Theme| container::Style {
        background: Some(colors::SURFACE_LIGHT.into()),
        border: iced::Border {
            color: colors::SURFACE_BORDER,
            width: 1.0,
            radius: 4.0.into(),
        },
        ..Default::default()
    })
    .width(Length::Fill)
    .into()
}

fn saved_filter_bar<'a>(
    saved_filters: &'a [String],
    current_filter: &str,
) -> Option<Element<'a, Message>> {
    if saved_filters.is_empty() {
        return None;
    }

    let mut filters = Row::new().spacing(4).align_y(iced::Alignment::Center);
    for filter in saved_filters.iter().take(6) {
        let is_active = filter == current_filter;
        let label = truncate_filter_label(filter);
        filters = filters.push(
            button(text(label).size(10).color(if is_active {
                colors::BACKGROUND
            } else {
                colors::TEXT_SECONDARY
            }))
            .on_press(Message::ApplySavedFilter(filter.clone()))
            .padding(Padding::from([2, 6]))
            .style(move |_theme: &iced::Theme, _status| button::Style {
                background: Some(if is_active {
                    colors::ACCENT_CYAN.into()
                } else {
                    colors::SURFACE_LIGHT.into()
                }),
                text_color: if is_active {
                    colors::BACKGROUND
                } else {
                    colors::TEXT_SECONDARY
                },
                border: iced::Border {
                    color: colors::SURFACE_BORDER,
                    width: 1.0,
                    radius: 4.0.into(),
                },
                ..Default::default()
            }),
        );
    }

    Some(filters.into())
}

fn truncate_filter_label(filter: &str) -> String {
    const MAX_CHARS: usize = 18;
    let mut chars = filter.chars();
    let label: String = chars.by_ref().take(MAX_CHARS).collect();
    if chars.next().is_some() {
        format!("{label}...")
    } else {
        label
    }
}

fn format_runtime(seconds: u64) -> String {
    let hours = seconds / 3600;
    let minutes = (seconds % 3600) / 60;
    let seconds = seconds % 60;

    if hours > 0 {
        format!("{hours}h{minutes:02}m")
    } else if minutes > 0 {
        format!("{minutes}m{seconds:02}s")
    } else {
        format!("{seconds}s")
    }
}

fn process_matches_filter(process: &ProcessInfo, filter: &str) -> bool {
    field_contains_filter(&process.name, filter)
        || process.pid.to_string().contains(filter)
        || field_contains_filter(&process.cmd, filter)
}

fn field_contains_filter(value: &str, filter: &str) -> bool {
    if filter.is_empty() {
        return false;
    }

    value.to_lowercase().contains(&filter.to_lowercase())
}

fn process_window(total_rows: usize, scroll_y: f32, viewport_height: f32) -> ProcessWindow {
    let viewport_rows = if viewport_height > 0.0 {
        (viewport_height / PROCESS_ROW_HEIGHT).ceil() as usize
    } else {
        INITIAL_PROCESS_WINDOW_ROWS
    };
    let first_visible = (scroll_y.max(0.0) / PROCESS_ROW_HEIGHT).floor() as usize;
    let start = first_visible
        .saturating_sub(PROCESS_OVERSCAN_ROWS)
        .min(total_rows);
    let end = first_visible
        .saturating_add(viewport_rows)
        .saturating_add(PROCESS_OVERSCAN_ROWS * 2)
        .min(total_rows)
        .max(start);

    ProcessWindow {
        start,
        end,
        top_spacer_height: start as f32 * PROCESS_ROW_HEIGHT,
        bottom_spacer_height: total_rows.saturating_sub(end) as f32 * PROCESS_ROW_HEIGHT,
    }
}

#[cfg(test)]
mod tests {
    use super::{process_window, ProcessWindow, PROCESS_ROW_HEIGHT};

    #[test]
    fn process_window_keeps_scroll_geometry_for_large_tables() {
        let window = process_window(1_000, PROCESS_ROW_HEIGHT * 500.0, PROCESS_ROW_HEIGHT * 20.0);

        assert_eq!(window.start, 492);
        assert_eq!(window.end, 536);
        assert_eq!(window.top_spacer_height, 492.0 * PROCESS_ROW_HEIGHT);
        assert_eq!(window.bottom_spacer_height, 464.0 * PROCESS_ROW_HEIGHT);
    }

    #[test]
    fn process_window_handles_short_tables_without_spacers() {
        let window = process_window(5, 0.0, 0.0);

        assert_eq!(
            window,
            ProcessWindow {
                start: 0,
                end: 5,
                top_spacer_height: 0.0,
                bottom_spacer_height: 0.0,
            }
        );
    }
}
