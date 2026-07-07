use std::time::Instant;

use iced::keyboard::{self, Key, Modifiers};
use iced::widget::scrollable::{self, AbsoluteOffset};
use iced::widget::{container, row, text, text_input, Column};
use iced::{Element, Length, Padding, Subscription, Theme};

use crate::alerts::{Alert, AlertEngine};
use crate::config::{LayoutPreset, RuntimeOptions};
use crate::export::{append_history_snapshot, history_path, SystemSnapshot};
use crate::metrics::memory::MemoryMetrics;
use crate::metrics::process::{ProcessSignal, SortField};
use crate::metrics::SystemMetrics;
use crate::theme;
use crate::theme::colors;
use crate::ui::widgets::{
    alerts_panel::alerts_panel_view,
    cpu_cores::cpu_cores_view,
    disk_bar::disk_view,
    gpu_view::gpu_panel_view,
    graph::graph_view,
    header::header_view,
    network_view::network_view,
    power_sensors::{battery_panel_view, sensors_panel_view},
    process_table::{
        process_table_view, ProcessTableViewOptions, PROCESS_ROW_HEIGHT, PROCESS_TABLE_SCROLL_ID,
    },
};

const FILTER_INPUT_ID: &str = "process_filter";

#[derive(Debug, Clone)]
pub enum Message {
    Tick,
    SortBy(SortField),
    FilterChanged(String),
    ApplySavedFilter(String),
    KeyPressed(KeyAction),
    ProcessTableScrolled { offset_y: f32, viewport_height: f32 },
    ToggleSettings,
    ApplyLayoutPreset(LayoutPreset),
    ToggleCompactMode,
    CycleTheme,
    ToggleAlerts,
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
    ToggleTreeMode,
    ToggleDetails,
    CycleSignal,
    SaveFilter,
    CycleSavedFilter,
    CycleColumnPreset,
    ToggleSettings,
    CycleLayoutPreset,
    ToggleCompactMode,
    CycleTheme,
}

pub struct RustTop {
    metrics: SystemMetrics,
    settings: RuntimeOptions,
    pub selected_process: Option<usize>,
    pending_kill_pid: Option<u32>,
    show_process_details: bool,
    selected_signal: ProcessSignal,
    saved_filter_index: Option<usize>,
    process_scroll_y: f32,
    process_viewport_height: f32,
    show_settings: bool,
    last_history_write: Option<Instant>,
    alert_engine: AlertEngine,
    active_alerts: Vec<Alert>,
}

impl RustTop {
    pub fn new(settings: RuntimeOptions) -> Self {
        let mut metrics = SystemMetrics::new(
            settings.panels.gpu,
            settings.default_sort.clone(),
            settings.sort_ascending,
        );
        metrics.refresh();
        Self {
            metrics,
            settings,
            selected_process: None,
            pending_kill_pid: None,
            show_process_details: false,
            selected_signal: ProcessSignal::default_action(),
            saved_filter_index: None,
            process_scroll_y: 0.0,
            process_viewport_height: 0.0,
            show_settings: false,
            last_history_write: None,
            alert_engine: AlertEngine::new(),
            active_alerts: Vec::new(),
        }
    }

    pub fn update(&mut self, message: Message) -> iced::Task<Message> {
        match message {
            Message::Tick => {
                self.metrics.refresh();
                let scroll_task = self.reconcile_process_view_after_refresh();
                self.active_alerts = self.alert_engine.evaluate(
                    &self.metrics,
                    &self.settings.alerts,
                    Instant::now(),
                );
                self.persist_history_if_due();
                if let Some(task) = scroll_task {
                    return task;
                }
            }
            Message::SortBy(field) => {
                self.metrics.processes.toggle_sort(field);
                self.selected_process = None;
                self.pending_kill_pid = None;
                return self.reset_process_scroll();
            }
            Message::FilterChanged(filter) => {
                self.metrics.processes.filter = filter;
                self.selected_process = None;
                self.pending_kill_pid = None;
                self.saved_filter_index = None;
                return self.reset_process_scroll();
            }
            Message::ApplySavedFilter(filter) => {
                self.metrics.processes.filter = filter;
                self.saved_filter_index = self
                    .settings
                    .config
                    .process_table
                    .saved_filters
                    .iter()
                    .position(|saved| saved == &self.metrics.processes.filter);
                self.selected_process = None;
                self.pending_kill_pid = None;
                return self.reset_process_scroll();
            }
            Message::KeyPressed(action) => {
                return self.handle_key_action(action);
            }
            Message::ProcessTableScrolled {
                offset_y,
                viewport_height,
            } => {
                self.process_scroll_y = offset_y.max(0.0);
                self.process_viewport_height = viewport_height.max(0.0);
            }
            Message::ToggleSettings => {
                self.show_settings = !self.show_settings;
            }
            Message::ApplyLayoutPreset(preset) => {
                self.apply_layout_preset(preset);
            }
            Message::ToggleCompactMode => {
                self.toggle_compact_mode();
            }
            Message::CycleTheme => {
                self.cycle_theme();
            }
            Message::ToggleAlerts => {
                self.toggle_alerts();
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
                self.pending_kill_pid = None;
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
                self.pending_kill_pid = None;
                return self.scroll_selected_process_into_view();
            }
            KeyAction::SelectDown => {
                let count = self.visible_process_count();
                if count == 0 {
                    return iced::Task::none();
                }
                let max_idx = count.saturating_sub(1);
                self.selected_process = Some(match self.selected_process {
                    Some(i) if i < max_idx => i + 1,
                    Some(i) => i,
                    None => 0,
                });
                self.pending_kill_pid = None;
                return self.scroll_selected_process_into_view();
            }
            KeyAction::KillSelected => {
                if let Some(idx) = self.selected_process {
                    let filtered = self.metrics.processes.filtered_processes();
                    if let Some(proc_info) = filtered.get(idx) {
                        if self.pending_kill_pid == Some(proc_info.pid) {
                            if self
                                .metrics
                                .processes
                                .signal_process(proc_info.pid, self.selected_signal)
                                .unwrap_or(false)
                            {
                                self.selected_process = None;
                                self.pending_kill_pid = None;
                            }
                        } else {
                            self.pending_kill_pid = Some(proc_info.pid);
                        }
                    }
                }
            }
            KeyAction::SortColumn(field) => {
                self.metrics.processes.toggle_sort(field);
                self.selected_process = None;
                self.pending_kill_pid = None;
                return self.reset_process_scroll();
            }
            KeyAction::ToggleSortDirection => {
                self.metrics.processes.toggle_sort_direction();
                self.selected_process = None;
                self.pending_kill_pid = None;
                return self.reset_process_scroll();
            }
            KeyAction::ToggleTreeMode => {
                self.metrics.processes.toggle_tree_mode();
                self.selected_process = None;
                self.pending_kill_pid = None;
                return self.reset_process_scroll();
            }
            KeyAction::ToggleDetails => {
                self.show_process_details = !self.show_process_details;
                self.pending_kill_pid = None;
            }
            KeyAction::CycleSignal => {
                self.selected_signal = self.selected_signal.next();
                self.pending_kill_pid = None;
            }
            KeyAction::SaveFilter => {
                self.save_current_filter();
            }
            KeyAction::CycleSavedFilter => {
                self.cycle_saved_filter();
                return self.reset_process_scroll();
            }
            KeyAction::CycleColumnPreset => {
                self.cycle_process_columns();
            }
            KeyAction::ToggleSettings => {
                self.show_settings = !self.show_settings;
            }
            KeyAction::CycleLayoutPreset => {
                self.apply_layout_preset(self.settings.layout_preset.next());
            }
            KeyAction::ToggleCompactMode => {
                self.toggle_compact_mode();
            }
            KeyAction::CycleTheme => {
                self.cycle_theme();
            }
        }
        iced::Task::none()
    }

    fn visible_process_count(&self) -> usize {
        self.metrics.processes.filtered_processes().len()
    }

    fn reset_process_scroll(&mut self) -> iced::Task<Message> {
        self.process_scroll_y = 0.0;
        scrollable::scroll_to(
            scrollable::Id::new(PROCESS_TABLE_SCROLL_ID),
            AbsoluteOffset { x: 0.0, y: 0.0 },
        )
    }

    fn scroll_selected_process_into_view(&mut self) -> iced::Task<Message> {
        let Some(index) = self.selected_process else {
            return iced::Task::none();
        };

        let viewport_height = if self.process_viewport_height > 0.0 {
            self.process_viewport_height
        } else {
            PROCESS_ROW_HEIGHT * 16.0
        };
        let current_top = self.process_scroll_y.max(0.0);
        let current_bottom = current_top + viewport_height;
        let row_top = index as f32 * PROCESS_ROW_HEIGHT;
        let row_bottom = row_top + PROCESS_ROW_HEIGHT;

        let target_y = if row_top < current_top {
            row_top
        } else if row_bottom > current_bottom {
            row_bottom - viewport_height
        } else {
            return iced::Task::none();
        }
        .max(0.0);

        self.process_scroll_y = target_y;
        scrollable::scroll_to(
            scrollable::Id::new(PROCESS_TABLE_SCROLL_ID),
            AbsoluteOffset {
                x: 0.0,
                y: target_y,
            },
        )
    }

    fn reconcile_process_view_after_refresh(&mut self) -> Option<iced::Task<Message>> {
        let visible = self.metrics.processes.filtered_processes();
        let count = visible.len();

        if self
            .pending_kill_pid
            .is_some_and(|pid| !visible.iter().any(|process| process.pid == pid))
        {
            self.pending_kill_pid = None;
        }

        if self.selected_process.is_some_and(|index| index >= count) {
            self.selected_process = count.checked_sub(1);
        }

        let viewport_height = if self.process_viewport_height > 0.0 {
            self.process_viewport_height
        } else {
            PROCESS_ROW_HEIGHT * 16.0
        };
        let content_height = count as f32 * PROCESS_ROW_HEIGHT;
        let max_scroll = (content_height - viewport_height).max(0.0);
        if self.process_scroll_y > max_scroll {
            self.process_scroll_y = max_scroll;
            return Some(scrollable::scroll_to(
                scrollable::Id::new(PROCESS_TABLE_SCROLL_ID),
                AbsoluteOffset {
                    x: 0.0,
                    y: max_scroll,
                },
            ));
        }

        None
    }

    fn save_current_filter(&mut self) {
        let filter = self.metrics.processes.filter.trim().to_string();
        if filter.is_empty() {
            return;
        }

        if let Some(existing_index) = self
            .settings
            .config
            .process_table
            .saved_filters
            .iter()
            .position(|saved| saved == &filter)
        {
            self.saved_filter_index = Some(existing_index);
            return;
        }

        self.settings
            .config
            .process_table
            .saved_filters
            .push(filter);
        self.saved_filter_index = self
            .settings
            .config
            .process_table
            .saved_filters
            .len()
            .checked_sub(1);
        self.persist_config();
    }

    fn cycle_saved_filter(&mut self) {
        let saved_filters = &self.settings.config.process_table.saved_filters;
        if saved_filters.is_empty() {
            return;
        }

        let next_index = self
            .saved_filter_index
            .map(|index| (index + 1) % saved_filters.len())
            .unwrap_or(0);

        self.metrics.processes.filter = saved_filters[next_index].clone();
        self.saved_filter_index = Some(next_index);
        self.selected_process = None;
        self.pending_kill_pid = None;
    }

    fn cycle_process_columns(&mut self) {
        self.settings.process_columns = self.settings.process_columns.next_preset();
        self.settings.config.process_table.columns = self.settings.process_columns.to_names();
        self.pending_kill_pid = None;
        self.persist_config();
    }

    fn apply_layout_preset(&mut self, preset: LayoutPreset) {
        self.settings.layout_preset = preset;
        self.settings.panels = preset.apply_to(self.settings.config.panels.clone());
        if !self.settings.gpu_allowed {
            self.settings.panels.gpu = false;
        }
        self.settings.config.appearance.layout_preset = preset.config_value().to_string();
        self.pending_kill_pid = None;
        self.persist_config();
    }

    fn toggle_compact_mode(&mut self) {
        self.settings.compact_mode = !self.settings.compact_mode;
        self.settings.config.appearance.compact_mode = self.settings.compact_mode;
        self.pending_kill_pid = None;
        self.persist_config();
    }

    fn cycle_theme(&mut self) {
        self.settings.theme = theme::next_theme(&self.settings.theme).to_string();
        self.settings.config.appearance.theme = self.settings.theme.clone();
        self.persist_config();
    }

    fn toggle_alerts(&mut self) {
        self.settings.alerts.enabled = !self.settings.alerts.enabled;
        self.settings.config.alerts.enabled = self.settings.alerts.enabled;
        self.alert_engine = AlertEngine::new();
        self.active_alerts.clear();
        self.persist_config();
    }

    fn persist_history_if_due(&mut self) {
        if !self.settings.history.enabled {
            return;
        }

        let now = Instant::now();
        let interval_seconds = self.settings.history.interval_seconds.max(1);
        if self
            .last_history_write
            .is_some_and(|last| now.duration_since(last).as_secs() < interval_seconds)
        {
            return;
        }

        let snapshot =
            SystemSnapshot::from_metrics_with_alerts(&self.metrics, self.active_alerts.clone());
        let path = history_path(self.settings.history.path.as_deref());
        if let Err(error) =
            append_history_snapshot(&path, &snapshot, self.settings.history.retention_samples)
        {
            eprintln!("{error}");
        } else {
            self.last_history_write = Some(now);
        }
    }

    fn persist_config(&self) {
        if let Some(path) = self.settings.config_path.as_ref() {
            if let Err(error) = self.settings.config.write_to_path(path) {
                eprintln!("{error}");
            }
        }
    }

    pub fn view(&self) -> Element<'_, Message> {
        let m = &self.metrics;
        let panel_spacing = if self.settings.compact_mode { 4 } else { 8 };
        let main_padding = if self.settings.compact_mode {
            Padding::from([4, 8])
        } else {
            Padding::from([8, 12])
        };

        // Header bar
        let header = header_view(m);

        let cpu_history = m.cpu.history.values();
        let mem_history = m.memory.mem_history.values();

        let cpu_graph = graph_view(
            &cpu_history,
            100.0,
            colors::CPU_COLOR,
            &format!("CPU — {}", m.cpu.brand),
            &format!("{:.1}%", m.cpu.global_usage),
        );

        // Memory graph
        let mem_graph = graph_view(
            &mem_history,
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

        let mut left_panel = Column::new()
            .spacing(panel_spacing)
            .width(Length::FillPortion(1))
            .height(Length::Fill);

        if self.settings.panels.cpu {
            left_panel = left_panel
                .push(
                    container(cpu_graph)
                        .width(Length::Fill)
                        .height(Length::FillPortion(2)),
                )
                .push(
                    container(cores_view)
                        .width(Length::Fill)
                        .height(Length::FillPortion(2)),
                );
        }

        if self.settings.panels.gpu {
            left_panel = left_panel.push(
                container(gpu_panel)
                    .width(Length::Fill)
                    .height(Length::FillPortion(3)),
            );
        }

        let mut bottom_row = row![].spacing(panel_spacing).height(Length::FillPortion(4));
        let mut has_bottom_content = false;

        if self.settings.panels.network {
            bottom_row = bottom_row.push(
                container(net_view)
                    .width(Length::FillPortion(1))
                    .height(Length::Fill),
            );
            has_bottom_content = true;
        }

        let mut metrics_column = Column::new()
            .spacing(panel_spacing)
            .width(Length::FillPortion(1))
            .height(Length::Fill);
        let mut has_metrics_column = false;

        if self.settings.panels.disk {
            metrics_column = metrics_column.push(disks);
            has_metrics_column = true;
        }
        if self.settings.panels.battery {
            metrics_column = metrics_column.push(battery_panel_view(&m.battery));
            has_metrics_column = true;
        }
        if self.settings.panels.sensors {
            metrics_column = metrics_column.push(sensors_panel_view(&m.sensors));
            has_metrics_column = true;
        }
        if self.settings.panels.memory {
            metrics_column = metrics_column.push(mem_graph);
            has_metrics_column = true;
        }
        if has_metrics_column {
            bottom_row = bottom_row.push(metrics_column);
            has_bottom_content = true;
        }
        if has_bottom_content {
            left_panel = left_panel.push(bottom_row);
        }

        // Help bar
        let help_bar = container(
            row![
                help_key("q", "Quit"),
                help_key(",", "Settings"),
                help_key("/", "Filter"),
                help_key("Esc", "Clear"),
                help_key("\u{2191}\u{2193}", "Select"),
                help_key("Del", "Kill"),
                help_key("s", self.selected_signal.label()),
                help_key("f", "Saved"),
                help_key("w", "Save"),
                help_key("c", self.settings.process_columns.label()),
                help_key("l", self.settings.layout_preset.label()),
                help_key(
                    "m",
                    if self.settings.compact_mode {
                        "Dense"
                    } else {
                        "Roomy"
                    }
                ),
                help_key("Enter", "Details"),
                help_key("t", "Tree"),
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
        let main_content = container({
            let mut main_row = row![left_panel].spacing(panel_spacing);
            if self.settings.panels.processes {
                main_row = main_row.push(
                    container(process_table_view(
                        &m.processes,
                        ProcessTableViewOptions {
                            selected: self.selected_process,
                            pending_kill_pid: self.pending_kill_pid,
                            pending_signal_label: self.selected_signal.label(),
                            saved_filters: &self.settings.config.process_table.saved_filters,
                            columns: &self.settings.process_columns,
                            scroll_y: self.process_scroll_y,
                            viewport_height: self.process_viewport_height,
                            show_details: self.show_process_details,
                        },
                    ))
                    .width(Length::FillPortion(1))
                    .height(Length::Fill),
                );
            }
            main_row
        })
        .padding(main_padding)
        .width(Length::Fill)
        .height(Length::Fill);

        let mut content = Column::new().spacing(0).push(header);
        if self.show_settings {
            content = content.push(crate::ui::widgets::settings_panel::settings_panel_view(
                &self.settings,
            ));
        }
        if let Some(alerts_panel) = alerts_panel_view(&self.active_alerts) {
            content = content.push(alerts_panel);
        }
        content = content.push(main_content).push(help_bar);

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
            iced::time::every(self.settings.refresh_interval).map(|_| Message::Tick),
            keyboard::on_key_press(handle_key_press),
        ])
    }

    pub fn theme(&self) -> Theme {
        theme::app_theme(&self.settings.theme)
    }
}

fn help_key<'a>(key: &'a str, label: &'a str) -> Element<'a, Message> {
    row![
        container(text(key).size(10).color(colors::BACKGROUND))
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
        Key::Character(ref c) if c.as_str() == "," && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::ToggleSettings))
        }
        Key::Character(ref c) if c.as_str() == "l" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::CycleLayoutPreset))
        }
        Key::Character(ref c) if c.as_str() == "m" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::ToggleCompactMode))
        }
        Key::Character(ref c) if c.as_str() == "g" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::CycleTheme))
        }
        // / focuses filter
        Key::Character(ref c) if c.as_str() == "/" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::FocusFilter))
        }
        // Escape clears
        Key::Named(Named::Escape) => Some(Message::KeyPressed(KeyAction::Escape)),
        // Arrow keys for process selection
        Key::Named(Named::ArrowUp) => Some(Message::KeyPressed(KeyAction::SelectUp)),
        Key::Named(Named::ArrowDown) => Some(Message::KeyPressed(KeyAction::SelectDown)),
        // k or Delete to kill selected process
        Key::Character(ref c) if c.as_str() == "k" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::KillSelected))
        }
        Key::Named(Named::Delete) => Some(Message::KeyPressed(KeyAction::KillSelected)),
        // s cycles the signal/action sent by the guarded process command
        Key::Character(ref c) if c.as_str() == "s" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::CycleSignal))
        }
        // f cycles saved filters; w writes the current filter to config
        Key::Character(ref c) if c.as_str() == "f" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::CycleSavedFilter))
        }
        Key::Character(ref c) if c.as_str() == "w" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::SaveFilter))
        }
        // c cycles persisted column presets
        Key::Character(ref c) if c.as_str() == "c" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::CycleColumnPreset))
        }
        // Enter toggles selected process details
        Key::Named(Named::Enter) => Some(Message::KeyPressed(KeyAction::ToggleDetails)),
        // t toggles process tree mode
        Key::Character(ref c) if c.as_str() == "t" && modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::ToggleTreeMode))
        }
        // F1-F5 for sorting columns
        Key::Named(Named::F1) => Some(Message::KeyPressed(KeyAction::SortColumn(SortField::Pid))),
        Key::Named(Named::F2) => Some(Message::KeyPressed(KeyAction::SortColumn(SortField::Name))),
        Key::Named(Named::F3) => Some(Message::KeyPressed(KeyAction::SortColumn(SortField::Cpu))),
        Key::Named(Named::F4) => Some(Message::KeyPressed(KeyAction::SortColumn(
            SortField::Memory,
        ))),
        Key::Named(Named::F5) => Some(Message::KeyPressed(KeyAction::SortColumn(
            SortField::Status,
        ))),
        // Tab to toggle sort direction
        Key::Named(Named::Tab) if modifiers.is_empty() => {
            Some(Message::KeyPressed(KeyAction::ToggleSortDirection))
        }
        _ => None,
    }
}
