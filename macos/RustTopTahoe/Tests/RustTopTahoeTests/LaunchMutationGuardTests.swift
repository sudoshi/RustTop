import Combine
import XCTest
@testable import RustTopTahoe

final class LaunchMutationGuardTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testRecordingUnchangedWindowVisibilityDoesNotPublish() {
        let suiteName = "LaunchMutationGuardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = RustTopSettings(defaults: defaults)
        var publishCount = 0
        settings.objectWillChange
            .sink { publishCount += 1 }
            .store(in: &cancellables)

        settings.recordMainWindowVisibility(settings.lastMainWindowVisible)
        XCTAssertEqual(publishCount, 0)

        settings.recordMainWindowVisibility(!settings.lastMainWindowVisible)
        XCTAssertEqual(publishCount, 1)
    }

    @MainActor
    func testCancelingMissingProcessActionDoesNotPublish() {
        let suiteName = "LaunchMutationGuardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let model = DashboardModel(settings: RustTopSettings(defaults: defaults))
        var publishCount = 0
        model.objectWillChange
            .sink { publishCount += 1 }
            .store(in: &cancellables)

        model.cancelPendingProcessAction()
        XCTAssertEqual(publishCount, 0)

        model.pendingProcessAction = .terminate(
            ProcessSnapshot(
                pid: 42,
                name: "test-process",
                cpuUsage: 0,
                memory: 0,
                status: "Run"
            )
        )
        XCTAssertEqual(publishCount, 1)

        model.cancelPendingProcessAction()
        XCTAssertEqual(publishCount, 2)
    }
}
