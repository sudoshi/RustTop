import XCTest
@testable import RustTopTahoe

final class DashboardModelHistoryTests: XCTestCase {
    func testMetricSampleCapturesExtendedSnapshotFields() {
        let snapshot = RustTopSnapshot.preview
        let sample = MetricSample(snapshot: snapshot)

        XCTAssertEqual(sample.date.timeIntervalSince1970, TimeInterval(snapshot.capturedAtUnix), accuracy: 0.001)
        XCTAssertEqual(sample.cpu, snapshot.cpuUsagePercent)
        XCTAssertEqual(sample.memory, snapshot.memory.usagePercent)
        XCTAssertEqual(sample.networkIn, Double(snapshot.network.totalRxRate))
        XCTAssertEqual(sample.networkOut, Double(snapshot.network.totalTxRate))
        XCTAssertEqual(sample.gpu, 31.0)
        XCTAssertEqual(sample.diskRead, 12_400_000)
        XCTAssertEqual(sample.diskWrite, 4_800_000)
        XCTAssertEqual(sample.temperature, 54.0)
    }

    func testMetricSampleLeavesExtendedFieldsEmptyWhenSnapshotOmitsSources() throws {
        let snapshot = try decodeFixture("partial-empty-snapshot")
        let sample = MetricSample(snapshot: snapshot)

        XCTAssertNil(sample.gpu)
        XCTAssertNil(sample.diskRead)
        XCTAssertNil(sample.diskWrite)
        XCTAssertNil(sample.temperature)
    }

    func testMetricHistoryRetainsNewestSamplesAndCompactsOptionalSeries() {
        let first = MetricSample(
            date: Date(timeIntervalSince1970: 1),
            cpu: 10,
            memory: 20,
            networkIn: 30,
            networkOut: 40,
            gpu: nil,
            diskRead: nil,
            diskWrite: nil,
            temperature: nil
        )
        let second = MetricSample(
            date: Date(timeIntervalSince1970: 2),
            cpu: 11,
            memory: 21,
            networkIn: 31,
            networkOut: 41,
            gpu: 51,
            diskRead: 61,
            diskWrite: 71,
            temperature: 81
        )
        let third = MetricSample(
            date: Date(timeIntervalSince1970: 3),
            cpu: 12,
            memory: 22,
            networkIn: 32,
            networkOut: 42,
            gpu: 52,
            diskRead: 62,
            diskWrite: 72,
            temperature: 82
        )

        var history = MetricHistory(capacity: 2)
        history.append(first)
        history.append(second)
        history.append(third)

        XCTAssertEqual(history.capacity, 2)
        XCTAssertEqual(history.samples.map(\.cpu), [11, 12])
        XCTAssertEqual(history.cpuValues, [11, 12])
        XCTAssertEqual(history.memoryValues, [21, 22])
        XCTAssertEqual(history.networkInValues, [31, 32])
        XCTAssertEqual(history.networkOutValues, [41, 42])
        XCTAssertEqual(history.gpuValues, [51, 52])
        XCTAssertEqual(history.diskReadValues, [61, 62])
        XCTAssertEqual(history.diskWriteValues, [71, 72])
        XCTAssertEqual(history.temperatureValues, [81, 82])
        XCTAssertEqual(history.latest?.date, third.date)
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
