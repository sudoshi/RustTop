import XCTest
@testable import RustTopTahoe

final class RustTopSnapshotDecodingTests: XCTestCase {
    func testDecodesValidSnapshotFixture() throws {
        let snapshot = try decodeFixture("valid-snapshot")

        XCTAssertEqual(snapshot.schemaVersion, RustTopSnapshot.supportedSchemaVersion)
        XCTAssertEqual(snapshot.kind, "system_snapshot")
        XCTAssertEqual(snapshot.hostname, "tahoe-test-mac")
        XCTAssertEqual(snapshot.memory.usagePercent, 56.25)
        XCTAssertEqual(snapshot.memory.pressurePercent, 45.31)
        XCTAssertEqual(snapshot.memory.pressureLevel, "normal")
        XCTAssertEqual(snapshot.memory.appMemory, 21_474_836_480)
        XCTAssertEqual(snapshot.disks.first?.mountPoint, "/")
        XCTAssertEqual(snapshot.network.totalRxRate, 1_024)
        XCTAssertEqual(snapshot.gpus.first?.temperature, 49.5)
        XCTAssertEqual(snapshot.batteries.first?.capacityPercent, nil)
        XCTAssertEqual(snapshot.batteries.first?.cycleCount, 321)
        XCTAssertEqual(snapshot.batteries.first?.powerSource, "AC Power")
        XCTAssertEqual(snapshot.batteries.first?.adapterWatts, 96.0)
        XCTAssertEqual(snapshot.sensors.first?.critical, 100.0)
        XCTAssertEqual(snapshot.launchdJobs.count, 2)
        XCTAssertEqual(snapshot.launchdJobs.first?.label, "com.apple.WindowServer")
        XCTAssertEqual(snapshot.launchdJobs.first?.kind, "Daemon")
        XCTAssertEqual(snapshot.topProcesses.first?.name, "WindowServer")
        XCTAssertEqual(snapshot.alerts.first?.severity, .warning)
    }

    func testDecodesPartialSnapshotWithEmptyOptionalSections() throws {
        let snapshot = try decodeFixture("partial-empty-snapshot")

        XCTAssertEqual(snapshot.schemaVersion, RustTopSnapshot.supportedSchemaVersion)
        XCTAssertNil(snapshot.memory.pressurePercent)
        XCTAssertNil(snapshot.memory.pressureLevel)
        XCTAssertNil(snapshot.memory.appMemory)
        XCTAssertTrue(snapshot.disks.isEmpty)
        XCTAssertTrue(snapshot.gpus.isEmpty)
        XCTAssertTrue(snapshot.batteries.isEmpty)
        XCTAssertTrue(snapshot.sensors.isEmpty)
        XCTAssertTrue(snapshot.launchdJobs.isEmpty)
        XCTAssertTrue(snapshot.topProcesses.isEmpty)
        XCTAssertTrue(snapshot.alerts.isEmpty)
    }

    func testRejectsUnsupportedSchemaVersion() throws {
        let data = try fixtureData("incompatible-schema")

        XCTAssertThrowsError(try JSONDecoder().decode(RustTopSnapshot.self, from: data)) { error in
            guard case SnapshotSchemaCompatibilityError.unsupportedVersion(let actual, let supported) = error else {
                return XCTFail("Expected schema compatibility error, got \(error)")
            }

            XCTAssertEqual(actual, 2)
            XCTAssertEqual(supported, RustTopSnapshot.supportedSchemaVersion)
            XCTAssertEqual(
                error.localizedDescription,
                "RustTop snapshot schema version 2 is not supported. This app supports schema version 1."
            )
        }
    }

    func testProviderClassifiesMalformedSnapshotJSON() throws {
        let provider = RustTopSnapshotProvider()
        let data = Data("{".utf8)

        XCTAssertThrowsError(try provider.decodeSnapshot(data)) { error in
            guard case SnapshotProviderError.badJSON(let message) = error else {
                return XCTFail("Expected badJSON, got \(error)")
            }

            XCTAssertEqual((error as? SnapshotProviderError)?.failureState, .badJSON)
            XCTAssertTrue(message.contains("Snapshot JSON is malformed"))
        }
    }

    func testProviderClassifiesUnsupportedSchemaAsMismatch() throws {
        let provider = RustTopSnapshotProvider()
        let data = try fixtureData("incompatible-schema")

        XCTAssertThrowsError(try provider.decodeSnapshot(data)) { error in
            guard case SnapshotProviderError.schemaMismatch(let message) = error else {
                return XCTFail("Expected schemaMismatch, got \(error)")
            }

            XCTAssertEqual((error as? SnapshotProviderError)?.failureState, .schemaMismatch)
            XCTAssertTrue(message.contains("schema version 2"))
        }
    }

    private func decodeFixture(_ name: String) throws -> RustTopSnapshot {
        try JSONDecoder().decode(RustTopSnapshot.self, from: fixtureData(name))
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: name, withExtension: "json")
        )
        return try Data(contentsOf: url)
    }
}
