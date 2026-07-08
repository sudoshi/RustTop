import XCTest
@testable import RustTopTahoe

final class DashboardModelNativeAlertTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "DashboardModelNativeAlertTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    func testApplySnapshotAugmentsEmbeddedAlertsWithNativeThresholdAlerts() {
        let settings = RustTopSettings(defaults: defaults)
        settings.setNativeCPUWarningThreshold(30)
        settings.setNativeCPUCriticalThreshold(35)
        settings.setNativeMemoryWarningThreshold(50)
        settings.setNativeMemoryCriticalThreshold(90)
        settings.setNativeAlertMinimumActiveSeconds(0)
        let model = DashboardModel(settings: settings)
        let embeddedAlert = AlertSnapshot(
            key: "cpu",
            label: "Embedded CPU",
            value: 85,
            threshold: 80,
            unit: .percent,
            severity: .warning,
            activeSeconds: 12
        )

        let alerts = model.applySnapshot(
            snapshot(capturedAtUnix: 100, cpuUsagePercent: 37.5, memoryUsagePercent: 56.25, alerts: [embeddedAlert])
        )

        XCTAssertEqual(model.snapshot.alerts.map(\.key), ["cpu"])
        XCTAssertTrue(alerts.contains { $0.key == "cpu" })
        XCTAssertTrue(alerts.contains { $0.key == "native.cpu.critical" })
        XCTAssertTrue(alerts.contains { $0.key == "native.memory.warning" })
    }

    @MainActor
    func testNativeThresholdAlertsHonorMinimumActiveSecondsAndResetWhenMetricClears() {
        let settings = RustTopSettings(defaults: defaults)
        settings.setNativeMemoryWarningThreshold(50)
        settings.setNativeMemoryCriticalThreshold(95)
        settings.setNativeAlertMinimumActiveSeconds(10)
        let model = DashboardModel(settings: settings)

        XCTAssertTrue(
            model.applySnapshot(snapshot(capturedAtUnix: 100, memoryUsagePercent: 70))
                .filter { $0.key.hasPrefix("native.") }
                .isEmpty
        )
        XCTAssertTrue(
            model.applySnapshot(snapshot(capturedAtUnix: 109, memoryUsagePercent: 70))
                .filter { $0.key.hasPrefix("native.") }
                .isEmpty
        )

        let sustainedAlerts = model.applySnapshot(snapshot(capturedAtUnix: 110, memoryUsagePercent: 70))
        let memoryAlert = sustainedAlerts.first { $0.key == "native.memory.warning" }
        XCTAssertEqual(memoryAlert?.activeSeconds, 10)

        XCTAssertTrue(
            model.applySnapshot(snapshot(capturedAtUnix: 120, memoryUsagePercent: 40))
                .filter { $0.key.hasPrefix("native.") }
                .isEmpty
        )
        XCTAssertTrue(
            model.applySnapshot(snapshot(capturedAtUnix: 130, memoryUsagePercent: 70))
                .filter { $0.key.hasPrefix("native.") }
                .isEmpty
        )
    }

    private func snapshot(
        capturedAtUnix: UInt64,
        cpuUsagePercent: Double = 10,
        memoryUsagePercent: Double = 10,
        alerts: [AlertSnapshot] = []
    ) -> RustTopSnapshot {
        RustTopSnapshot(
            schemaVersion: RustTopSnapshot.supportedSchemaVersion,
            kind: "system_snapshot",
            capturedAtUnix: capturedAtUnix,
            hostname: "test-mac",
            osName: "macOS",
            osVersion: "26.0",
            kernelVersion: "25.0.0",
            uptimeSeconds: capturedAtUnix,
            cpuUsagePercent: cpuUsagePercent,
            memory: MemorySnapshot(
                total: 100,
                used: UInt64(memoryUsagePercent),
                available: 100 - UInt64(memoryUsagePercent),
                usagePercent: memoryUsagePercent,
                swapTotal: 100,
                swapUsed: 0,
                swapUsagePercent: 0,
                appMemory: nil,
                wiredMemory: nil,
                compressedMemory: nil,
                fileCache: nil,
                pressurePercent: nil,
                pressureLevel: nil
            ),
            disks: [],
            network: NetworkSnapshot(totalRxRate: 0, totalTxRate: 0),
            gpus: [],
            batteries: [],
            sensors: [],
            launchdJobs: [],
            processCount: 0,
            topProcesses: [],
            alerts: alerts
        )
    }
}
