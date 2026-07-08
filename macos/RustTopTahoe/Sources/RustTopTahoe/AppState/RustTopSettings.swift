import Combine
import Foundation

enum DashboardDensity: String, CaseIterable, Identifiable, Sendable {
    case comfortable
    case balanced
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comfortable: "Comfortable"
        case .balanced: "Balanced"
        case .compact: "Compact"
        }
    }
}

enum DashboardTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum DashboardAccent: String, CaseIterable, Identifiable, Sendable {
    case system
    case blue
    case mint
    case violet
    case rose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .blue: "Blue"
        case .mint: "Mint"
        case .violet: "Violet"
        case .rose: "Rose"
        }
    }
}

final class RustTopSettings: ObservableObject {
    enum StartupBehavior: String, CaseIterable, Identifiable {
        case openMainWindow
        case menuBarOnly
        case restorePrevious

        var id: String { rawValue }

        var title: String {
            switch self {
            case .openMainWindow: "Open main window"
            case .menuBarOnly: "Menu bar only"
            case .restorePrevious: "Restore previous"
            }
        }
    }

    private enum Key {
        static let refreshIntervalSeconds = "settings.refreshIntervalSeconds"
        static let helperPathOverride = "settings.helperPathOverride"
        static let startupBehavior = "settings.startupBehavior"
        static let showOverviewPanel = "settings.showOverviewPanel"
        static let showProcessesPanel = "settings.showProcessesPanel"
        static let showStoragePanel = "settings.showStoragePanel"
        static let showSensorsPanel = "settings.showSensorsPanel"
        static let dashboardTheme = "settings.dashboardTheme"
        static let dashboardAccent = "settings.dashboardAccent"
        static let dashboardDensity = "settings.dashboardDensity"
        static let alertNotificationsEnabled = "settings.alertNotificationsEnabled"
        static let alertNotificationMinimumActiveSeconds = "settings.alertNotificationMinimumActiveSeconds"
        static let nativeAlertCPUWarningThreshold = "settings.nativeAlertCPUWarningThreshold"
        static let nativeAlertCPUCriticalThreshold = "settings.nativeAlertCPUCriticalThreshold"
        static let nativeAlertMemoryWarningThreshold = "settings.nativeAlertMemoryWarningThreshold"
        static let nativeAlertMemoryCriticalThreshold = "settings.nativeAlertMemoryCriticalThreshold"
        static let nativeAlertMinimumActiveSeconds = "settings.nativeAlertMinimumActiveSeconds"
        static let showMenuBarMonitor = "settings.showMenuBarMonitor"
        static let showMenuBarCPU = "settings.showMenuBarCPU"
        static let showMenuBarMemory = "settings.showMenuBarMemory"
        static let showMenuBarNetwork = "settings.showMenuBarNetwork"
        static let showMenuBarGPUAndTemperature = "settings.showMenuBarGPUAndTemperature"
        static let showDockLiveGraph = "settings.showDockLiveGraph"
        static let lastMainWindowVisible = "settings.lastMainWindowVisible"
    }

    static let refreshIntervalRange: ClosedRange<Double> = 1...60
    static let alertNotificationMinimumActiveSecondsRange: ClosedRange<Double> = 0...600
    static let nativeAlertThresholdRange: ClosedRange<Double> = 0...100
    static let nativeAlertMinimumActiveSecondsRange: ClosedRange<Double> = 0...600
    static let menuBarOnlyMinimumRefreshIntervalSeconds = 5.0
    static let defaultNativeWarningThreshold = 90.0
    static let defaultNativeCriticalThreshold = 95.0
    static let defaultNativeAlertMinimumActiveSeconds = 10.0

    private let defaults: UserDefaults

    @Published private(set) var refreshIntervalSeconds: Double
    @Published private(set) var alertNotificationMinimumActiveSeconds: Double
    @Published private(set) var nativeCPUWarningThreshold: Double
    @Published private(set) var nativeCPUCriticalThreshold: Double
    @Published private(set) var nativeMemoryWarningThreshold: Double
    @Published private(set) var nativeMemoryCriticalThreshold: Double
    @Published private(set) var nativeAlertMinimumActiveSeconds: Double
    @Published var helperPathOverride: String {
        didSet { defaults.set(helperPathOverride, forKey: Key.helperPathOverride) }
    }
    @Published var startupBehavior: StartupBehavior {
        didSet { defaults.set(startupBehavior.rawValue, forKey: Key.startupBehavior) }
    }
    @Published var showOverviewPanel: Bool {
        didSet { defaults.set(showOverviewPanel, forKey: Key.showOverviewPanel) }
    }
    @Published var showProcessesPanel: Bool {
        didSet { defaults.set(showProcessesPanel, forKey: Key.showProcessesPanel) }
    }
    @Published var showStoragePanel: Bool {
        didSet { defaults.set(showStoragePanel, forKey: Key.showStoragePanel) }
    }
    @Published var showSensorsPanel: Bool {
        didSet { defaults.set(showSensorsPanel, forKey: Key.showSensorsPanel) }
    }
    @Published var dashboardTheme: DashboardTheme {
        didSet { defaults.set(dashboardTheme.rawValue, forKey: Key.dashboardTheme) }
    }
    @Published var dashboardAccent: DashboardAccent {
        didSet { defaults.set(dashboardAccent.rawValue, forKey: Key.dashboardAccent) }
    }
    @Published var dashboardDensity: DashboardDensity {
        didSet { defaults.set(dashboardDensity.rawValue, forKey: Key.dashboardDensity) }
    }
    @Published var alertNotificationsEnabled: Bool {
        didSet { defaults.set(alertNotificationsEnabled, forKey: Key.alertNotificationsEnabled) }
    }
    @Published var showMenuBarMonitor: Bool {
        didSet { defaults.set(showMenuBarMonitor, forKey: Key.showMenuBarMonitor) }
    }
    @Published var showMenuBarCPU: Bool {
        didSet { defaults.set(showMenuBarCPU, forKey: Key.showMenuBarCPU) }
    }
    @Published var showMenuBarMemory: Bool {
        didSet { defaults.set(showMenuBarMemory, forKey: Key.showMenuBarMemory) }
    }
    @Published var showMenuBarNetwork: Bool {
        didSet { defaults.set(showMenuBarNetwork, forKey: Key.showMenuBarNetwork) }
    }
    @Published var showMenuBarGPUAndTemperature: Bool {
        didSet { defaults.set(showMenuBarGPUAndTemperature, forKey: Key.showMenuBarGPUAndTemperature) }
    }
    @Published var showDockLiveGraph: Bool {
        didSet { defaults.set(showDockLiveGraph, forKey: Key.showDockLiveGraph) }
    }
    @Published private(set) var lastMainWindowVisible: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshIntervalSeconds = Self.clampedRefreshInterval(
            defaults.object(forKey: Key.refreshIntervalSeconds) as? Double ?? 2
        )
        alertNotificationMinimumActiveSeconds = Self.clampedAlertNotificationMinimumActiveSeconds(
            defaults.object(forKey: Key.alertNotificationMinimumActiveSeconds) as? Double ?? 60
        )
        let cpuThresholds = Self.normalizedNativeThresholds(
            warning: defaults.object(forKey: Key.nativeAlertCPUWarningThreshold) as? Double
                ?? Self.defaultNativeWarningThreshold,
            critical: defaults.object(forKey: Key.nativeAlertCPUCriticalThreshold) as? Double
                ?? Self.defaultNativeCriticalThreshold
        )
        nativeCPUWarningThreshold = cpuThresholds.warning
        nativeCPUCriticalThreshold = cpuThresholds.critical
        let memoryThresholds = Self.normalizedNativeThresholds(
            warning: defaults.object(forKey: Key.nativeAlertMemoryWarningThreshold) as? Double
                ?? Self.defaultNativeWarningThreshold,
            critical: defaults.object(forKey: Key.nativeAlertMemoryCriticalThreshold) as? Double
                ?? Self.defaultNativeCriticalThreshold
        )
        nativeMemoryWarningThreshold = memoryThresholds.warning
        nativeMemoryCriticalThreshold = memoryThresholds.critical
        nativeAlertMinimumActiveSeconds = Self.clampedNativeAlertMinimumActiveSeconds(
            defaults.object(forKey: Key.nativeAlertMinimumActiveSeconds) as? Double
                ?? Self.defaultNativeAlertMinimumActiveSeconds
        )
        helperPathOverride = defaults.string(forKey: Key.helperPathOverride) ?? ""
        startupBehavior = StartupBehavior(
            rawValue: defaults.string(forKey: Key.startupBehavior) ?? ""
        ) ?? .openMainWindow
        showOverviewPanel = defaults.bool(forKey: Key.showOverviewPanel, defaultValue: true)
        showProcessesPanel = defaults.bool(forKey: Key.showProcessesPanel, defaultValue: true)
        showStoragePanel = defaults.bool(forKey: Key.showStoragePanel, defaultValue: true)
        showSensorsPanel = defaults.bool(forKey: Key.showSensorsPanel, defaultValue: true)
        dashboardTheme = DashboardTheme(
            rawValue: defaults.string(forKey: Key.dashboardTheme) ?? ""
        ) ?? .system
        dashboardAccent = DashboardAccent(
            rawValue: defaults.string(forKey: Key.dashboardAccent) ?? ""
        ) ?? .system
        dashboardDensity = DashboardDensity(
            rawValue: defaults.string(forKey: Key.dashboardDensity) ?? ""
        ) ?? .balanced
        alertNotificationsEnabled = defaults.bool(forKey: Key.alertNotificationsEnabled, defaultValue: false)
        showMenuBarMonitor = defaults.bool(forKey: Key.showMenuBarMonitor, defaultValue: true)
        showMenuBarCPU = defaults.bool(forKey: Key.showMenuBarCPU, defaultValue: true)
        showMenuBarMemory = defaults.bool(forKey: Key.showMenuBarMemory, defaultValue: true)
        showMenuBarNetwork = defaults.bool(forKey: Key.showMenuBarNetwork, defaultValue: true)
        showMenuBarGPUAndTemperature = defaults.bool(forKey: Key.showMenuBarGPUAndTemperature, defaultValue: false)
        showDockLiveGraph = defaults.bool(forKey: Key.showDockLiveGraph, defaultValue: false)
        lastMainWindowVisible = defaults.bool(forKey: Key.lastMainWindowVisible, defaultValue: true)
    }

    func setRefreshIntervalSeconds(_ value: Double) {
        let clamped = Self.clampedRefreshInterval(value)
        refreshIntervalSeconds = clamped
        defaults.set(clamped, forKey: Key.refreshIntervalSeconds)
    }

    func setAlertNotificationMinimumActiveSeconds(_ value: Double) {
        let clamped = Self.clampedAlertNotificationMinimumActiveSeconds(value)
        alertNotificationMinimumActiveSeconds = clamped
        defaults.set(clamped, forKey: Key.alertNotificationMinimumActiveSeconds)
    }

    func setNativeCPUWarningThreshold(_ value: Double) {
        setNativeThresholds(
            warning: value,
            critical: nativeCPUCriticalThreshold,
            warningKey: Key.nativeAlertCPUWarningThreshold,
            criticalKey: Key.nativeAlertCPUCriticalThreshold,
            assign: { warning, critical in
                nativeCPUWarningThreshold = warning
                nativeCPUCriticalThreshold = critical
            }
        )
    }

    func setNativeCPUCriticalThreshold(_ value: Double) {
        setNativeThresholds(
            warning: nativeCPUWarningThreshold,
            critical: value,
            warningKey: Key.nativeAlertCPUWarningThreshold,
            criticalKey: Key.nativeAlertCPUCriticalThreshold,
            assign: { warning, critical in
                nativeCPUWarningThreshold = warning
                nativeCPUCriticalThreshold = critical
            }
        )
    }

    func setNativeMemoryWarningThreshold(_ value: Double) {
        setNativeThresholds(
            warning: value,
            critical: nativeMemoryCriticalThreshold,
            warningKey: Key.nativeAlertMemoryWarningThreshold,
            criticalKey: Key.nativeAlertMemoryCriticalThreshold,
            assign: { warning, critical in
                nativeMemoryWarningThreshold = warning
                nativeMemoryCriticalThreshold = critical
            }
        )
    }

    func setNativeMemoryCriticalThreshold(_ value: Double) {
        setNativeThresholds(
            warning: nativeMemoryWarningThreshold,
            critical: value,
            warningKey: Key.nativeAlertMemoryWarningThreshold,
            criticalKey: Key.nativeAlertMemoryCriticalThreshold,
            assign: { warning, critical in
                nativeMemoryWarningThreshold = warning
                nativeMemoryCriticalThreshold = critical
            }
        )
    }

    func setNativeAlertMinimumActiveSeconds(_ value: Double) {
        let clamped = Self.clampedNativeAlertMinimumActiveSeconds(value)
        nativeAlertMinimumActiveSeconds = clamped
        defaults.set(clamped, forKey: Key.nativeAlertMinimumActiveSeconds)
    }

    func clearHelperPathOverride() {
        helperPathOverride = ""
    }

    func recordMainWindowVisibility(_ isVisible: Bool) {
        guard lastMainWindowVisible != isVisible else { return }
        lastMainWindowVisible = isVisible
        defaults.set(isVisible, forKey: Key.lastMainWindowVisible)
    }

    var effectiveRefreshIntervalSeconds: Double {
        guard usesMenuBarOnlyLaunchMode else { return refreshIntervalSeconds }
        return max(refreshIntervalSeconds, Self.menuBarOnlyMinimumRefreshIntervalSeconds)
    }

    var shouldOpenMainWindowAtLaunch: Bool {
        switch startupBehavior {
        case .openMainWindow:
            return true
        case .menuBarOnly:
            return false
        case .restorePrevious:
            return lastMainWindowVisible
        }
    }

    private var usesMenuBarOnlyLaunchMode: Bool {
        !shouldOpenMainWindowAtLaunch
    }

    var helperOverrideURL: URL? {
        let trimmedPath = helperPathOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString(string: trimmedPath).expandingTildeInPath)
    }

    var helperPathState: HelperPathState {
        guard let helperOverrideURL else { return .empty }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: helperOverrideURL.path, isDirectory: &isDirectory)
        guard exists, !isDirectory.boolValue else { return .missing }
        guard FileManager.default.isExecutableFile(atPath: helperOverrideURL.path) else { return .notExecutable }
        return .ready
    }

    private static func clampedRefreshInterval(_ value: Double) -> Double {
        min(max(value, refreshIntervalRange.lowerBound), refreshIntervalRange.upperBound)
    }

    private static func clampedAlertNotificationMinimumActiveSeconds(_ value: Double) -> Double {
        min(
            max(value, alertNotificationMinimumActiveSecondsRange.lowerBound),
            alertNotificationMinimumActiveSecondsRange.upperBound
        )
    }

    private func setNativeThresholds(
        warning: Double,
        critical: Double,
        warningKey: String,
        criticalKey: String,
        assign: (Double, Double) -> Void
    ) {
        let thresholds = Self.normalizedNativeThresholds(warning: warning, critical: critical)
        assign(thresholds.warning, thresholds.critical)
        defaults.set(thresholds.warning, forKey: warningKey)
        defaults.set(thresholds.critical, forKey: criticalKey)
    }

    private static func normalizedNativeThresholds(
        warning: Double,
        critical: Double
    ) -> (warning: Double, critical: Double) {
        let clampedWarning = clampedNativeAlertThreshold(warning)
        let clampedCritical = clampedNativeAlertThreshold(critical)
        if clampedWarning <= clampedCritical {
            return (clampedWarning, clampedCritical)
        }

        return (clampedCritical, clampedCritical)
    }

    private static func clampedNativeAlertThreshold(_ value: Double) -> Double {
        min(max(value, nativeAlertThresholdRange.lowerBound), nativeAlertThresholdRange.upperBound)
    }

    private static func clampedNativeAlertMinimumActiveSeconds(_ value: Double) -> Double {
        min(
            max(value, nativeAlertMinimumActiveSecondsRange.lowerBound),
            nativeAlertMinimumActiveSecondsRange.upperBound
        )
    }
}

enum HelperPathState {
    case empty
    case ready
    case missing
    case notExecutable
}

private extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        object(forKey: key) as? Bool ?? defaultValue
    }
}
