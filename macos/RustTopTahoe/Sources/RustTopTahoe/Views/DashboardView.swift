import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var settings: RustTopSettings

    var body: some View {
        NavigationSplitView {
            SidebarView(
                sections: model.visibleSections,
                selection: selectedSectionBinding
            )
        } detail: {
            ZStack {
                TahoeBackdrop()
                selectedContent
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    StatusPill(isLive: model.isLive, isRefreshing: model.isRefreshing)

                    Button {
                        model.isPaused.toggle()
                    } label: {
                        Label(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(model.isPaused ? "Resume live updates" : "Pause live updates")
                    .accessibilityValue(model.isPaused ? "Paused" : "Running")
                    .accessibilityHint(model.isPaused ? "Restarts automatic snapshot refreshes." : "Stops automatic snapshot refreshes until resumed.")

                    Button {
                        Task { await model.refreshNow() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Refresh snapshot")
                    .accessibilityValue(model.isRefreshing ? "Refreshing" : "Ready")
                    .accessibilityHint("Fetches a new RustTop system snapshot.")
                }
            }
        }
        .navigationTitle("RustTop")
        .searchable(
            text: processSearchTextBinding,
            placement: .toolbar,
            prompt: "Search processes, disks, sensors"
        )
        .onSubmit(of: .search) {
            navigateToBestSearchMatch()
        }
        .confirmationDialog(
            "Terminate Process",
            isPresented: processActionConfirmationIsPresented,
            presenting: model.pendingProcessAction
        ) { _ in
            Button("Send TERM", role: .destructive) {
                model.confirmPendingProcessAction()
            }

            Button("Cancel", role: .cancel) {
                model.cancelPendingProcessAction()
            }
        } message: { request in
            Text("Send a graceful TERM signal to \(request.process.name) (PID \(request.process.pid))? The process may prompt, save state, or refuse to exit.")
        }
        .sheet(item: $model.presentedAlert) { alert in
            AlertDetailView(
                alert: alert,
                notificationsEnabled: settings.alertNotificationsEnabled,
                notificationStatus: model.alertNotificationStatus
            )
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch model.resolvedSelectedSection {
        case .overview:
            OverviewView(model: model, density: settings.dashboardDensity)
        case .processes:
            ProcessesView(model: model, density: settings.dashboardDensity)
        case .storage:
            StorageView(snapshot: model.snapshot, density: settings.dashboardDensity, searchText: model.processSearchText)
        case .sensors:
            SensorsView(snapshot: model.snapshot, density: settings.dashboardDensity, searchText: model.processSearchText)
        case .services:
            ServicesView(snapshot: model.snapshot, density: settings.dashboardDensity, searchText: model.processSearchText)
        }
    }

    private func navigateToBestSearchMatch() {
        let query = DashboardSearchQuery(model.processSearchText)
        guard !query.isEmpty else { return }

        if let selectedSection = model.selectedSection,
           model.visibleSections.contains(selectedSection),
           model.snapshot.hasSearchMatch(in: selectedSection, query: query) {
            return
        }

        if let section = model.snapshot.bestSearchSection(for: query, visibleSections: model.visibleSections) {
            model.selectedSection = section
        }
    }

    private var selectedSectionBinding: Binding<DashboardSection?> {
        Binding {
            model.selectedSection
        } set: { section in
            guard model.selectedSection != section else { return }
            model.selectedSection = section
        }
    }

    private var processSearchTextBinding: Binding<String> {
        Binding {
            model.processSearchText
        } set: { text in
            guard model.processSearchText != text else { return }
            model.processSearchText = text
        }
    }

    private var processActionConfirmationIsPresented: Binding<Bool> {
        Binding {
            model.pendingProcessAction != nil
        } set: { isPresented in
            guard !isPresented, model.pendingProcessAction != nil else { return }
            model.cancelPendingProcessAction()
        }
    }
}

private struct DashboardSearchQuery {
    let text: String

    init(_ rawValue: String) {
        text = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        text.isEmpty
    }

    var preferredSections: [DashboardSection] {
        var sections: [DashboardSection] = []

        if containsAny(["process", "processes", "pid"]) {
            sections.append(.processes)
        }

        if containsAny(["disk", "disks", "drive", "storage", "volume", "filesystem", "mount"]) {
            sections.append(.storage)
        }

        if containsAny(["gpu", "graphics", "sensor", "sensors", "thermal", "temperature", "battery", "batteries", "power"]) {
            sections.append(.sensors)
        }

        if containsAny(["launchd", "service", "services", "agent", "agents", "daemon", "daemons", "plist"]) {
            sections.append(.services)
        }

        return sections
    }

    func matches(_ values: String...) -> Bool {
        matches(values)
    }

    func matches(_ values: [String]) -> Bool {
        guard !isEmpty else { return true }
        return values.contains { $0.localizedCaseInsensitiveContains(text) }
    }

    private func containsAny(_ keywords: [String]) -> Bool {
        let normalizedText = text.lowercased()
        return keywords.contains { normalizedText.contains($0) }
    }
}

private struct DashboardDensityMetrics {
    let pagePadding: CGFloat
    let panelPadding: CGFloat
    let sectionSpacing: CGFloat
    let cardSpacing: CGFloat
    let rowSpacing: CGFloat
    let tableMinHeight: CGFloat
}

private extension DashboardDensity {
    var metrics: DashboardDensityMetrics {
        switch self {
        case .comfortable:
            DashboardDensityMetrics(
                pagePadding: 28,
                panelPadding: 20,
                sectionSpacing: 20,
                cardSpacing: 18,
                rowSpacing: 12,
                tableMinHeight: 500
            )
        case .balanced:
            DashboardDensityMetrics(
                pagePadding: 24,
                panelPadding: 18,
                sectionSpacing: 18,
                cardSpacing: 16,
                rowSpacing: 10,
                tableMinHeight: 460
            )
        case .compact:
            DashboardDensityMetrics(
                pagePadding: 16,
                panelPadding: 14,
                sectionSpacing: 12,
                cardSpacing: 12,
                rowSpacing: 6,
                tableMinHeight: 380
            )
        }
    }

    var controlSize: ControlSize {
        switch self {
        case .comfortable:
            return .large
        case .balanced:
            return .regular
        case .compact:
            return .small
        }
    }
}

private struct SidebarView: View {
    let sections: [DashboardSection]
    @Binding var selection: DashboardSection?

    var body: some View {
        List(sections, selection: $selection) { section in
            Label(section.title, systemImage: section.symbolName)
                .tag(section)
                .accessibilityLabel(section.title)
                .accessibilityValue(selection == section ? "Selected" : "Not selected")
                .accessibilityHint("Shows the \(section.title.lowercased()) dashboard.")
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
    }
}

private struct StatusPill: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let isLive: Bool
    let isRefreshing: Bool

    var body: some View {
        Label {
            Text(isRefreshing ? "Syncing" : (isLive ? "Live" : "Preview"))
        } icon: {
            Image(systemName: isLive ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle")
                .symbolEffect(.pulse, isActive: isRefreshing && !accessibilityReduceMotion)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isLive ? Color.tahoeMint : Color.tahoeAmber)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Snapshot status")
        .accessibilityValue(isRefreshing ? "Syncing" : (isLive ? "Live" : "Preview"))
        .accessibilityHint(isLive ? "Live data is available." : "Showing preview data or the latest cached snapshot.")
    }
}

private struct OverviewView: View {
    @ObservedObject var model: DashboardModel
    let density: DashboardDensity

    private var snapshot: RustTopSnapshot { model.snapshot }
    private var activeAlerts: [AlertSnapshot] { model.activeAlerts }
    private var metrics: DashboardDensityMetrics { density.metrics }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                HeaderPanel(
                    snapshot: snapshot,
                    lastError: model.lastError,
                    artifactStatus: model.artifactStatus
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: metrics.cardSpacing)], spacing: metrics.cardSpacing) {
                    MetricCard(
                        title: "CPU",
                        symbol: "cpu",
                        value: snapshot.cpuUsagePercent.percentString,
                        subtitle: "\(snapshot.processCount) processes",
                        percent: snapshot.cpuUsagePercent,
                        tint: .tahoeBlue
                    )

                    MetricCard(
                        title: "Memory",
                        symbol: "memorychip",
                        value: snapshot.memory.displayPressurePercent.percentString,
                        subtitle: snapshot.memory.pressureSubtitle,
                        percent: snapshot.memory.displayPressurePercent,
                        tint: .tahoeViolet
                    )

                    MetricCard(
                        title: "Network",
                        symbol: "network",
                        value: snapshot.network.totalRxRate.rateString,
                        subtitle: "\(snapshot.network.totalTxRate.rateString) out",
                        percent: min(100, Double(snapshot.network.totalRxRate) / 80_000),
                        tint: .tahoeMint
                    )

                    MetricCard(
                        title: "Alerts",
                        symbol: activeAlerts.isEmpty ? "checkmark.shield" : "exclamationmark.triangle",
                        value: "\(activeAlerts.count)",
                        subtitle: activeAlerts.isEmpty ? "No active alerts" : "Needs attention",
                        percent: activeAlerts.isEmpty ? 4 : 100,
                        tint: activeAlerts.isEmpty ? .tahoeMint : .tahoeRose
                    )
                }

                if !activeAlerts.isEmpty {
                    ActiveAlertsPanel(model: model, density: density)
                }

                HStack(alignment: .top, spacing: metrics.cardSpacing) {
                    GlassPanel(tintColor: .controlAccentColor.withAlphaComponent(0.08)) {
                        VStack(alignment: .leading, spacing: metrics.rowSpacing + 4) {
                            PanelHeader(title: "Pressure", symbol: "waveform.path.ecg")
                            Sparkline(values: model.samples.map(\.cpu), tint: .tahoeBlue)
                                .frame(height: 116)
                                .accessibilityLabel("CPU pressure trend")
                                .accessibilityHint("Shows recent CPU usage samples.")
                            HStack {
                                MiniLegend(label: "CPU", color: .tahoeBlue, value: snapshot.cpuUsagePercent.percentString)
                                MiniLegend(label: "Memory", color: .tahoeViolet, value: snapshot.memory.displayPressurePercent.percentString)
                                Spacer()
                            }
                            MemoryBreakdownGrid(memory: snapshot.memory)
                        }
                        .padding(metrics.panelPadding)
                    }

                    GlassPanel(tintColor: .systemGreen.withAlphaComponent(0.07)) {
                        VStack(alignment: .leading, spacing: metrics.rowSpacing + 4) {
                            PanelHeader(title: "Top Processes", symbol: "list.bullet.rectangle")
                            ProcessRows(processes: Array(snapshot.topProcesses.prefix(6)), density: density)
                        }
                        .padding(metrics.panelPadding)
                    }
                }
            }
            .padding(metrics.pagePadding)
        }
    }
}

private struct HeaderPanel: View {
    let snapshot: RustTopSnapshot
    let lastError: String?
    let artifactStatus: DashboardArtifactStatus?

    var body: some View {
        GlassPanel(tintColor: .controlAccentColor.withAlphaComponent(0.06)) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.thinMaterial)
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 34, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.tahoeBlue)
                }
                .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.hostname)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                    Text("\(snapshot.osName) \(snapshot.osVersion) | kernel \(snapshot.kernelVersion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let lastError {
                        Text(lastError)
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundStyle(Color.tahoeAmber)
                    } else if let artifactStatus {
                        Label {
                            Text(artifactStatus.message)
                                .lineLimit(2)
                        } icon: {
                            Image(systemName: artifactStatus.symbolName)
                        }
                        .font(.caption)
                        .foregroundStyle(artifactStatus.tintColor)
                        .accessibilityLabel("Artifact status")
                        .accessibilityValue(artifactStatus.accessibilityValue)
                    } else {
                        Text("Uptime \(snapshot.uptimeSeconds.durationString) | captured \(snapshot.captureDate.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("System summary")
        .accessibilityValue("\(snapshot.hostname), \(snapshot.osName) \(snapshot.osVersion), uptime \(snapshot.uptimeSeconds.durationString)")
        .accessibilityHint(headerAccessibilityHint)
    }

    private var headerAccessibilityHint: String {
        if lastError != nil {
            return "Shows host identity and the latest snapshot error."
        }

        if artifactStatus != nil {
            return "Shows host identity and the latest export or incident bundle status."
        }

        return "Shows host identity and the latest capture time."
    }
}

private struct ActiveAlertsPanel: View {
    @ObservedObject var model: DashboardModel
    let density: DashboardDensity

    private var metrics: DashboardDensityMetrics { density.metrics }

    var body: some View {
        GlassPanel(tintColor: .systemRed.withAlphaComponent(0.07)) {
            VStack(alignment: .leading, spacing: metrics.rowSpacing + 4) {
                HStack {
                    PanelHeader(title: "Active Alerts", symbol: "exclamationmark.triangle")
                    Spacer()
                    Text("\(model.activeAlerts.count)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.tahoeRose)
                }

                ForEach(model.activeAlerts) { alert in
                    AlertSummaryRow(alert: alert) {
                        model.presentAlertDetails(alert)
                    }
                }

                if let alertNotificationStatus = model.alertNotificationStatus {
                    Label(alertNotificationStatus.message, systemImage: alertNotificationStatus.symbolName)
                        .font(.caption)
                        .foregroundStyle(alertNotificationStatus.tintColor)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Alert notification status")
                        .accessibilityValue(alertNotificationStatus.message)
                }
            }
            .padding(metrics.panelPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active alerts")
    }
}

private struct AlertSummaryRow: View {
    let alert: AlertSnapshot
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: alert.severity.symbolName)
                    .foregroundStyle(alert.severity.tintColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.label)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(alertSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(alert.label)
        .accessibilityValue(alert.accessibilitySummary)
        .accessibilityHint("Opens alert details.")
    }

    private var alertSummaryText: String {
        "\(alert.displayValue) over \(alert.displayThreshold) for \(alert.activeSeconds.durationString)"
    }
}

private struct AlertDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let alert: AlertSnapshot
    let notificationsEnabled: Bool
    let notificationStatus: AlertNotificationStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: alert.severity.symbolName)
                    .font(.title2)
                    .foregroundStyle(alert.severity.tintColor)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.label)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                    Text(alert.severity.displayTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(alert.severity.tintColor)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close alert details")
            }

            Divider()

            VStack(spacing: 10) {
                MetricLine(label: "Current", value: alert.displayValue)
                MetricLine(label: "Threshold", value: alert.displayThreshold)
                MetricLine(label: "Active", value: alert.activeSeconds.durationString)
                MetricLine(label: "Notification", value: notificationsEnabled ? "Enabled" : "Disabled")
            }

            if let notificationStatus {
                Label(notificationStatus.message, systemImage: notificationStatus.symbolName)
                    .font(.caption)
                    .foregroundStyle(notificationStatus.tintColor)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Alert notification status")
                    .accessibilityValue(notificationStatus.message)
            }
        }
        .padding(24)
        .frame(width: 420)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Alert details")
        .accessibilityValue(alert.accessibilitySummary)
    }
}

private struct MetricCard: View {
    let title: String
    let symbol: String
    let value: String
    let subtitle: String
    let percent: Double
    let tint: Color

    var body: some View {
        GlassPanel(tintColor: NSColor(tint).withAlphaComponent(0.08)) {
            HStack(spacing: 16) {
                PressureRing(percent: percent, tint: tint)
                    .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: symbol)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) metric")
        .accessibilityValue("\(value), \(subtitle)")
        .accessibilityHint("Current \(title.lowercased()) dashboard summary.")
    }
}

private struct PressureRing: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    let percent: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: colorSchemeContrast == .increased ? 9 : 8)
            Circle()
                .trim(from: 0, to: min(max(percent / 100, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint, .tahoeAmber, .tahoeRose],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int(percent.rounded()))")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .accessibilityHidden(true)
    }

    private var trackColor: Color {
        let base: Color = colorScheme == .dark ? .white : .black
        return base.opacity(colorSchemeContrast == .increased ? 0.24 : 0.12)
    }
}

private struct PanelHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .symbolRenderingMode(.hierarchical)
    }
}

private struct Sparkline: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(values.max() ?? 1, 1)
            let minValue = min(values.min() ?? 0, maxValue)
            let range = max(maxValue - minValue, 1)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(colorSchemeContrast == .increased ? 0.09 : 0.055))

                Path { path in
                    guard values.count > 1 else { return }
                    for index in values.indices {
                        let x = proxy.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let normalized = (values[index] - minValue) / range
                        let y = proxy.size.height * CGFloat(1 - normalized)
                        let point = CGPoint(x: x, y: y)
                        if index == values.startIndex {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: colorSchemeContrast == .increased ? 4 : 3, lineCap: .round, lineJoin: .round))
                .shadow(color: tint.opacity(colorSchemeContrast == .increased ? 0.18 : 0.36), radius: colorSchemeContrast == .increased ? 4 : 12, x: 0, y: 0)
                .padding(12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let latest = values.last else { return "No samples available" }
        let minValue = values.min() ?? latest
        let maxValue = values.max() ?? latest
        return "Latest \(latest.percentString), range \(minValue.percentString) to \(maxValue.percentString)"
    }
}

private struct MiniLegend: View {
    let label: String
    let color: Color
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private struct MemoryBreakdownGrid: View {
    let memory: MemorySnapshot

    var body: some View {
        if memory.hasBreakdown {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                if let appMemory = memory.appMemory {
                    StatBlock(title: "App", value: appMemory.byteString)
                }
                if let wiredMemory = memory.wiredMemory {
                    StatBlock(title: "Wired", value: wiredMemory.byteString)
                }
                if let compressedMemory = memory.compressedMemory {
                    StatBlock(title: "Compressed", value: compressedMemory.byteString)
                }
                if let fileCache = memory.fileCache {
                    StatBlock(title: "Cache", value: fileCache.byteString)
                }
            }
        }
    }
}

private struct ProcessesView: View {
    @ObservedObject var model: DashboardModel
    let density: DashboardDensity

    private var snapshot: RustTopSnapshot { model.snapshot }
    private var metrics: DashboardDensityMetrics { density.metrics }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: metrics.cardSpacing) {
                processPanel
                    .frame(minWidth: 480)
                ProcessInspector(model: model, density: density)
                    .frame(width: 286)
            }

            VStack(spacing: metrics.cardSpacing) {
                processPanel
                ProcessInspector(model: model, density: density)
            }
        }
        .padding(metrics.pagePadding)
    }

    private var processPanel: some View {
        GlassPanel(tintColor: .controlAccentColor.withAlphaComponent(0.07)) {
            VStack(alignment: .leading, spacing: metrics.rowSpacing + 4) {
                ProcessChrome(model: model)

                ZStack {
                    Table(model.visibleProcesses, selection: $model.selectedProcessID) {
                        TableColumn("PID") { process in
                            Text("\(process.pid)")
                                .monospacedDigit()
                                .accessibilityLabel("PID")
                                .accessibilityValue("\(process.pid)")
                        }
                        .width(70)

                        TableColumn("Name") { process in
                            Text(process.name)
                                .lineLimit(1)
                                .accessibilityLabel("Process name")
                                .accessibilityValue(process.name)
                        }

                        TableColumn("CPU") { process in
                            Text(process.cpuUsage.percentString)
                                .monospacedDigit()
                                .foregroundStyle(usageColor(process.cpuUsage))
                                .accessibilityLabel("CPU")
                                .accessibilityValue(process.cpuUsage.percentString)
                        }
                        .width(80)

                        TableColumn("Memory") { process in
                            Text(process.memory.byteString)
                                .monospacedDigit()
                                .accessibilityLabel("Memory")
                                .accessibilityValue(process.memory.byteString)
                        }
                        .width(110)

                        TableColumn("Status") { process in
                            Text(process.status)
                                .accessibilityLabel("Status")
                                .accessibilityValue(process.status)
                        }
                        .width(90)
                    }
                    .controlSize(density.controlSize)
                    .frame(minHeight: metrics.tableMinHeight)
                    .accessibilityLabel("Process table")
                    .accessibilityValue("\(model.visibleProcesses.count) of \(model.snapshot.processCount) processes shown, sorted by \(model.processSort.title)")
                    .accessibilityHint("Select a process row to inspect its CPU, memory, and status.")

                    if model.visibleProcesses.isEmpty {
                        UnavailableProcessSearch(searchText: model.processSearchText)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(metrics.panelPadding)
        }
    }
}

private struct ProcessChrome: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                titleBlock

                Spacer(minLength: 12)

                sortPicker
                    .frame(maxWidth: 330)

                SearchField(text: $model.processSearchText)
                    .frame(width: 220)
            }

            VStack(alignment: .leading, spacing: 12) {
                titleBlock

                HStack(spacing: 12) {
                    sortPicker
                    SearchField(text: $model.processSearchText)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Process controls")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            PanelHeader(title: "Processes", symbol: "list.bullet.rectangle.portrait")
            Text("\(model.visibleProcesses.count) of \(model.snapshot.processCount) shown")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Processes")
        .accessibilityValue("\(model.visibleProcesses.count) of \(model.snapshot.processCount) shown")
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $model.processSort) {
            ForEach(ProcessSortOption.allCases) { option in
                Label(option.title, systemImage: option.symbolName)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Process sort")
        .accessibilityValue(model.processSort.title)
        .accessibilityHint("Changes the order of the process table.")
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Filter processes", text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel("Filter processes")
                .accessibilityValue(text.isEmpty ? "No filter" : text)
                .accessibilityHint("Filters by process name, PID, or status.")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear process filter")
                .accessibilityHint("Removes the current process search text.")
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct UnavailableProcessSearch: View {
    let searchText: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No processes reported" : "No matching processes")
                .font(.headline)
            Text(searchText.isEmpty ? "The current snapshot did not include process rows." : "Try a process name, PID, or status.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(searchText.isEmpty ? "No processes reported" : "No matching processes")
        .accessibilityValue(searchText.isEmpty ? "The current snapshot did not include process rows." : "Try a process name, PID, or status.")
    }
}

private struct ProcessInspector: View {
    @ObservedObject var model: DashboardModel
    let density: DashboardDensity

    private var metrics: DashboardDensityMetrics { density.metrics }

    var body: some View {
        GlassPanel(tintColor: .systemBlue.withAlphaComponent(0.06)) {
            VStack(alignment: .leading, spacing: metrics.rowSpacing + 6) {
                PanelHeader(title: "Inspector", symbol: "sidebar.right")

                if let process = model.selectedProcess {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(process.name)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .lineLimit(2)
                        Text("PID \(process.pid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(process.name)
                    .accessibilityValue("PID \(process.pid)")

                    Divider()

                    MetricLine(label: "CPU", value: process.cpuUsage.percentString)
                    MetricLine(label: "Memory", value: process.memory.byteString)
                    MetricLine(label: "Status", value: process.status)
                    MetricLine(label: "Sort", value: model.processSort.title)

                    Button {
                        model.copyCurrentSelectionToPasteboard()
                    } label: {
                        Label("Copy Process", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(model.selectedSection != .processes)
                    .accessibilityLabel("Copy selected process")
                    .accessibilityValue(process.name)
                    .accessibilityHint("Copies the selected process summary to the pasteboard.")

                    Button {
                        model.requestTerminateSelectedProcess()
                    } label: {
                        Label("Send TERM", systemImage: "xmark.octagon")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(model.selectedProcess == nil)
                    .help("Requests graceful termination after confirmation.")
                    .accessibilityLabel("Send TERM to selected process")
                    .accessibilityValue(process.name)
                    .accessibilityHint("Opens a confirmation dialog before sending a graceful terminate signal.")

                    if let status = model.processActionStatus {
                        ProcessActionStatusView(status: status)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select a process")
                            .font(.headline)
                        Text("Choose a row to inspect process identity, pressure, and status.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("No process selected")
                    .accessibilityHint("Choose a process row to show details here.")
                }
            }
            .padding(metrics.panelPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Process inspector")
    }
}

private struct ProcessActionStatusView: View {
    let status: ProcessActionStatus

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.message)
                    .font(.caption.weight(.semibold))
                if let detail = status.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: status.symbolName)
        }
        .foregroundStyle(status.tintColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Process action status")
        .accessibilityValue(status.accessibilityValue)
    }
}

private struct StorageView: View {
    let snapshot: RustTopSnapshot
    let density: DashboardDensity
    let searchText: String

    private var metrics: DashboardDensityMetrics { density.metrics }
    private var searchQuery: DashboardSearchQuery { DashboardSearchQuery(searchText) }
    private var disks: [DiskSnapshot] {
        guard !searchQuery.isEmpty else { return snapshot.disks }
        return snapshot.disks.filter { $0.matchesSearch(searchQuery) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: metrics.cardSpacing) {
                ForEach(disks) { disk in
                    GlassPanel(tintColor: .systemOrange.withAlphaComponent(0.07)) {
                        VStack(alignment: .leading, spacing: metrics.rowSpacing + 4) {
                            HStack {
                                PanelHeader(title: disk.mountPoint, symbol: "internaldrive")
                                Spacer()
                                Text(disk.fsType.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            ProgressView(value: disk.usagePercent, total: 100)
                                .tint(usageColor(disk.usagePercent))
                                .controlSize(.large)
                                .accessibilityLabel("Disk usage")
                                .accessibilityValue(disk.usagePercent.percentString)

                            HStack {
                                StatBlock(title: "Used", value: disk.used.byteString)
                                StatBlock(title: "Available", value: disk.available.byteString)
                                StatBlock(title: "Read", value: disk.readRate.rateString)
                                StatBlock(title: "Write", value: disk.writeRate.rateString)
                            }
                        }
                        .padding(metrics.panelPadding)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Storage \(disk.mountPoint)")
                        .accessibilityValue(disk.accessibilitySummary)
                        .accessibilityHint("File system \(disk.fsType.uppercased()).")
                    }
                }

                if disks.isEmpty, !searchQuery.isEmpty {
                    SearchEmptyState(
                        title: "No storage matches",
                        symbol: "internaldrive",
                        message: "No disks match \(searchQuery.text)."
                    )
                }
            }
            .padding(metrics.pagePadding)
        }
    }
}

private struct ServicesView: View {
    let snapshot: RustTopSnapshot
    let density: DashboardDensity
    let searchText: String

    private var metrics: DashboardDensityMetrics { density.metrics }
    private var searchQuery: DashboardSearchQuery { DashboardSearchQuery(searchText) }
    private var jobs: [LaunchdJobSnapshot] {
        guard !searchQuery.isEmpty else { return snapshot.launchdJobs }
        return snapshot.launchdJobs.filter { $0.matchesSearch(searchQuery) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: metrics.cardSpacing) {
                servicesSummary

                ForEach(jobs) { job in
                    GlassPanel(tintColor: .controlAccentColor.withAlphaComponent(0.06)) {
                        VStack(alignment: .leading, spacing: metrics.rowSpacing + 4) {
                            HStack(alignment: .top, spacing: 12) {
                                PanelHeader(title: job.label, symbol: job.symbolName)
                                Spacer()
                                Text(job.kind)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(job.kind == "Daemon" ? Color.tahoeBlue : Color.tahoeViolet)
                            }

                            HStack(spacing: 10) {
                                ServiceChip(label: job.domain, symbol: "scope")
                                ServiceChip(label: job.state, symbol: "checkmark.circle")
                            }

                            Text(job.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        .padding(metrics.panelPadding)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("launchd \(job.kind.lowercased()) \(job.label)")
                        .accessibilityValue(job.accessibilitySummary)
                        .accessibilityHint("Read-only launchd inventory item. RustTop does not enable, disable, unload, or bootstrap services.")
                    }
                }

                if snapshot.launchdJobs.isEmpty {
                    MissingTelemetryCard(
                        title: "launchd inventory unavailable",
                        symbol: "gearshape.2",
                        message: "No readable launchd plist inventory was reported. This view is read-only and only inventories standard launchd locations.",
                        state: "not_exposed"
                    )
                } else if jobs.isEmpty, !searchQuery.isEmpty {
                    SearchEmptyState(
                        title: "No service matches",
                        symbol: "gearshape.2",
                        message: "No launchd services or agents match \(searchQuery.text)."
                    )
                }
            }
            .padding(metrics.pagePadding)
        }
    }

    private var servicesSummary: some View {
        GlassPanel(tintColor: .controlAccentColor.withAlphaComponent(0.05)) {
            HStack(spacing: metrics.cardSpacing) {
                StatBlock(title: "Launchd Jobs", value: "\(snapshot.launchdJobs.count)")
                StatBlock(title: "Agents", value: "\(snapshot.launchdJobs.filter { $0.kind == "Agent" }.count)")
                StatBlock(title: "Daemons", value: "\(snapshot.launchdJobs.filter { $0.kind == "Daemon" }.count)")
                StatBlock(title: "User", value: "\(snapshot.launchdJobs.filter { $0.domain == "User" }.count)")
            }
            .padding(metrics.panelPadding)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("launchd inventory summary")
        .accessibilityValue("\(snapshot.launchdJobs.count) jobs, \(snapshot.launchdJobs.filter { $0.kind == "Agent" }.count) agents, \(snapshot.launchdJobs.filter { $0.kind == "Daemon" }.count) daemons")
        .accessibilityHint("Read-only inventory of launchd plist jobs.")
    }
}

private struct ServiceChip: View {
    let label: String
    let symbol: String

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

private struct SensorsView: View {
    let snapshot: RustTopSnapshot
    let density: DashboardDensity
    let searchText: String

    private var metrics: DashboardDensityMetrics { density.metrics }
    private var searchQuery: DashboardSearchQuery { DashboardSearchQuery(searchText) }
    private var gpus: [GpuSnapshot] {
        guard !searchQuery.isEmpty else { return snapshot.gpus }
        return snapshot.gpus.filter { $0.matchesSearch(searchQuery) }
    }
    private var sensors: [SensorSnapshot] {
        guard !searchQuery.isEmpty else { return snapshot.sensors }
        return snapshot.sensors.filter { $0.matchesSearch(searchQuery) }
    }
    private var batteries: [BatterySnapshot] {
        guard !searchQuery.isEmpty else { return snapshot.batteries }
        return snapshot.batteries.filter { $0.matchesSearch(searchQuery) }
    }
    private var showsMissingGPU: Bool {
        snapshot.gpus.isEmpty && (searchQuery.isEmpty || searchQuery.matches("GPU telemetry unavailable", "GPU", "graphics"))
    }
    private var showsMissingSensors: Bool {
        snapshot.sensors.isEmpty && (searchQuery.isEmpty || searchQuery.matches("Thermal sensors unavailable", "sensor", "sensors", "thermal", "temperature"))
    }
    private var showsMissingBatteries: Bool {
        snapshot.batteries.isEmpty && (searchQuery.isEmpty || searchQuery.matches("Battery not applicable", "battery", "batteries", "power"))
    }
    private var isShowingNoMatches: Bool {
        !searchQuery.isEmpty
            && gpus.isEmpty
            && sensors.isEmpty
            && batteries.isEmpty
            && !showsMissingGPU
            && !showsMissingSensors
            && !showsMissingBatteries
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: metrics.cardSpacing)], spacing: metrics.cardSpacing) {
                if showsMissingGPU {
                    MissingTelemetryCard(
                        title: "GPU telemetry unavailable",
                        symbol: "gpu",
                        message: "This Mac or macOS build did not expose GPU counters through RustTop's public collector path.",
                        state: "not_exposed"
                    )
                }

                if showsMissingSensors {
                    MissingTelemetryCard(
                        title: "Thermal sensors unavailable",
                        symbol: "thermometer.medium",
                        message: "Public temperature sensors are not reported for this hardware right now.",
                        state: "not_exposed"
                    )
                }

                if showsMissingBatteries {
                    MissingTelemetryCard(
                        title: "Battery not applicable",
                        symbol: "battery.0percent",
                        message: "Desktop Macs and some virtualized environments do not report battery hardware.",
                        state: "not_applicable"
                    )
                }

                ForEach(gpus) { gpu in
                    GlassPanel(tintColor: .systemGreen.withAlphaComponent(0.07)) {
                        VStack(alignment: .leading, spacing: metrics.rowSpacing + 2) {
                            PanelHeader(title: gpu.name, symbol: "gpu")
                            MetricLine(label: "Utilization", value: gpu.usagePercent.percentString)
                            MetricLine(label: "VRAM", value: "\(gpu.vramUsed.byteString) / \(gpu.vramTotal.byteString)")
                            if let temperature = gpu.temperature {
                                MetricLine(label: "Temperature", value: "\(temperature.oneDecimal) C")
                            }
                            if let powerWatts = gpu.powerWatts {
                                MetricLine(label: "Power", value: "\(powerWatts.oneDecimal) W")
                            }
                        }
                        .padding(metrics.panelPadding)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("GPU \(gpu.name)")
                        .accessibilityValue(gpu.accessibilitySummary)
                    }
                }

                ForEach(sensors) { sensor in
                    GlassPanel(tintColor: .systemYellow.withAlphaComponent(0.07)) {
                        VStack(alignment: .leading, spacing: metrics.rowSpacing + 2) {
                            PanelHeader(title: sensor.label, symbol: "thermometer.medium")
                            MetricLine(label: "Temperature", value: sensor.temperature.map { "\($0.oneDecimal) C" } ?? "N/A")
                            MetricLine(label: "Critical", value: sensor.critical.map { "\($0.oneDecimal) C" } ?? "N/A")
                        }
                        .padding(metrics.panelPadding)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Sensor \(sensor.label)")
                        .accessibilityValue(sensor.accessibilitySummary)
                    }
                }

                ForEach(batteries) { battery in
                    GlassPanel(tintColor: .systemBlue.withAlphaComponent(0.07)) {
                        VStack(alignment: .leading, spacing: metrics.rowSpacing + 2) {
                            PanelHeader(title: battery.name, symbol: "battery.75percent")
                            MetricLine(label: "Status", value: battery.status)
                            MetricLine(label: "Capacity", value: battery.capacityPercent.map(\.percentString) ?? "N/A")
                            MetricLine(label: "Health", value: battery.healthPercent.map(\.percentString) ?? "N/A")
                            if let cycleCount = battery.cycleCount {
                                MetricLine(label: "Cycles", value: "\(cycleCount)")
                            }
                            if let powerSource = battery.powerSource {
                                MetricLine(label: "Power Source", value: powerSource)
                            }
                            if let adapterWatts = battery.adapterWatts {
                                MetricLine(label: "Adapter", value: "\(adapterWatts.oneDecimal) W")
                            }
                        }
                        .padding(metrics.panelPadding)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Battery \(battery.name)")
                        .accessibilityValue(battery.accessibilitySummary)
                    }
                }

                if isShowingNoMatches {
                    SearchEmptyState(
                        title: "No sensor matches",
                        symbol: "magnifyingglass",
                        message: "No GPUs, sensors, or batteries match \(searchQuery.text)."
                    )
                }
            }
            .padding(metrics.pagePadding)
        }
    }
}

private struct SearchEmptyState: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        GlassPanel(tintColor: .controlAccentColor.withAlphaComponent(0.05)) {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeader(title: title, symbol: symbol)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(message)
    }
}

private struct MissingTelemetryCard: View {
    let title: String
    let symbol: String
    let message: String
    let state: String

    var body: some View {
        GlassPanel(tintColor: .controlAccentColor.withAlphaComponent(0.05)) {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeader(title: title, symbol: symbol)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(state)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(message) State \(state).")
    }
}

private struct ProcessRows: View {
    let processes: [ProcessSnapshot]
    let density: DashboardDensity

    private var metrics: DashboardDensityMetrics { density.metrics }

    var body: some View {
        VStack(spacing: metrics.rowSpacing) {
            ForEach(processes) { process in
                HStack(spacing: 12) {
                    Text("\(process.pid)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                    Text(process.name)
                        .lineLimit(1)
                    Spacer()
                    Text(process.cpuUsage.percentString)
                        .monospacedDigit()
                        .foregroundStyle(usageColor(process.cpuUsage))
                }
                .font(.callout)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(process.name)
                .accessibilityValue(process.accessibilitySummary)
            }
        }
        .accessibilityLabel("Top processes")
    }
}

private struct StatBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct MetricLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private func usageColor(_ value: Double) -> Color {
    switch value {
    case 0..<55: .tahoeMint
    case 55..<82: .tahoeAmber
    default: .tahoeRose
    }
}

private extension DiskSnapshot {
    var accessibilitySummary: String {
        "\(usagePercent.percentString) used, \(used.byteString) used, \(available.byteString) available, \(readRate.rateString) read, \(writeRate.rateString) write"
    }

    func matchesSearch(_ query: DashboardSearchQuery) -> Bool {
        query.matches(
            mountPoint,
            fsType,
            fsType.uppercased(),
            "disk",
            "drive",
            "storage",
            "volume",
            "\(usagePercent.percentString) used",
            "\(used.byteString) used",
            "\(available.byteString) available",
            "\(readRate.rateString) read",
            "\(writeRate.rateString) write"
        )
    }
}

private extension GpuSnapshot {
    var accessibilitySummary: String {
        var parts = [
            "\(usagePercent.percentString) utilization",
            "\(vramUsed.byteString) of \(vramTotal.byteString) VRAM"
        ]

        if let temperature {
            parts.append("\(temperature.oneDecimal) degrees Celsius")
        }

        if let powerWatts {
            parts.append("\(powerWatts.oneDecimal) watts")
        }

        return parts.joined(separator: ", ")
    }

    func matchesSearch(_ query: DashboardSearchQuery) -> Bool {
        var values = [
            name,
            "GPU",
            "graphics",
            "\(usagePercent.percentString) utilization",
            "\(vramUsed.byteString) VRAM used",
            "\(vramTotal.byteString) VRAM total"
        ]

        if let temperature {
            values.append("\(temperature.oneDecimal) C")
            values.append("\(temperature.oneDecimal) degrees Celsius")
        }

        if let powerWatts {
            values.append("\(powerWatts.oneDecimal) W")
            values.append("\(powerWatts.oneDecimal) watts")
        }

        return query.matches(values)
    }
}

private extension SensorSnapshot {
    var accessibilitySummary: String {
        let temperatureText = temperature.map { "\($0.oneDecimal) degrees Celsius" } ?? "Temperature unavailable"
        let criticalText = critical.map { "critical at \($0.oneDecimal) degrees Celsius" } ?? "critical temperature unavailable"
        return "\(temperatureText), \(criticalText)"
    }

    func matchesSearch(_ query: DashboardSearchQuery) -> Bool {
        var values = [
            label,
            "sensor",
            "thermal",
            "temperature"
        ]

        if let temperature {
            values.append("\(temperature.oneDecimal) C")
            values.append("\(temperature.oneDecimal) degrees Celsius")
        }

        if let critical {
            values.append("\(critical.oneDecimal) C critical")
            values.append("\(critical.oneDecimal) degrees Celsius critical")
        }

        return query.matches(values)
    }
}

private extension BatterySnapshot {
    var accessibilitySummary: String {
        var parts = ["Status \(status)"]

        if let capacityPercent {
            parts.append("capacity \(capacityPercent.percentString)")
        }

        if let healthPercent {
            parts.append("health \(healthPercent.percentString)")
        }

        if let cycleCount {
            parts.append("\(cycleCount) cycles")
        }

        if let powerSource {
            parts.append("power source \(powerSource)")
        }

        if let adapterWatts {
            parts.append("adapter \(adapterWatts.oneDecimal) watts")
        }

        return parts.joined(separator: ", ")
    }

    func matchesSearch(_ query: DashboardSearchQuery) -> Bool {
        var values = [
            name,
            status,
            "battery",
            "power"
        ]

        if let capacityPercent {
            values.append("\(capacityPercent.percentString) capacity")
        }

        if let healthPercent {
            values.append("\(healthPercent.percentString) health")
        }

        if let cycleCount {
            values.append("\(cycleCount) cycles")
        }

        if let powerSource {
            values.append(powerSource)
        }

        if let adapterWatts {
            values.append("\(adapterWatts.oneDecimal) W")
            values.append("\(adapterWatts.oneDecimal) watts")
        }

        return query.matches(values)
    }
}

private extension LaunchdJobSnapshot {
    var symbolName: String {
        kind == "Daemon" ? "gearshape.2" : "person.crop.circle.badge.gearshape"
    }

    var accessibilitySummary: String {
        "\(domain) \(kind), \(state), \(path)"
    }

    func matchesSearch(_ query: DashboardSearchQuery) -> Bool {
        query.matches(
            label,
            domain,
            kind,
            state,
            path,
            "launchd",
            "service",
            "agent",
            "daemon",
            "plist"
        )
    }
}

private extension ProcessSnapshot {
    var accessibilitySummary: String {
        "PID \(pid), CPU \(cpuUsage.percentString), memory \(memory.byteString), status \(status)"
    }

    func matchesSearch(_ query: DashboardSearchQuery) -> Bool {
        query.matches(
            name,
            status,
            "PID \(pid)",
            "\(pid)"
        )
    }
}

private extension RustTopSnapshot {
    var captureDate: Date {
        Date(timeIntervalSince1970: TimeInterval(capturedAtUnix))
    }

    func bestSearchSection(for query: DashboardSearchQuery, visibleSections: [DashboardSection]) -> DashboardSection? {
        let fallbackSections: [DashboardSection] = [.processes, .storage, .sensors, .services]
        let orderedSections = query.preferredSections + fallbackSections

        for section in orderedSections where visibleSections.contains(section) {
            if hasSearchMatch(in: section, query: query) {
                return section
            }
        }

        return nil
    }

    func hasSearchMatch(in section: DashboardSection, query: DashboardSearchQuery) -> Bool {
        guard !query.isEmpty else { return false }

        switch section {
        case .overview:
            return false
        case .processes:
            return topProcesses.contains { $0.matchesSearch(query) }
        case .storage:
            return disks.contains { $0.matchesSearch(query) }
        case .sensors:
            return gpus.contains { $0.matchesSearch(query) }
                || sensors.contains { $0.matchesSearch(query) }
                || batteries.contains { $0.matchesSearch(query) }
                || (gpus.isEmpty && query.matches("GPU telemetry unavailable", "GPU", "graphics"))
                || (sensors.isEmpty && query.matches("Thermal sensors unavailable", "sensor", "sensors", "thermal", "temperature"))
                || (batteries.isEmpty && query.matches("Battery not applicable", "battery", "batteries", "power"))
        case .services:
            return launchdJobs.contains { $0.matchesSearch(query) }
                || (launchdJobs.isEmpty && query.matches("launchd inventory unavailable", "launchd", "services", "agents"))
        }
    }
}

private extension DashboardArtifactStatus {
    var symbolName: String {
        switch phase {
        case .running:
            return "arrow.triangle.2.circlepath"
        case .succeeded:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var tintColor: Color {
        switch phase {
        case .running:
            return .tahoeBlue
        case .succeeded:
            return .tahoeMint
        case .failed:
            return .tahoeAmber
        }
    }

    var accessibilityValue: String {
        if let destinationPath {
            return "\(message), \(destinationPath)"
        }

        return message
    }
}

private extension ProcessActionStatus {
    var symbolName: String {
        switch phase {
        case .succeeded:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var tintColor: Color {
        switch phase {
        case .succeeded:
            return .tahoeMint
        case .failed:
            return .tahoeAmber
        }
    }

    var accessibilityValue: String {
        if let detail {
            return "\(message), \(detail)"
        }

        return message
    }
}

private extension AlertNotificationStatus {
    var symbolName: String {
        switch phase {
        case .delivered:
            return "bell.badge"
        case .failed:
            return "bell.slash"
        }
    }

    var tintColor: Color {
        switch phase {
        case .delivered:
            return .tahoeMint
        case .failed:
            return .tahoeAmber
        }
    }
}

private extension AlertSnapshot {
    var displayValue: String {
        unit.display(value)
    }

    var displayThreshold: String {
        unit.display(threshold)
    }

    var accessibilitySummary: String {
        "\(severity.displayTitle), \(displayValue) over \(displayThreshold), active for \(activeSeconds.durationString)"
    }
}

private extension AlertSeverity {
    var displayTitle: String {
        switch self {
        case .warning:
            return "Warning"
        case .critical:
            return "Critical"
        }
    }

    var symbolName: String {
        switch self {
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "exclamationmark.octagon"
        }
    }

    var tintColor: Color {
        switch self {
        case .warning:
            return .tahoeAmber
        case .critical:
            return .tahoeRose
        }
    }
}

private extension AlertUnit {
    func display(_ value: Double) -> String {
        switch self {
        case .percent:
            return value.percentString
        case .celsius:
            return "\(value.oneDecimal) C"
        }
    }
}

private extension MemorySnapshot {
    var hasBreakdown: Bool {
        appMemory != nil || wiredMemory != nil || compressedMemory != nil || fileCache != nil
    }

    var displayPressurePercent: Double {
        pressurePercent ?? usagePercent
    }

    var pressureSubtitle: String {
        if let pressureLevel {
            return "\(pressureLevel.capitalized) pressure | \(used.byteString) of \(total.byteString)"
        }

        return "\(used.byteString) of \(total.byteString)"
    }
}

private extension UInt64 {
    var byteString: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .memory)
    }

    var rateString: String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .binary))/s"
    }

    var durationString: String {
        let days = self / 86_400
        let hours = (self % 86_400) / 3_600
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        let minutes = (self % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(self)s"
    }
}

private extension Double {
    var percentString: String {
        "\(oneDecimal)%"
    }

    var oneDecimal: String {
        formatted(.number.precision(.fractionLength(1)))
    }
}
