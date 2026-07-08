import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: RustTopSettings

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            alertsSettings
                .tabItem {
                    Label("Alerts", systemImage: "exclamationmark.triangle")
                }

            panelsSettings
                .tabItem {
                    Label("Panels", systemImage: "rectangle.3.group")
                }

            menuBarSettings
                .tabItem {
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                }
        }
        .frame(width: 600, height: 520)
    }

    private var generalSettings: some View {
        Form {
            Section("Refresh") {
                HStack {
                    Slider(
                        value: refreshInterval,
                        in: RustTopSettings.refreshIntervalRange,
                        step: 1
                    )
                    .accessibilityLabel("Refresh interval")
                    .accessibilityValue("\(Int(settings.refreshIntervalSeconds)) seconds")
                    .accessibilityHint("Controls how often RustTop fetches a new snapshot.")

                    Text("\(Int(settings.refreshIntervalSeconds)) s")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                        .accessibilityHidden(true)
                }

                if settings.startupBehavior == .menuBarOnly,
                   settings.effectiveRefreshIntervalSeconds > settings.refreshIntervalSeconds {
                    Label(
                        "Menu bar only uses \(Int(settings.effectiveRefreshIntervalSeconds)) s minimum cadence",
                        systemImage: "leaf"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Menu bar only cadence")
                    .accessibilityValue("\(Int(settings.effectiveRefreshIntervalSeconds)) seconds minimum")
                }
            }

            Section("Helper") {
                HStack {
                    TextField("Automatic helper discovery", text: $settings.helperPathOverride)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Helper path override")
                        .accessibilityValue(settings.helperPathOverride.isEmpty ? "Automatic helper discovery" : settings.helperPathOverride)
                        .accessibilityHint("Optional path to the RustTop helper executable.")

                    Button {
                        chooseHelperPath()
                    } label: {
                        Label("Choose", systemImage: "folder")
                    }
                    .accessibilityLabel("Choose helper executable")
                    .accessibilityHint("Opens a file picker for the RustTop helper path.")
                }

                helperPathStatus

                if !settings.helperPathOverride.isEmpty {
                    Button {
                        settings.clearHelperPathOverride()
                    } label: {
                        Label("Clear Override", systemImage: "xmark.circle")
                    }
                    .accessibilityLabel("Clear helper override")
                    .accessibilityHint("Returns to automatic helper discovery.")
                }
            }

            Section("Startup") {
                Picker("Behavior", selection: $settings.startupBehavior) {
                    ForEach(RustTopSettings.StartupBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                .accessibilityLabel("Startup behavior")
                .accessibilityValue(settings.startupBehavior.title)
                .accessibilityHint("Chooses what RustTop opens when the app starts.")
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.dashboardTheme) {
                    ForEach(DashboardTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .accessibilityLabel("Dashboard theme")
                .accessibilityValue(settings.dashboardTheme.title)
                .accessibilityHint("Chooses whether RustTop follows the system appearance or uses a fixed light or dark appearance.")

                Picker("Accent", selection: $settings.dashboardAccent) {
                    ForEach(DashboardAccent.allCases) { accent in
                        Text(accent.title).tag(accent)
                    }
                }
                .accessibilityLabel("Dashboard accent")
                .accessibilityValue(settings.dashboardAccent.title)
                .accessibilityHint("Changes the accent used by native controls while preserving system contrast.")

                Picker("Dashboard Density", selection: $settings.dashboardDensity) {
                    ForEach(DashboardDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                .accessibilityLabel("Dashboard density")
                .accessibilityValue(settings.dashboardDensity.title)
                .accessibilityHint("Changes dashboard spacing and process table density.")
            }

        }
        .padding(20)
    }

    private var alertsSettings: some View {
        Form {
            Section("Native Thresholds") {
                thresholdRow(
                    title: "CPU warning",
                    value: nativeCPUWarningThreshold,
                    currentValue: settings.nativeCPUWarningThreshold
                )
                thresholdRow(
                    title: "CPU critical",
                    value: nativeCPUCriticalThreshold,
                    currentValue: settings.nativeCPUCriticalThreshold
                )
                thresholdRow(
                    title: "Memory warning",
                    value: nativeMemoryWarningThreshold,
                    currentValue: settings.nativeMemoryWarningThreshold
                )
                thresholdRow(
                    title: "Memory critical",
                    value: nativeMemoryCriticalThreshold,
                    currentValue: settings.nativeMemoryCriticalThreshold
                )

                HStack {
                    Slider(
                        value: nativeAlertMinimumActiveSeconds,
                        in: RustTopSettings.nativeAlertMinimumActiveSecondsRange,
                        step: 5
                    )
                    .accessibilityLabel("Native alert minimum active time")
                    .accessibilityValue("\(Int(settings.nativeAlertMinimumActiveSeconds)) seconds")

                    Text("\(Int(settings.nativeAlertMinimumActiveSeconds)) s")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }

            Section("Notifications") {
                Toggle("Notification Center alerts", isOn: $settings.alertNotificationsEnabled)
                    .accessibilityValue(settings.alertNotificationsEnabled ? "Enabled" : "Disabled")
                    .accessibilityHint("Delivers active RustTop alerts through Notification Center after the selected duration.")

                HStack {
                    Slider(
                        value: alertNotificationMinimumActiveSeconds,
                        in: RustTopSettings.alertNotificationMinimumActiveSecondsRange,
                        step: 5
                    )
                    .disabled(!settings.alertNotificationsEnabled)
                    .accessibilityLabel("Notify after active")
                    .accessibilityValue("\(Int(settings.alertNotificationMinimumActiveSeconds)) seconds")

                    Text("\(Int(settings.alertNotificationMinimumActiveSeconds)) s")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(20)
    }

    private var panelsSettings: some View {
        Form {
            Section("Visible Panels") {
                Toggle("Overview", isOn: $settings.showOverviewPanel)
                    .accessibilityValue(settings.showOverviewPanel ? "Visible" : "Hidden")
                    .accessibilityHint("Shows or hides the overview dashboard panel.")
                Toggle("Processes", isOn: $settings.showProcessesPanel)
                    .accessibilityValue(settings.showProcessesPanel ? "Visible" : "Hidden")
                    .accessibilityHint("Shows or hides the process dashboard panel.")
                Toggle("Storage", isOn: $settings.showStoragePanel)
                    .accessibilityValue(settings.showStoragePanel ? "Visible" : "Hidden")
                    .accessibilityHint("Shows or hides the storage dashboard panel.")
                Toggle("Sensors", isOn: $settings.showSensorsPanel)
                    .accessibilityValue(settings.showSensorsPanel ? "Visible" : "Hidden")
                    .accessibilityHint("Shows or hides the sensors dashboard panel.")
            }
        }
        .padding(20)
    }

    private var menuBarSettings: some View {
        Form {
            Section("Menu Bar Monitor") {
                Toggle("Show menu bar monitor", isOn: $settings.showMenuBarMonitor)
                    .accessibilityValue(settings.showMenuBarMonitor ? "Shown" : "Hidden")
                    .accessibilityHint("Shows or hides RustTop in the macOS menu bar.")

                Toggle("CPU", isOn: $settings.showMenuBarCPU)
                    .disabled(!settings.showMenuBarMonitor)
                    .accessibilityValue(menuBarModuleAccessibilityValue(settings.showMenuBarCPU))
                    .accessibilityHint("Shows or hides CPU usage in the menu bar monitor.")
                Toggle("Memory", isOn: $settings.showMenuBarMemory)
                    .disabled(!settings.showMenuBarMonitor)
                    .accessibilityValue(menuBarModuleAccessibilityValue(settings.showMenuBarMemory))
                    .accessibilityHint("Shows or hides memory usage in the menu bar monitor.")
                Toggle("Network", isOn: $settings.showMenuBarNetwork)
                    .disabled(!settings.showMenuBarMonitor)
                    .accessibilityValue(menuBarModuleAccessibilityValue(settings.showMenuBarNetwork))
                    .accessibilityHint("Shows or hides network throughput in the menu bar monitor.")
                Toggle("GPU / Temperature", isOn: $settings.showMenuBarGPUAndTemperature)
                    .disabled(!settings.showMenuBarMonitor)
                    .accessibilityValue(menuBarModuleAccessibilityValue(settings.showMenuBarGPUAndTemperature))
                    .accessibilityHint("Shows GPU utilization or temperature in the menu bar monitor when snapshot data is available.")
            }

            Section("Dock") {
                Toggle("Live Dock graph", isOn: $settings.showDockLiveGraph)
                    .accessibilityValue(settings.showDockLiveGraph ? "Shown" : "Hidden")
                    .accessibilityHint("Shows a compact CPU and memory trend in the Dock tile.")
            }
        }
        .padding(20)
    }

    private var refreshInterval: Binding<Double> {
        Binding {
            settings.refreshIntervalSeconds
        } set: { value in
            settings.setRefreshIntervalSeconds(value)
        }
    }

    private var alertNotificationMinimumActiveSeconds: Binding<Double> {
        Binding {
            settings.alertNotificationMinimumActiveSeconds
        } set: { value in
            settings.setAlertNotificationMinimumActiveSeconds(value)
        }
    }

    private var nativeCPUWarningThreshold: Binding<Double> {
        Binding {
            settings.nativeCPUWarningThreshold
        } set: { value in
            settings.setNativeCPUWarningThreshold(value)
        }
    }

    private var nativeCPUCriticalThreshold: Binding<Double> {
        Binding {
            settings.nativeCPUCriticalThreshold
        } set: { value in
            settings.setNativeCPUCriticalThreshold(value)
        }
    }

    private var nativeMemoryWarningThreshold: Binding<Double> {
        Binding {
            settings.nativeMemoryWarningThreshold
        } set: { value in
            settings.setNativeMemoryWarningThreshold(value)
        }
    }

    private var nativeMemoryCriticalThreshold: Binding<Double> {
        Binding {
            settings.nativeMemoryCriticalThreshold
        } set: { value in
            settings.setNativeMemoryCriticalThreshold(value)
        }
    }

    private var nativeAlertMinimumActiveSeconds: Binding<Double> {
        Binding {
            settings.nativeAlertMinimumActiveSeconds
        } set: { value in
            settings.setNativeAlertMinimumActiveSeconds(value)
        }
    }

    private func thresholdRow(
        title: String,
        value: Binding<Double>,
        currentValue: Double
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 116, alignment: .leading)

            Slider(
                value: value,
                in: RustTopSettings.nativeAlertThresholdRange,
                step: 1
            )
            .accessibilityLabel(title)
            .accessibilityValue("\(Int(currentValue)) percent")

            Text("\(Int(currentValue))%")
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var helperPathStatus: some View {
        switch settings.helperPathState {
        case .empty:
            Label("Using automatic helper discovery", systemImage: "sparkle.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Helper status")
                .accessibilityValue("Using automatic helper discovery")
        case .ready:
            Label("Helper override is executable", systemImage: "checkmark.circle")
                .foregroundStyle(Color.tahoeMint)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Helper status")
                .accessibilityValue("Helper override is executable")
        case .missing:
            Label("Helper path was not found", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.tahoeAmber)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Helper status")
                .accessibilityValue("Helper path was not found")
        case .notExecutable:
            Label("Helper path is not executable", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.tahoeAmber)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Helper status")
                .accessibilityValue("Helper path is not executable")
        }
    }

    private func menuBarModuleAccessibilityValue(_ isVisible: Bool) -> String {
        guard settings.showMenuBarMonitor else { return "Disabled because the menu bar monitor is hidden" }
        return isVisible ? "Shown" : "Hidden"
    }

    private func chooseHelperPath() {
        let panel = NSOpenPanel()
        panel.title = "Choose RustTop Helper"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            settings.helperPathOverride = url.path
        }
    }
}
