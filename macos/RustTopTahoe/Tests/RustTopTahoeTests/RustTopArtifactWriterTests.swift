import XCTest
@testable import RustTopTahoe

final class RustTopArtifactWriterTests: XCTestCase {
    func testJSONSnapshotCommandUsesExportJSONFlagAndDestinationPath() {
        let destination = URL(fileURLWithPath: "/tmp/rusttop/snapshot.json")
        let command = RustTopHelperCommand.exportJSON(destination)

        XCTAssertEqual(command.arguments, ["--export-json", destination.path])
        XCTAssertEqual(command.destinationURL, destination)
        XCTAssertEqual(command.displayName, "JSON snapshot export")
        XCTAssertEqual(command.logName, "json_snapshot")
    }

    func testCSVSnapshotCommandUsesExportCSVFlagAndDestinationPath() {
        let destination = URL(fileURLWithPath: "/tmp/rusttop/snapshot.csv")
        let command = RustTopHelperCommand.exportCSV(destination)

        XCTAssertEqual(command.arguments, ["--export-csv", destination.path])
        XCTAssertEqual(command.destinationURL, destination)
        XCTAssertEqual(command.displayName, "CSV snapshot export")
        XCTAssertEqual(command.logName, "csv_snapshot")
    }

    func testIncidentBundleCommandUsesIncidentBundleFlagAndDirectoryPath() {
        let destination = URL(fileURLWithPath: "/tmp/rusttop/incident-bundle")
        let command = RustTopHelperCommand.incidentBundle(destination)

        XCTAssertEqual(command.arguments, ["--incident-bundle", destination.path])
        XCTAssertEqual(command.destinationURL, destination)
        XCTAssertEqual(command.displayName, "incident bundle")
        XCTAssertEqual(command.logName, "incident_bundle")
    }

    func testArtifactWriterErrorsExposeFailureStates() {
        XCTAssertEqual(
            RustTopArtifactWriterError.destinationDirectoryMissing("/tmp/missing").failureState,
            .destinationConfiguration
        )
        XCTAssertEqual(
            RustTopArtifactWriterError.destinationIsNotDirectory("/tmp/file").failureState,
            .destinationConfiguration
        )
        XCTAssertEqual(
            RustTopArtifactWriterError.configuration("JSON snapshot export", "failed").failureState,
            .destinationConfiguration
        )
        XCTAssertEqual(
            RustTopArtifactWriterError.configuration("JSON snapshot export", "Permission denied").failureState,
            .permissionsIssue
        )
        XCTAssertEqual(
            RustTopArtifactWriterError.timedOut("JSON snapshot export", "/tmp/rust_top").failureState,
            .timeout
        )
        XCTAssertEqual(
            RustTopArtifactWriterError.processFailed("JSON snapshot export", "/tmp/rust_top", 2, "stderr").failureState,
            .processFailure
        )
        XCTAssertEqual(
            RustTopArtifactWriterError.processFailed(
                "JSON snapshot export",
                "/tmp/rust_top",
                101,
                "thread 'main' panicked at collector"
            ).failureState,
            .collectorPanic
        )
    }
}
