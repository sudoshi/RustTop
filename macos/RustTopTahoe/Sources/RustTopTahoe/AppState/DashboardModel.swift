import AppKit
@preconcurrency import Combine
import Darwin
import Foundation
import UserNotifications

@MainActor
final class DashboardModel: ObservableObject {
    @Published var snapshot: RustTopSnapshot = .preview
    @Published private(set) var metricHistory: MetricHistory = .preview
    @Published var isLive = false
    @Published var isPaused = false
    @Published var isRefreshing = false
    @Published var isWritingArtifact = false
    @Published var lastError: String?
    @Published var lastRefreshLatency: RustTopBridgeLatency?
    @Published var artifactStatus: DashboardArtifactStatus?
    @Published var selectedSection: DashboardSection? = .overview
    @Published var processSearchText = ""
    @Published var processSort: ProcessSortOption = .cpu
    @Published var selectedProcessID: UInt32?
    @Published var pendingProcessAction: ProcessActionRequest?
    @Published var processActionStatus: ProcessActionStatus?
    @Published var presentedAlert: AlertSnapshot?
    @Published var alertNotificationStatus: AlertNotificationStatus?
    @Published private(set) var nativeThresholdAlerts: [AlertSnapshot] = []

    private let baseProvider: RustTopSnapshotProvider
    private let settings: RustTopSettings
    private var refreshTask: Task<Void, Never>?
    private var dockTileSettingCancellable: AnyCancellable?
    private var notifiedAlertIdentities: Set<String> = []
    private var nativeAlertEngine = TahoeNativeAlertEngine()

    init(
        provider: RustTopSnapshotProvider = RustTopSnapshotProvider(),
        settings: RustTopSettings = RustTopSettings()
    ) {
        baseProvider = provider
        self.settings = settings
        selectedProcessID = snapshot.topProcesses.first?.id
        dockTileSettingCancellable = settings.$showDockLiveGraph
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                Task { @MainActor [weak self] in
                    self?.syncDockTile(isEnabled: isEnabled)
                }
            }
    }

    deinit {
        refreshTask?.cancel()
        dockTileSettingCancellable?.cancel()
        Task { @MainActor in
            DockTileGraphController.shared.clear()
        }
    }

    func start() {
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)

            while !Task.isCancelled {
                guard let self else { return }

                if !self.isPaused {
                    await self.refreshNow()
                }

                try? await Task.sleep(nanoseconds: self.refreshIntervalNanoseconds)
            }
        }
    }

    func refreshNow() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await currentProvider().fetchResult()
            let alertsForNotifications = applySnapshot(result.snapshot)
            lastRefreshLatency = result.latency
            isLive = true
            lastError = nil
            syncDockTile()
            Task { [weak self, alerts = alertsForNotifications] in
                await self?.deliverNotificationsIfNeeded(for: alerts)
            }
        } catch {
            isLive = false
            lastError = error.localizedDescription
            syncDockTile()
        }
    }

    func writeJSONSnapshot(to destinationURL: URL) async {
        await writeArtifact(.jsonSnapshot(destinationURL))
    }

    func writeCSVSnapshot(to destinationURL: URL) async {
        await writeArtifact(.csvSnapshot(destinationURL))
    }

    func writeIncidentBundle(to destinationURL: URL) async {
        await writeArtifact(.incidentBundle(destinationURL))
    }

    var visibleProcesses: [ProcessSnapshot] {
        let query = processSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredProcesses: [ProcessSnapshot]

        if query.isEmpty {
            filteredProcesses = snapshot.topProcesses
        } else {
            filteredProcesses = snapshot.topProcesses.filter { process in
                process.name.localizedCaseInsensitiveContains(query)
                    || process.status.localizedCaseInsensitiveContains(query)
                    || String(process.pid).contains(query)
            }
        }

        return filteredProcesses.sorted(by: sortProcesses)
    }

    var selectedProcess: ProcessSnapshot? {
        guard let selectedProcessID else { return nil }
        return snapshot.topProcesses.first { $0.id == selectedProcessID }
    }

    var samples: [MetricSample] {
        metricHistory.samples
    }

    var activeAlerts: [AlertSnapshot] {
        sortedAlerts(snapshot.alerts + nativeThresholdAlerts)
    }

    @discardableResult
    func applySnapshot(_ newSnapshot: RustTopSnapshot) -> [AlertSnapshot] {
        snapshot = newSnapshot
        nativeThresholdAlerts = nativeAlertEngine.evaluate(snapshot: newSnapshot, settings: settings)
        reconcileSelectedProcess()
        appendSample(from: newSnapshot)
        return activeAlerts
    }

    private func sortedAlerts(_ alerts: [AlertSnapshot]) -> [AlertSnapshot] {
        alerts.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity.sortPriority > rhs.severity.sortPriority
            }

            if lhs.activeSeconds != rhs.activeSeconds {
                return lhs.activeSeconds > rhs.activeSeconds
            }

            return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }
    }

    var visibleSections: [DashboardSection] {
        let sections = DashboardSection.allCases.filter(isSectionVisible)
        return sections.isEmpty ? [.overview] : sections
    }

    var resolvedSelectedSection: DashboardSection {
        let sections = visibleSections
        if let selectedSection, sections.contains(selectedSection) {
            return selectedSection
        }

        return sections[0]
    }

    var copyCommandTitle: String {
        if selectedSection == .processes {
            return "Copy Selected Process"
        }

        return "Copy Dashboard Summary"
    }

    var canCopyCurrentSelection: Bool {
        selectedSection == .processes ? selectedProcess != nil : true
    }

    var canTerminateSelectedProcess: Bool {
        guard let selectedProcess else { return false }
        return ProcessActionPolicy.termAvailability(for: selectedProcess).isAllowed
    }

    @discardableResult
    func copyCurrentSelectionToPasteboard() -> Bool {
        guard let text = currentClipboardText else { return false }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
    }

    func requestTerminateSelectedProcess() {
        guard let process = selectedProcess else {
            processActionStatus = .failed(
                "Select a process before sending TERM.",
                detail: "RustTop only acts on the selected process row."
            )
            return
        }

        switch ProcessActionPolicy.termAvailability(for: process) {
        case .allowed:
            pendingProcessAction = .terminate(process)
        case .blocked(let reason):
            processActionStatus = .failed(
                "TERM is not available for \(process.name).",
                detail: reason
            )
        }
    }

    func confirmPendingProcessAction() {
        guard let pendingProcessAction else { return }

        self.pendingProcessAction = nil
        switch pendingProcessAction.kind {
        case .terminate:
            sendTerm(to: pendingProcessAction.process)
        }
    }

    func cancelPendingProcessAction() {
        guard pendingProcessAction != nil else { return }
        pendingProcessAction = nil
    }

    func presentAlertDetails(_ alert: AlertSnapshot) {
        presentedAlert = alert
    }

    private func appendSample(from snapshot: RustTopSnapshot) {
        var history = metricHistory
        history.append(from: snapshot)
        metricHistory = history
    }

    private func syncDockTile(isEnabled: Bool? = nil) {
        DockTileGraphController.shared.update(
            samples: metricHistory.samples,
            isEnabled: isEnabled ?? settings.showDockLiveGraph,
            isLive: isLive,
            activeAlertCount: activeAlerts.count
        )
    }

    private var refreshIntervalNanoseconds: UInt64 {
        UInt64(settings.effectiveRefreshIntervalSeconds * 1_000_000_000)
    }

    private func currentProvider() throws -> RustTopSnapshotProvider {
        var provider = baseProvider

        if let helperURL = settings.helperOverrideURL {
            guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
                throw DashboardModelError.helperOverrideUnavailable(helperURL.path)
            }
            provider.binaryURL = helperURL
        }

        return provider
    }

    private func writeArtifact(_ request: DashboardArtifactRequest) async {
        guard !isWritingArtifact else {
            artifactStatus = .failed(
                "Another RustTop artifact workflow is already running.",
                destinationPath: request.destinationURL.path
            )
            return
        }

        isWritingArtifact = true
        artifactStatus = .running(request.startedMessage, destinationPath: request.destinationURL.path)
        defer { isWritingArtifact = false }

        do {
            let writer = RustTopArtifactWriter(provider: try currentProvider())
            let result = try await request.write(with: writer)
            artifactStatus = .succeeded(result.successMessage, destinationPath: result.destinationURL.path)
        } catch {
            artifactStatus = .failed(error.localizedDescription, destinationPath: request.destinationURL.path)
        }
    }

    private func reconcileSelectedProcess() {
        if let selectedProcessID,
           snapshot.topProcesses.contains(where: { $0.id == selectedProcessID }) {
            return
        }

        selectedProcessID = snapshot.topProcesses.first?.id
    }

    private func isSectionVisible(_ section: DashboardSection) -> Bool {
        switch section {
        case .overview:
            return settings.showOverviewPanel
        case .processes:
            return settings.showProcessesPanel
        case .storage:
            return settings.showStoragePanel
        case .sensors:
            return settings.showSensorsPanel
        case .services:
            return true
        }
    }

    private func sortProcesses(_ lhs: ProcessSnapshot, _ rhs: ProcessSnapshot) -> Bool {
        switch processSort {
        case .cpu:
            if lhs.cpuUsage == rhs.cpuUsage {
                return lhs.pid < rhs.pid
            }
            return lhs.cpuUsage > rhs.cpuUsage
        case .memory:
            if lhs.memory == rhs.memory {
                return lhs.pid < rhs.pid
            }
            return lhs.memory > rhs.memory
        case .pid:
            return lhs.pid < rhs.pid
        case .name:
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.pid < rhs.pid
            }
            return comparison == .orderedAscending
        }
    }

    private func sendTerm(to process: ProcessSnapshot) {
        switch ProcessActionPolicy.termAvailability(for: process) {
        case .allowed:
            break
        case .blocked(let reason):
            processActionStatus = .failed(
                "TERM is not available for \(process.name).",
                detail: reason
            )
            return
        }

        errno = 0
        let signalPID = pid_t(Int32(process.pid))
        let result = Darwin.kill(signalPID, SIGTERM)

        guard result == 0 else {
            let code = errno
            let reason = String(cString: Darwin.strerror(code))
            processActionStatus = .failed(
                "Could not send TERM to \(process.name).",
                detail: "PID \(process.pid): \(reason)"
            )
            return
        }

        processActionStatus = .succeeded(
            "TERM sent to \(process.name).",
            detail: "PID \(process.pid) was asked to terminate gracefully."
        )
    }

    private func deliverNotificationsIfNeeded(for alerts: [AlertSnapshot]) async {
        let currentIdentities = Set(alerts.map(notificationIdentity))
        notifiedAlertIdentities.formIntersection(currentIdentities)

        guard settings.alertNotificationsEnabled else { return }

        let eligibleAlerts = alerts.filter {
            $0.activeSeconds >= UInt64(settings.alertNotificationMinimumActiveSeconds.rounded())
        }

        guard !eligibleAlerts.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        guard await notificationsAreAuthorized(center: center) else { return }

        for alert in eligibleAlerts {
            let identity = notificationIdentity(for: alert)
            guard !notifiedAlertIdentities.contains(identity) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "RustTop \(alert.severity.notificationTitle)"
            content.subtitle = alert.label
            content.body = "\(alert.formattedValue) is above \(alert.formattedThreshold) for \(alert.activeSeconds.durationString)."
            content.sound = alert.severity == .critical ? .defaultCritical : .default

            let request = UNNotificationRequest(
                identifier: "rusttop.alert.\(identity)",
                content: content,
                trigger: nil
            )

            do {
                try await center.add(request)
                notifiedAlertIdentities.insert(identity)
                alertNotificationStatus = .delivered("Notification sent for \(alert.label).")
            } catch {
                alertNotificationStatus = .failed("Notification delivery failed: \(error.localizedDescription)")
            }
        }
    }

    private func notificationsAreAuthorized(center: UNUserNotificationCenter) async -> Bool {
        let notificationSettings = await center.notificationSettings()

        switch notificationSettings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                if !granted {
                    alertNotificationStatus = .failed("Notification permission was not granted.")
                }
                return granted
            } catch {
                alertNotificationStatus = .failed("Notification permission failed: \(error.localizedDescription)")
                return false
            }
        case .denied:
            alertNotificationStatus = .failed("Notification permission is disabled in System Settings.")
            return false
        @unknown default:
            alertNotificationStatus = .failed("Notification permission is unavailable.")
            return false
        }
    }

    private func notificationIdentity(for alert: AlertSnapshot) -> String {
        "\(alert.key).\(alert.severity.rawValue)"
    }

    private var currentClipboardText: String? {
        if selectedSection == .processes {
            return selectedProcess.map(processClipboardText)
        }

        return dashboardClipboardText
    }

    private func processClipboardText(for process: ProcessSnapshot) -> String {
        """
        Process: \(process.name)
        PID: \(process.pid)
        CPU: \(percentString(process.cpuUsage))
        Memory: \(byteString(process.memory))
        Status: \(process.status)
        """
    }

    private var dashboardClipboardText: String {
        """
        RustTop snapshot: \(snapshot.hostname)
        Captured: \(Date(timeIntervalSince1970: TimeInterval(snapshot.capturedAtUnix)).formatted(date: .abbreviated, time: .standard))
        CPU: \(percentString(snapshot.cpuUsagePercent))
        Memory: \(percentString(snapshot.memory.usagePercent)) (\(byteString(snapshot.memory.used)) of \(byteString(snapshot.memory.total)))
        Network: \(rateString(snapshot.network.totalRxRate)) in, \(rateString(snapshot.network.totalTxRate)) out
        Processes: \(snapshot.processCount)
        Alerts: \(activeAlerts.count)
        """
    }

    private func percentString(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    private func byteString(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private func rateString(_ value: UInt64) -> String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary))/s"
    }
}

enum ProcessActionAvailability: Equatable, Sendable {
    case allowed
    case blocked(String)

    var isAllowed: Bool {
        self == .allowed
    }
}

enum ProcessActionPolicy {
    static func termAvailability(
        for process: ProcessSnapshot,
        currentProcessID: UInt32 = Self.currentProcessID()
    ) -> ProcessActionAvailability {
        if process.pid == 0 {
            return .blocked("PID 0 is managed by the kernel and cannot be signaled safely.")
        }

        if process.pid == 1 {
            return .blocked("PID 1 is launchd; terminating it is not a safe user action.")
        }

        if process.pid == currentProcessID {
            return .blocked("RustTop will not terminate its own app process.")
        }

        if process.pid > UInt32(Int32.max) {
            return .blocked("PID \(process.pid) is outside the macOS signal range.")
        }

        return .allowed
    }

    private static func currentProcessID() -> UInt32 {
        let processID = ProcessInfo.processInfo.processIdentifier
        guard processID > 0 else { return 0 }
        return UInt32(processID)
    }
}

struct ProcessActionRequest: Identifiable, Sendable {
    enum Kind: Sendable {
        case terminate
    }

    let kind: Kind
    let process: ProcessSnapshot

    var id: String {
        "\(kind)-\(process.pid)"
    }

    static func terminate(_ process: ProcessSnapshot) -> ProcessActionRequest {
        ProcessActionRequest(kind: .terminate, process: process)
    }
}

struct ProcessActionStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case succeeded
        case failed
    }

    let phase: Phase
    let message: String
    let detail: String?

    static func succeeded(_ message: String, detail: String?) -> ProcessActionStatus {
        ProcessActionStatus(phase: .succeeded, message: message, detail: detail)
    }

    static func failed(_ message: String, detail: String?) -> ProcessActionStatus {
        ProcessActionStatus(phase: .failed, message: message, detail: detail)
    }
}

struct AlertNotificationStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case delivered
        case failed
    }

    let phase: Phase
    let message: String

    static func delivered(_ message: String) -> AlertNotificationStatus {
        AlertNotificationStatus(phase: .delivered, message: message)
    }

    static func failed(_ message: String) -> AlertNotificationStatus {
        AlertNotificationStatus(phase: .failed, message: message)
    }
}

struct TahoeNativeAlertConfiguration: Equatable, Sendable {
    let cpuWarningThreshold: Double
    let cpuCriticalThreshold: Double
    let memoryWarningThreshold: Double
    let memoryCriticalThreshold: Double
    let minimumActiveSeconds: UInt64

    init(settings: RustTopSettings) {
        cpuWarningThreshold = settings.nativeCPUWarningThreshold
        cpuCriticalThreshold = settings.nativeCPUCriticalThreshold
        memoryWarningThreshold = settings.nativeMemoryWarningThreshold
        memoryCriticalThreshold = settings.nativeMemoryCriticalThreshold
        minimumActiveSeconds = UInt64(settings.nativeAlertMinimumActiveSeconds.rounded())
    }
}

struct TahoeNativeAlertEngine: Sendable {
    private var firstSeenByKey: [String: UInt64] = [:]
    private var lastConfiguration: TahoeNativeAlertConfiguration?

    mutating func reset() {
        firstSeenByKey.removeAll()
        lastConfiguration = nil
    }

    mutating func evaluate(
        snapshot: RustTopSnapshot,
        settings: RustTopSettings
    ) -> [AlertSnapshot] {
        evaluate(snapshot: snapshot, configuration: TahoeNativeAlertConfiguration(settings: settings))
    }

    mutating func evaluate(
        snapshot: RustTopSnapshot,
        configuration: TahoeNativeAlertConfiguration
    ) -> [AlertSnapshot] {
        if lastConfiguration != configuration {
            firstSeenByKey.removeAll()
            lastConfiguration = configuration
        }

        let candidates = Self.candidates(from: snapshot, configuration: configuration)
        let activeKeys = Set(candidates.map(\.key))
        firstSeenByKey = firstSeenByKey.filter { activeKeys.contains($0.key) }

        return candidates.compactMap { candidate in
            let firstSeen = min(firstSeenByKey[candidate.key] ?? snapshot.capturedAtUnix, snapshot.capturedAtUnix)
            firstSeenByKey[candidate.key] = firstSeen

            let activeSeconds = snapshot.capturedAtUnix - firstSeen
            guard activeSeconds >= configuration.minimumActiveSeconds else { return nil }

            return AlertSnapshot(
                key: candidate.key,
                label: candidate.label,
                value: candidate.value,
                threshold: candidate.threshold,
                unit: .percent,
                severity: candidate.severity,
                activeSeconds: activeSeconds
            )
        }
    }

    private static func candidates(
        from snapshot: RustTopSnapshot,
        configuration: TahoeNativeAlertConfiguration
    ) -> [TahoeNativeAlertCandidate] {
        [
            candidate(
                keyPrefix: "native.cpu",
                label: "CPU Usage",
                value: snapshot.cpuUsagePercent,
                warningThreshold: configuration.cpuWarningThreshold,
                criticalThreshold: configuration.cpuCriticalThreshold
            ),
            candidate(
                keyPrefix: "native.memory",
                label: "Memory Usage",
                value: snapshot.memory.usagePercent,
                warningThreshold: configuration.memoryWarningThreshold,
                criticalThreshold: configuration.memoryCriticalThreshold
            )
        ].compactMap { $0 }
    }

    private static func candidate(
        keyPrefix: String,
        label: String,
        value: Double,
        warningThreshold: Double,
        criticalThreshold: Double
    ) -> TahoeNativeAlertCandidate? {
        guard value.isFinite else { return nil }

        if value >= criticalThreshold {
            return TahoeNativeAlertCandidate(
                key: "\(keyPrefix).critical",
                label: label,
                value: value,
                threshold: criticalThreshold,
                severity: .critical
            )
        }

        if value >= warningThreshold {
            return TahoeNativeAlertCandidate(
                key: "\(keyPrefix).warning",
                label: label,
                value: value,
                threshold: warningThreshold,
                severity: .warning
            )
        }

        return nil
    }
}

private struct TahoeNativeAlertCandidate: Sendable {
    let key: String
    let label: String
    let value: Double
    let threshold: Double
    let severity: AlertSeverity
}

private enum DashboardArtifactRequest {
    case jsonSnapshot(URL)
    case csvSnapshot(URL)
    case incidentBundle(URL)

    var destinationURL: URL {
        switch self {
        case .jsonSnapshot(let destinationURL),
             .csvSnapshot(let destinationURL),
             .incidentBundle(let destinationURL):
            return destinationURL
        }
    }

    var startedMessage: String {
        switch self {
        case .jsonSnapshot:
            return "Exporting JSON snapshot..."
        case .csvSnapshot:
            return "Exporting CSV snapshot..."
        case .incidentBundle:
            return "Writing incident bundle..."
        }
    }

    func write(with writer: RustTopArtifactWriter) async throws -> RustTopArtifactWriteResult {
        switch self {
        case .jsonSnapshot(let destinationURL):
            return try await writer.writeJSONSnapshot(to: destinationURL)
        case .csvSnapshot(let destinationURL):
            return try await writer.writeCSVSnapshot(to: destinationURL)
        case .incidentBundle(let destinationURL):
            return try await writer.writeIncidentBundle(to: destinationURL)
        }
    }
}

struct DashboardArtifactStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case running
        case succeeded
        case failed
    }

    let phase: Phase
    let message: String
    let destinationPath: String?

    static func running(_ message: String, destinationPath: String?) -> DashboardArtifactStatus {
        DashboardArtifactStatus(phase: .running, message: message, destinationPath: destinationPath)
    }

    static func succeeded(_ message: String, destinationPath: String?) -> DashboardArtifactStatus {
        DashboardArtifactStatus(phase: .succeeded, message: message, destinationPath: destinationPath)
    }

    static func failed(_ message: String, destinationPath: String?) -> DashboardArtifactStatus {
        DashboardArtifactStatus(phase: .failed, message: message, destinationPath: destinationPath)
    }
}

enum ProcessSortOption: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case pid
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .pid: "PID"
        case .name: "Name"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .pid: "number"
        case .name: "textformat"
        }
    }
}

enum DashboardModelError: LocalizedError {
    case helperOverrideUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .helperOverrideUnavailable(let path):
            return "RustTop helper override is not executable: \(path)"
        }
    }
}

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case processes
    case storage
    case sensors
    case services

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .processes: "Processes"
        case .storage: "Storage"
        case .sensors: "Sensors"
        case .services: "Services"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .processes: "list.bullet.rectangle.portrait"
        case .storage: "internaldrive"
        case .sensors: "thermometer.medium"
        case .services: "gearshape.2"
        }
    }
}

struct MetricSample: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let memory: Double
    let networkIn: Double
    let networkOut: Double
    let gpu: Double?
    let diskRead: Double?
    let diskWrite: Double?
    let temperature: Double?

    init(
        date: Date,
        cpu: Double,
        memory: Double,
        networkIn: Double,
        networkOut: Double,
        gpu: Double? = nil,
        diskRead: Double? = nil,
        diskWrite: Double? = nil,
        temperature: Double? = nil
    ) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.networkIn = networkIn
        self.networkOut = networkOut
        self.gpu = gpu
        self.diskRead = diskRead
        self.diskWrite = diskWrite
        self.temperature = temperature
    }

    init(snapshot: RustTopSnapshot) {
        self.init(
            date: Date(timeIntervalSince1970: TimeInterval(snapshot.capturedAtUnix)),
            cpu: snapshot.cpuUsagePercent,
            memory: snapshot.memory.usagePercent,
            networkIn: Double(snapshot.network.totalRxRate),
            networkOut: Double(snapshot.network.totalTxRate),
            gpu: Self.maxFinite(snapshot.gpus.map(\.usagePercent)),
            diskRead: Self.totalDiskRate(snapshot.disks.map(\.readRate)),
            diskWrite: Self.totalDiskRate(snapshot.disks.map(\.writeRate)),
            temperature: Self.maxFinite(
                snapshot.gpus.compactMap(\.temperature) + snapshot.sensors.compactMap(\.temperature)
            )
        )
    }

    static let preview: [MetricSample] = stride(from: 0, to: 34, by: 1).map { index in
        let phase = Double(index) / 5.0
        return MetricSample(
            date: Date().addingTimeInterval(Double(index - 34) * 2),
            cpu: 35 + sin(phase) * 18 + Double(index % 5),
            memory: 58 + cos(phase / 1.8) * 8,
            networkIn: 120_000 + Double(index * 7_000),
            networkOut: 42_000 + Double(index * 3_000),
            gpu: 22 + sin(phase / 1.4) * 11 + Double(index % 4),
            diskRead: 4_000_000 + Double(index * 180_000),
            diskWrite: 1_200_000 + Double(index * 95_000),
            temperature: 48 + cos(phase / 2.2) * 4
        )
    }

    private static func maxFinite(_ values: [Double]) -> Double? {
        values.filter(\.isFinite).max()
    }

    private static func totalDiskRate(_ values: [UInt64]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0.0) { total, value in
            total + Double(value)
        }
    }
}

struct MetricHistory: Sendable {
    static let defaultCapacity = 360

    private var sampleBuffer: RetainedMetricBuffer<MetricSample>

    init(capacity: Int = Self.defaultCapacity, samples: [MetricSample] = []) {
        sampleBuffer = RetainedMetricBuffer(capacity: capacity, values: samples)
    }

    var capacity: Int {
        sampleBuffer.capacity
    }

    var samples: [MetricSample] {
        sampleBuffer.values
    }

    var latest: MetricSample? {
        samples.last
    }

    var cpuValues: [Double] {
        samples.map(\.cpu)
    }

    var memoryValues: [Double] {
        samples.map(\.memory)
    }

    var networkInValues: [Double] {
        samples.map(\.networkIn)
    }

    var networkOutValues: [Double] {
        samples.map(\.networkOut)
    }

    var gpuValues: [Double] {
        samples.compactMap(\.gpu)
    }

    var diskReadValues: [Double] {
        samples.compactMap(\.diskRead)
    }

    var diskWriteValues: [Double] {
        samples.compactMap(\.diskWrite)
    }

    var temperatureValues: [Double] {
        samples.compactMap(\.temperature)
    }

    mutating func append(from snapshot: RustTopSnapshot) {
        append(MetricSample(snapshot: snapshot))
    }

    mutating func append(_ sample: MetricSample) {
        sampleBuffer.append(sample)
    }

    static let preview = MetricHistory(samples: MetricSample.preview)
}

struct RetainedMetricBuffer<Element: Sendable>: Sendable {
    let capacity: Int
    private(set) var values: [Element]

    init(capacity: Int, values: [Element] = []) {
        self.capacity = max(0, capacity)
        self.values = Array(values.suffix(self.capacity))
    }

    mutating func append(_ value: Element) {
        guard capacity > 0 else {
            values.removeAll()
            return
        }

        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }
}

private extension AlertSeverity {
    var sortPriority: Int {
        switch self {
        case .warning: 1
        case .critical: 2
        }
    }

    var notificationTitle: String {
        switch self {
        case .warning: "Warning"
        case .critical: "Critical Alert"
        }
    }
}

private extension AlertSnapshot {
    var formattedValue: String {
        unit.formatted(value)
    }

    var formattedThreshold: String {
        unit.formatted(threshold)
    }
}

private extension AlertUnit {
    func formatted(_ value: Double) -> String {
        switch self {
        case .percent:
            return "\(value.formatted(.number.precision(.fractionLength(1))))%"
        case .celsius:
            return "\(value.formatted(.number.precision(.fractionLength(1)))) C"
        }
    }
}

private extension UInt64 {
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
        return "\(self)s"
    }
}
