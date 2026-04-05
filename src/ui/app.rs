use std::time::Duration;

use iced::keyboard::{self, Key, Modifiers};
use iced::widget::{column, container, row, text, text_input};
use iced::{Element, Length, Padding, Subscription, Theme};

use crate::metrics::SystemMetrics;
use crate::metrics::memory::MemoryMetrics;
use crate::metrics::process::SortField;
use crate::theme;
use crate::theme::colors;
use crate::ui::widgets::{
    cpu_cores::cpu_cores_view,
    disk_bar::disk_view,
    gpu_view::gpu_panel_view,
    graph::graph_view,
    header::header_view,
    network_view::network_view,
    process_table::process_table_view,
};

const FILTER_INPUT_ID: &str = "process_filter";

#[derive(Debug, Clone)]
pub enum Message {
    Tick,
    SortBy(SortField),
    FilterChanged(String),
    KeyPressed(KeyAction),
}

#[derive(Debug, Clone)]
pub enum KeyAction {
    Quit,
    FocusFilter,
    Escape,
    SelectUp,
    SelectDown,
    KillSelected,
    SortColumn(SortField),
    ToggleSortDirection,
}

pub struct RustTop {
    metrics: SystemMetrics,
    pub selected_process: Option<usize>,
    show_kill_confirm: bool,
}

impl RustTop {
    pub fn new() -> Self {
        let mut metrics = SystemMetrics::new();
        metrics.refresh();
        Self {
            metrics,
            selected_process: None,
            show_kill_confirm: false,
        }
    }

    pub fn update(&mut self, message: Message) -> iced::Task<Message> {
        match message {
            Message::Tick => {
                self.metrics.refresh();
            }
            Message::SortBy(field) => {
                self.metrics.processes.toggle_sort(field);
                self.selected_process = None;
            }
            Message::FilterChanged(filter) => {
                self.metrics.processes.filter = filter;
                self.selected_process = None;
            }
            Message::KeyPressed(action) => {
                return self.handle_key_action(action);
            }
        }
        iced::Task::none()
    }

    fn handle_key_action(&mut self, action: KeyAction) -> iced::Task<Message> {
        match action {
            KeyAction::Quit => {
                std::process::exit(0);
            }
            KeyAction::FocusFilter => {
                return text_input::focus(text_input::Id::new(FILTER_INPUT_ID));
            }
            KeyAction::Escape => {
                self.metrics.processes.filter.clear();
                self.selected_process = None;
                self.show_kill_confirm = false;
            }
            KeyAction::SelectUp => {
                let count = self.visible_process_count();
                if count == 0 {
                    return iced::Task::none();
                }
                self.selected_process = Some(match self.selected_process {
                    Some(i) if i > 0 => i - 1,
                    Some(_) => 0,
                    None => 0,
                });
                self.show_kill_confirm = false;
            }
            KeyAction::SelectDown => {
                let count = self.visible_process_count();
                if count == 0 {
                    return iced::Task::none();
                }
                let max_idx = count.saturating_sub(1).min(199);
                self.selected_process = Some(match self.selected_process {
                    Some(i) if i < max_idx => i + 1,
                    Some(i) => i,
                    None => 0,
                });
                self.show_kill_confirm = false;
            }
            KeyAction::KillSelected => {
                if let Some(idx) = self.selected_process {
                    let filtered = self.metrics.processes.filtered_processes();
                    if let Some(proc_info) = filtered.get(idx) {
                        self.metrics.processes.kill_process(proc_info.pid);
                        self.selected_process = None;
                    }
                }
            }
            KeyAction::SortColumn(field) => {
                self.metrics.processes.toggle_sort(field);
                self.selected_process = None;
            }
            KeyAction::ToggleSortDirection => {
                self.metrics.processes.sort_ascending = !self.metrics.processes.sort_ascending;
            }
        }
        iced::Task::none()
    }

    fn visible_process_count(&self) -> usize {
        self.metrics.processes.filtered_processes().len()
    }

    pub fn view(&self) -> Element<'_, Message> {
        let m = &self.metrics;

        // Header bar
        let header = header_view(m);

        // CPU graph
        let cpu_graph = graph_view(
            &m.cpu.history,
            100.0,
            colors::CPU_COLOR,
            &format!("CPU — {}", m.cpu.brand),
            &format!("{:.1}%", m.cpu.global_usage),
        );

        // Memory graph
        let mem_graph = graph_view(
            &m.memory.mem_history,
            100.0,
            colors::MEM_COLOR,
            "Memory",
            &format!(
                "{:.1}% — {} / {}",
                m.memory.mem_usage_percent,
                MemoryMetrics::format_bytes(m.memory.used_mem),
                MemoryMetrics::format_bytes(m.memory.total_mem),
            ),
        );

        // Per-core CPU view with btop-style dots
        let cores_view = cpu_cores_view(&m.cpu);

        // GPU panel
        let gpu_panel = gpu_panel_view(&m.gpu);

        // Network + Disk row
        let net_view = network_view(&m.network);
        let disks = disk_view(&m.disk);

        // Left panel: CPU full-width, cores, GPU, then network | disks+memory
        let left_panel = column![
            // CPU graph — full width
            container(cpu_graph)
                .width(Length::Fill)
                .height(Length::FillPortion(2)),
            // CPU cores
            container(cores_view)
                .width(Length::Fill)
                .height(Length::FillPortion(2)),
            // GPU panel
            container(gpu_panel)
                .width(Length::Fill)
                .height(Length::FillPortion(3)),
            // Bottom row: Network (left) | Disks + Memory (right)
            row![
                container(net_view)
                    .width(Length::FillPortion(1))
                    .height(Length::Fill),
                column![
                    disks,
                    mem_graph,
                ]
                .spacing(8)
                .width(Length::FillPortion(1))
                .height(Length::Fill),
            ]
            .spacing(8)
            .height(Length::FillPortion(4)),
        ]
        .spacing(8)
        .width(Length::FillPortion(1))
        .height(Length::Fill);

        // Right panel: process table
        let right_panel = container(process_table_view(&m.processes, self.selected_process))
            .width(Length::FillPortion(1))
            .height(Length::Fill);

        // Help bar
        let help_bar = container(
            row![
                help_key("q", "Quit"),
                help_key("/", "Filter"),
                help_key("Esc", "Clear"),
                help_key("\u{2191}\u{2193}", "Select"),
                help_key("Del", "Kill"),
                help_key("F1-F5", "Sort"),
                help_key("Tab", "Reverse"),
            ]
            .spacing(16)
            .align_y(iced::Alignment::Center),
        )
        .padding(Padding::from([4, 12]))
        .width(Length::Fill)
        .style(|_theme: &Theme| container::Style {
            background: Some(colors::SURFACE.into()),
            border: iced::Border {
                color: colors::SURFACE_BORDER,
                width: 1.0,
                radius: 0.0.into(),
            },
            ..Default::default()
        });

        // Main layout
        let content = column![
            header,
            container(
                row![left_panel, right_panel].spacing(8)
            )
            .padding(Padding::from([8, 12]))
            .width(Length::Fill)
            .height(Length::Fill),
            help_bar,
        ]
        .spacing(0);

        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .style(|_theme: &Theme| container::Style {
                background: Some(colors::BACKGROUND.into()),
                ..Default::default()
            })
            .into()
    }

    pub fn subscription(&self) -> Subscription<Message> {
        Subscription::batch([
            iced::time::every(Duration::from_millis(500)).map(|_| Message::Tick),
            keyboard::on_key_press(handle_key_press),
        ])
    }

    pub fn theme(&self) -> Theme {
        theme::app_theme()
    }
}

fn help_key<'a>(key: &'a str, label: &'a str) -> Element<'a, Message> {
    row![
        container(
            text(key).size(10).color(colors::BACKGROUND)
        )
        .padding(Padding::from([1, 4]))
        .style(|_theme: &Theme| container::Style {
            background: Some(colors::TEXT_SECONDARY.into()),
            border: iced::Border {
                radius: 3.0.into(),
                ..Default::default()
            },
            ..Default::default()
        }),
        text(label).size(10).color(colors::TEXT_DIM),
    ]
    .spacing(4)
    .align_y(iced::Alignment::Center)
    .into()
}

fn handle_key_press(key: Key, modifiers: Modifiers) -> Option<Message> {
    use keyboard::key::Named;

    match key {
        // Ctrl+Q always quits
        Key::Character(ref c) if c.as_str() == "q" && modifiers.command() => {
            Some(Message::KeyPressed(KeyAction::Quit))
        }
        // q quits (only fires when text input not focused, per iced's Ignored status)
        Key::Character(ref c) if c.as_str() == "q" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::Quit))
        }
        // / focuses filter
        Key::Character(ref c) if c.as_str() == "/" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::FocusFilter))
        }
        // Escape clears
        Key::Named(Named::Escape) => {
            Some(Message::KeyPressed(KeyAction::Escape))
        }
        // Arrow keys for process selection
        Key::Named(Named::ArrowUp) => {
            Some(Message::KeyPressed(KeyAction::SelectUp))
        }
        Key::Named(Named::ArrowDown) => {
            Some(Message::KeyPressed(KeyAction::SelectDown))
        }
        // k or Delete to kill selected process
        Key::Character(ref c) if c.as_str() == "k" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::KillSelected))
        }
        Key::Named(Named::Delete) => {
            Some(Message::KeyPressed(KeyAction::KillSelected))
        }
        // F1-F5 for sorting columns
        Key::Named(Named::F1) => {
            Some(Message::KeyPressed(KeyAction::SortColumn(SortField::Pid)))
        }
        Key::Named(Named::F2) => {
            Some(Message::KeyPressed(KeyAction::SortColumn(SortField::Name)))
        }
        Key::Named(Named::F3) => {
            Some(Message::KeyPressed(KeyAction::SortColumn(SortField::Cpu)))
        }
        Key::Named(Named::F4) => {
            Some(Message::KeyPressed(KeyAction::SortColumn(SortField::Memory)))
        }
        Key::Named(Named::F5) => {
            Some(Message::KeyPressed(KeyAction::SortColumn(SortField::Status)))
        }
        // Tab to toggle sort direction
        Key::Named(Named::Tab) if modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::ToggleSortDirection))
        }
        _ => None,
    }
}
