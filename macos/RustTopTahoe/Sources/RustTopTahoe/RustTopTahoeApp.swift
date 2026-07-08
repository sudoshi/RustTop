import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct RustTopTahoeApp: App {
    @StateObject private var settings: RustTopSettings
    @StateObject private var model: DashboardModel

    init() {
        let settings = RustTopSettings()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: DashboardModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup("RustTop Tahoe", id: RustTopTahoeWindow.main.rawValue) {
            MainWindowContent(model: model, settings: settings)
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .saveItem) {
                Divider()

                Button("Export JSON Snapshot...") {
                    presentJSONExportPanel()
                }
                .disabled(model.isWritingArtifact)

                Button("Export CSV Snapshot...") {
                    presentCSVExportPanel()
                }
                .disabled(model.isWritingArtifact)

                Button("Write Incident Bundle...") {
                    presentIncidentBundlePanel()
                }
                .disabled(model.isWritingArtifact)
            }

            CommandMenu("Dashboard") {
                Button("Show Overview") {
                    model.selectedSection = .overview
                }
                .keyboardShortcut("1", modifiers: [.command])
                .disabled(!model.visibleSections.contains(.overview))

                Button("Show Processes") {
                    model.selectedSection = .processes
                }
                .keyboardShortcut("2", modifiers: [.command])
                .disabled(!model.visibleSections.contains(.processes))

                Button("Show Storage") {
                    model.selectedSection = .storage
                }
                .keyboardShortcut("3", modifiers: [.command])
                .disabled(!model.visibleSections.contains(.storage))

                Button("Show Sensors") {
                    model.selectedSection = .sensors
                }
                .keyboardShortcut("4", modifiers: [.command])
                .disabled(!model.visibleSections.contains(.sensors))

                Button("Show Services") {
                    model.selectedSection = .services
                }
                .keyboardShortcut("5", modifiers: [.command])
                .disabled(!model.visibleSections.contains(.services))

                Divider()

                Button("Refresh Snapshot") {
                    Task { await model.refreshNow() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(model.isPaused ? "Resume Live Updates" : "Pause Live Updates") {
                    model.isPaused.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command])

                Divider()

                Button(model.copyCommandTitle) {
                    model.copyCurrentSelectionToPasteboard()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.canCopyCurrentSelection)

                Button("Terminate Selected Process...") {
                    model.requestTerminateSelectedProcess()
                }
                .disabled(model.selectedProcess == nil)
            }
        }

        Settings {
            SettingsView(settings: settings)
                .preferredColorScheme(settings.preferredColorScheme)
                .tint(settings.accentColor)
        }

        MenuBarExtra(isInserted: menuBarMonitorIsInserted) {
            MenuBarMonitorView(model: model, settings: settings)
                .tint(settings.accentColor)
        } label: {
            MenuBarMonitorLabel(
                metrics: MenuBarLabelMetrics(snapshot: model.snapshot, activeAlerts: model.activeAlerts),
                isLive: model.isLive,
                settings: settings
            )
        }
        .menuBarExtraStyle(.menu)
    }

    @MainActor
    private func presentJSONExportPanel() {
        let panel = snapshotSavePanel(
            title: "Export JSON Snapshot",
            defaultName: timestampedFilename(extension: "json"),
            contentType: .json
        )

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.writeJSONSnapshot(to: normalizedDestinationURL(url, fileExtension: "json")) }
    }

    @MainActor
    private func presentCSVExportPanel() {
        let panel = snapshotSavePanel(
            title: "Export CSV Snapshot",
            defaultName: timestampedFilename(extension: "csv"),
            contentType: UTType(filenameExtension: "csv")
        )

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.writeCSVSnapshot(to: normalizedDestinationURL(url, fileExtension: "csv")) }
    }

    @MainActor
    private func presentIncidentBundlePanel() {
        let panel = NSOpenPanel()
        panel.title = "Write Incident Bundle"
        panel.message = "Choose a folder for the RustTop incident bundle."
        panel.prompt = "Write Bundle"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.writeIncidentBundle(to: url) }
    }

    private func snapshotSavePanel(
        title: String,
        defaultName: String,
        contentType: UTType?
    ) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.canSelectHiddenExtension = true

        if let contentType {
            panel.allowedContentTypes = [contentType]
        }

        return panel
    }

    private func timestampedFilename(extension fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "rusttop-snapshot-\(formatter.string(from: Date())).\(fileExtension)"
    }

    private func normalizedDestinationURL(_ url: URL, fileExtension: String) -> URL {
        guard url.pathExtension.isEmpty else { return url }
        return url.appendingPathExtension(fileExtension)
    }

    private var menuBarMonitorIsInserted: Binding<Bool> {
        Binding {
            settings.showMenuBarMonitor
        } set: { isInserted in
            guard settings.showMenuBarMonitor != isInserted else { return }
            settings.showMenuBarMonitor = isInserted
        }
    }
}

enum RustTopTahoeWindow: String {
    case main
}

private struct MainWindowContent: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var settings: RustTopSettings
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var appliedStartupBehavior = false

    var body: some View {
        DashboardView(model: model, settings: settings)
            .frame(minWidth: 980, minHeight: 680)
            .preferredColorScheme(settings.preferredColorScheme)
            .tint(settings.accentColor)
            .task {
                model.start()
            }
            .onAppear {
                applyStartupBehaviorIfNeeded()
            }
            .onDisappear {
                settings.recordMainWindowVisibility(false)
            }
    }

    private func applyStartupBehaviorIfNeeded() {
        guard !appliedStartupBehavior else { return }
        appliedStartupBehavior = true

        guard !settings.shouldOpenMainWindowAtLaunch else {
            settings.recordMainWindowVisibility(true)
            return
        }

        settings.recordMainWindowVisibility(false)
        DispatchQueue.main.async {
            dismissWindow(id: RustTopTahoeWindow.main.rawValue)
        }
    }
}

private extension RustTopSettings {
    var preferredColorScheme: ColorScheme? {
        switch dashboardTheme {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var accentColor: Color {
        switch dashboardAccent {
        case .system:
            return .accentColor
        case .blue:
            return .tahoeBlue
        case .mint:
            return .tahoeMint
        case .violet:
            return .tahoeViolet
        case .rose:
            return .tahoeRose
        }
    }
}
