import XCTest
@testable import RustTopTahoe

final class RustTopSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RustTopSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMenuBarOnlyStartupUsesLowPowerCadenceFloor() {
        let settings = RustTopSettings(defaults: defaults)

        settings.setRefreshIntervalSeconds(1)
        settings.startupBehavior = .menuBarOnly

        XCTAssertFalse(settings.shouldOpenMainWindowAtLaunch)
        XCTAssertEqual(settings.effectiveRefreshIntervalSeconds, RustTopSettings.menuBarOnlyMinimumRefreshIntervalSeconds)
    }

    func testRestorePreviousUsesPersistedMainWindowVisibility() {
        let settings = RustTopSettings(defaults: defaults)
        settings.startupBehavior = .restorePrevious
        settings.recordMainWindowVisibility(false)

        let restoredSettings = RustTopSettings(defaults: defaults)

        XCTAssertEqual(restoredSettings.startupBehavior, .restorePrevious)
        XCTAssertFalse(restoredSettings.shouldOpenMainWindowAtLaunch)
    }

    func testOpenMainWindowIgnoresPreviousHiddenState() {
        let settings = RustTopSettings(defaults: defaults)
        settings.recordMainWindowVisibility(false)
        settings.startupBehavior = .openMainWindow

        XCTAssertTrue(settings.shouldOpenMainWindowAtLaunch)
        XCTAssertEqual(settings.effectiveRefreshIntervalSeconds, settings.refreshIntervalSeconds)
    }

    func testAppearancePreferencesPersist() {
        let settings = RustTopSettings(defaults: defaults)
        settings.dashboardTheme = .dark
        settings.dashboardAccent = .violet
        settings.dashboardDensity = .compact
        settings.showDockLiveGraph = true

        let restoredSettings = RustTopSettings(defaults: defaults)

        XCTAssertEqual(restoredSettings.dashboardTheme, .dark)
        XCTAssertEqual(restoredSettings.dashboardAccent, .violet)
        XCTAssertEqual(restoredSettings.dashboardDensity, .compact)
        XCTAssertTrue(restoredSettings.showDockLiveGraph)
    }

    func testNativeAlertThresholdPreferencesPersist() {
        let settings = RustTopSettings(defaults: defaults)
        settings.setNativeCPUWarningThreshold(82)
        settings.setNativeCPUCriticalThreshold(94)
        settings.setNativeMemoryWarningThreshold(84)
        settings.setNativeMemoryCriticalThreshold(96)
        settings.setNativeAlertMinimumActiveSeconds(45)

        let restoredSettings = RustTopSettings(defaults: defaults)

        XCTAssertEqual(restoredSettings.nativeCPUWarningThreshold, 82)
        XCTAssertEqual(restoredSettings.nativeCPUCriticalThreshold, 94)
        XCTAssertEqual(restoredSettings.nativeMemoryWarningThreshold, 84)
        XCTAssertEqual(restoredSettings.nativeMemoryCriticalThreshold, 96)
        XCTAssertEqual(restoredSettings.nativeAlertMinimumActiveSeconds, 45)
    }

    func testNativeAlertThresholdsClampAndNormalize() {
        let settings = RustTopSettings(defaults: defaults)

        settings.setNativeCPUWarningThreshold(150)
        XCTAssertEqual(settings.nativeCPUWarningThreshold, RustTopSettings.defaultNativeCriticalThreshold)
        XCTAssertEqual(settings.nativeCPUCriticalThreshold, RustTopSettings.defaultNativeCriticalThreshold)

        settings.setNativeCPUCriticalThreshold(-10)
        XCTAssertEqual(settings.nativeCPUWarningThreshold, 0)
        XCTAssertEqual(settings.nativeCPUCriticalThreshold, 0)

        settings.setNativeAlertMinimumActiveSeconds(900)
        XCTAssertEqual(
            settings.nativeAlertMinimumActiveSeconds,
            RustTopSettings.nativeAlertMinimumActiveSecondsRange.upperBound
        )
    }
}
