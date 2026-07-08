import AppKit
import SwiftUI

struct MenuBarMonitorView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var settings: RustTopSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(model.isLive ? "Live" : "Preview", systemImage: model.isLive ? "dot.radiowaves.left.and.right" : "gauge")
                    .foregroundStyle(model.isLive ? Color.tahoeMint : Color.tahoeAmber)
                Spacer()
                Text("\(Int(settings.refreshIntervalSeconds)) s")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("RustTop status")
            .accessibilityValue("\(model.isLive ? "Live" : "Preview"), refresh interval \(Int(settings.refreshIntervalSeconds)) seconds")

            Divider()

            if settings.showMenuBarCPU {
                MenuBarMetricRow(
                    title: "CPU",
                    systemImage: "cpu",
                    value: model.snapshot.cpuUsagePercent.menuPercentString,
                    detail: "\(model.snapshot.processCount) processes",
                    tint: usageColor(model.snapshot.cpuUsagePercent)
                )
            }

            if settings.showMenuBarMemory {
                MenuBarMetricRow(
                    title: "Memory",
                    systemImage: "memorychip",
                    value: model.snapshot.memory.usagePercent.menuPercentString,
                    detail: "\(model.snapshot.memory.used.menuByteString) used",
                    tint: usageColor(model.snapshot.memory.usagePercent)
                )
            }

            if settings.showMenuBarNetwork {
                MenuBarMetricRow(
                    title: "Network",
                    systemImage: "network",
                    value: model.snapshot.network.totalRxRate.menuRateString,
                    detail: "\(model.snapshot.network.totalTxRate.menuRateString) out",
                    tint: .tahoeMint
                )
            }

            if settings.showMenuBarGPUAndTemperature, let thermalSummary {
                MenuBarMetricRow(
                    title: thermalSummary.title,
                    systemImage: thermalSummary.systemImage,
                    value: thermalSummary.value,
                    detail: thermalSummary.detail,
                    tint: thermalSummary.tint
                )
            }

            if !model.activeAlerts.isEmpty {
                MenuBarMetricRow(
                    title: "Alerts",
                    systemImage: "exclamationmark.triangle",
                    value: "\(model.activeAlerts.count)",
                    detail: model.activeAlerts.first?.label ?? "Needs attention",
                    tint: model.activeAlerts.contains { $0.severity == .critical } ? .tahoeRose : .tahoeAmber
                )
            }

            if !hasRenderedMetricModule {
                Label("No menu bar modules active", systemImage: "eye.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("No menu bar modules active")
                    .accessibilityHint("Enable modules in Settings to show live menu bar metrics.")
            }

            if let lastError = model.lastError {
                Divider()
                Label(lastError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.tahoeAmber)
                    .lineLimit(3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Snapshot error")
                    .accessibilityValue(lastError)
            }

            Divider()

            Button {
                openRustTop()
            } label: {
                Label("Open RustTop Tahoe", systemImage: "macwindow")
            }
            .accessibilityLabel("Open RustTop Tahoe")
            .accessibilityHint("Opens the main RustTop window.")

            Button {
                model.isPaused.toggle()
            } label: {
                Label(model.isPaused ? "Resume Live Updates" : "Pause Live Updates", systemImage: model.isPaused ? "play.fill" : "pause.fill")
            }
            .accessibilityLabel(model.isPaused ? "Resume live updates" : "Pause live updates")
            .accessibilityValue(model.isPaused ? "Paused" : "Running")
            .accessibilityHint(model.isPaused ? "Restarts automatic snapshot refreshes." : "Stops automatic snapshot refreshes until resumed.")

            Button {
                Task { await model.refreshNow() }
            } label: {
                Label("Refresh Snapshot", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)
            .accessibilityLabel("Refresh snapshot")
            .accessibilityValue(model.isRefreshing ? "Refreshing" : "Ready")
            .accessibilityHint("Fetches a new RustTop system snapshot.")

            SettingsLink {
                Label("Settings", systemImage: "gear")
            }
            .accessibilityLabel("Open Settings")
            .accessibilityHint("Opens RustTop settings.")

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit RustTop Tahoe", systemImage: "power")
            }
            .accessibilityLabel("Quit RustTop Tahoe")
        }
        .padding(12)
        .frame(width: 280)
        .task {
            model.start()
        }
    }

    private func openRustTop() {
        settings.recordMainWindowVisibility(true)
        openWindow(id: RustTopTahoeWindow.main.rawValue)
        NSApplication.shared.activate()
    }

    private var thermalSummary: MenuBarThermalSummary? {
        MenuBarThermalSummary(snapshot: model.snapshot)
    }

    private var hasRenderedMetricModule: Bool {
        settings.showMenuBarCPU
            || settings.showMenuBarMemory
            || settings.showMenuBarNetwork
            || (settings.showMenuBarGPUAndTemperature && thermalSummary != nil)
            || !model.activeAlerts.isEmpty
    }
}

struct MenuBarLabelMetrics {
    let cpuUsagePercent: Double
    let memoryUsagePercent: Double
    let networkReceiveRate: UInt64
    let thermalSummary: MenuBarThermalSummary?
    let activeAlertCount: Int

    init(snapshot: RustTopSnapshot, activeAlerts: [AlertSnapshot]) {
        cpuUsagePercent = snapshot.cpuUsagePercent
        memoryUsagePercent = snapshot.memory.usagePercent
        networkReceiveRate = snapshot.network.totalRxRate
        thermalSummary = MenuBarThermalSummary(snapshot: snapshot)
        activeAlertCount = activeAlerts.count
    }
}

struct MenuBarMonitorLabel: View {
    let metrics: MenuBarLabelMetrics
    let isLive: Bool
    @ObservedObject var settings: RustTopSettings

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isLive ? "dot.radiowaves.left.and.right" : "gauge")
                .symbolRenderingMode(.hierarchical)

            if settings.showMenuBarCPU {
                Text("CPU \(metrics.cpuUsagePercent.menuPercentString)")
            }

            if settings.showMenuBarMemory {
                Text("MEM \(metrics.memoryUsagePercent.menuPercentString)")
            }

            if settings.showMenuBarNetwork {
                Text(metrics.networkReceiveRate.menuRateString)
            }

            if settings.showMenuBarGPUAndTemperature, let thermalSummary = metrics.thermalSummary {
                Text("\(thermalSummary.shortLabel) \(thermalSummary.value)")
            }

            if metrics.activeAlertCount > 0 {
                Text("ALRT \(metrics.activeAlertCount)")
            }

            if !hasRenderedMetricModule {
                Text("RustTop")
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("RustTop menu bar monitor")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [isLive ? "Live" : "Preview"]

        if settings.showMenuBarCPU {
            parts.append("CPU \(metrics.cpuUsagePercent.menuPercentString)")
        }

        if settings.showMenuBarMemory {
            parts.append("memory \(metrics.memoryUsagePercent.menuPercentString)")
        }

        if settings.showMenuBarNetwork {
            parts.append("network receive \(metrics.networkReceiveRate.menuRateString)")
        }

        if settings.showMenuBarGPUAndTemperature, let thermalSummary = metrics.thermalSummary {
            parts.append("\(thermalSummary.title) \(thermalSummary.value)")
        }

        if metrics.activeAlertCount > 0 {
            parts.append("\(metrics.activeAlertCount) active alerts")
        }

        if parts.count == 1 {
            parts.append("no metrics selected")
        }

        return parts.joined(separator: ", ")
    }

    private var hasRenderedMetricModule: Bool {
        settings.showMenuBarCPU
            || settings.showMenuBarMemory
            || settings.showMenuBarNetwork
            || (settings.showMenuBarGPUAndTemperature && metrics.thermalSummary != nil)
            || metrics.activeAlertCount > 0
    }
}

private struct MenuBarMetricRow: View {
    let title: String
    let systemImage: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value), \(detail)")
    }
}

struct MenuBarThermalSummary {
    let title: String
    let shortLabel: String
    let systemImage: String
    let value: String
    let detail: String
    let tint: Color

    init?(snapshot: RustTopSnapshot) {
        if let gpu = snapshot.gpus.first {
            title = "GPU"
            shortLabel = "GPU"
            systemImage = "gpu"

            if let temperature = gpu.temperature {
                value = "\(temperature.oneDecimal) C"
                detail = "\(gpu.usagePercent.menuPercentString) util"
                tint = thermalColor(temperature)
            } else {
                value = gpu.usagePercent.menuPercentString
                detail = "\(gpu.vramUsed.menuByteString) VRAM"
                tint = usageColor(gpu.usagePercent)
            }
            return
        }

        if let sensor = snapshot.sensors.first(where: { $0.temperature != nil }),
           let temperature = sensor.temperature {
            title = "Temperature"
            shortLabel = "TEMP"
            systemImage = "thermometer.medium"
            value = "\(temperature.oneDecimal) C"
            detail = sensor.label
            tint = thermalColor(temperature)
            return
        }

        return nil
    }
}

private func usageColor(_ value: Double) -> Color {
    switch value {
    case 0..<55: .tahoeMint
    case 55..<82: .tahoeAmber
    default: .tahoeRose
    }
}

private func thermalColor(_ value: Double) -> Color {
    switch value {
    case 0..<65: .tahoeMint
    case 65..<85: .tahoeAmber
    default: .tahoeRose
    }
}

private extension Double {
    var menuPercentString: String {
        "\(Int(rounded()))%"
    }

    var oneDecimal: String {
        formatted(.number.precision(.fractionLength(1)))
    }
}

private extension UInt64 {
    var menuByteString: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .memory)
    }

    var menuRateString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = self >= 1_048_576 ? [.useMB] : [.useKB]
        formatter.includesUnit = true
        formatter.includesCount = true
        return "\(formatter.string(fromByteCount: Int64(self)))/s"
    }
}
