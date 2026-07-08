import XCTest
@testable import RustTopTahoe

final class RustTopBridgeDiagnosticsTests: XCTestCase {
    func testLatencyMeasuresElapsedMilliseconds() {
        let startedAt = Date(timeIntervalSince1970: 10)
        let finishedAt = Date(timeIntervalSince1970: 10.125)

        let latency = RustTopBridgeLatency(startedAt: startedAt, finishedAt: finishedAt)

        XCTAssertEqual(latency.duration, 0.125, accuracy: 0.000_1)
        XCTAssertEqual(latency.milliseconds, 125, accuracy: 0.000_1)
        XCTAssertEqual(latency.startedAt, startedAt)
        XCTAssertEqual(latency.finishedAt, finishedAt)
    }

    func testLatencyClampsNegativeClockMovement() {
        let startedAt = Date(timeIntervalSince1970: 11)
        let finishedAt = Date(timeIntervalSince1970: 10)

        let latency = RustTopBridgeLatency(startedAt: startedAt, finishedAt: finishedAt)

        XCTAssertEqual(latency.duration, 0)
        XCTAssertEqual(latency.milliseconds, 0)
    }

    func testFailureStateClassifiesProviderErrors() {
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(SnapshotProviderError.binaryNotFound([])),
            .missingHelper
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(SnapshotProviderError.timedOut("/tmp/rust_top")),
            .timeout
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(SnapshotProviderError.processFailed("/tmp/rust_top", 2, "stderr")),
            .processFailure
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(SnapshotProviderError.badJSON("invalid")),
            .badJSON
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(SnapshotProviderError.schemaMismatch("schema")),
            .schemaMismatch
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(SnapshotProviderError.configuration("config")),
            .destinationConfiguration
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(SnapshotProviderError.configuration("Permission denied")),
            .permissionsIssue
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(
                SnapshotProviderError.processFailed("/tmp/rust_top", 101, "thread 'main' panicked at src/main.rs")
            ),
            .collectorPanic
        )
    }

    func testFailureStateClassifiesArtifactWriterErrors() {
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(RustTopArtifactWriterError.destinationDirectoryMissing("/tmp/missing")),
            .destinationConfiguration
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(RustTopArtifactWriterError.destinationIsNotDirectory("/tmp/file")),
            .destinationConfiguration
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(RustTopArtifactWriterError.configuration("JSON snapshot export", "config")),
            .destinationConfiguration
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(
                RustTopArtifactWriterError.configuration("JSON snapshot export", "Operation not permitted")
            ),
            .permissionsIssue
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(RustTopArtifactWriterError.timedOut("JSON snapshot export", "/tmp/rust_top")),
            .timeout
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(
                RustTopArtifactWriterError.processFailed("JSON snapshot export", "/tmp/rust_top", 1, "stderr")
            ),
            .processFailure
        )
        XCTAssertEqual(
            RustTopBridgeFailureState.classify(
                RustTopArtifactWriterError.processFailed(
                    "JSON snapshot export",
                    "/tmp/rust_top",
                    101,
                    "note: run with RUST_BACKTRACE=1"
                )
            ),
            .collectorPanic
        )
    }

    func testFailureStateClassifiesRawDecodeErrors() {
        let context = DecodingError.Context(codingPath: [], debugDescription: "not json")
        let error = DecodingError.dataCorrupted(context)

        XCTAssertEqual(RustTopBridgeFailureState.classify(error), .badJSON)
    }
}
