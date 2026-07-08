import Foundation
import XCTest
@testable import RustTopTahoe

final class RustTopStreamingSnapshotProviderTests: XCTestCase {
    func testStreamArgumentsClampIntervalAndUseNewlineMode() {
        XCTAssertEqual(
            RustTopStreamingSnapshotBridge.streamArguments(intervalMilliseconds: 1),
            ["--stream-json", "--interval-ms", "250"]
        )
        XCTAssertEqual(
            RustTopStreamingSnapshotBridge.streamArguments(intervalMilliseconds: 1_500),
            ["--stream-json", "--interval-ms", "1500"]
        )
    }

    func testStreamingLineBufferReturnsCompleteLinesAndKeepsPartialData() throws {
        var buffer = RustTopStreamingLineBuffer()

        XCTAssertEqual(buffer.append(Data("{\"a\":1".utf8)), [])

        let firstBatch = buffer.append(Data("}\r\n{\"b\":2}\npartial".utf8))
        XCTAssertEqual(firstBatch.map(string), ["{\"a\":1}", "{\"b\":2}"])

        let secondBatch = buffer.append(Data("-done\n\n".utf8))
        XCTAssertEqual(secondBatch.map(string), ["partial-done"])
    }

    func testProviderReadsMultipleSnapshotsFromOneStreamingProcess() async throws {
        let tempDirectory = try makeTempDirectory("streaming-provider")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let snapshotFile = tempDirectory.appendingPathComponent("snapshots.jsonl")
        let launchLog = tempDirectory.appendingPathComponent("launches.log")
        let helper = tempDirectory.appendingPathComponent("rust_top_fake")
        let snapshotLine = try encodedPreviewSnapshotLine()
        try snapshotLine.write(to: snapshotFile, atomically: true, encoding: .utf8)

        let script = """
        #!/bin/sh
        echo launch >> \(shellQuoted(launchLog.path))
        if [ "$1" != "--stream-json" ]; then
          exit 64
        fi
        if [ "$2" != "--interval-ms" ] || [ "$3" != "333" ]; then
          exit 65
        fi
        snapshot="$(cat \(shellQuoted(snapshotFile.path)))"
        printf '%s\\n' "$snapshot"
        sleep 1
        printf '%s\\n' "$snapshot"
        sleep 5
        """
        try writeExecutableScript(script, to: helper)

        let provider = RustTopSnapshotProvider(
            binaryURL: helper,
            timeoutSeconds: 2,
            streamIntervalMilliseconds: 333
        )
        defer { provider.stopStreaming() }

        let first = try await provider.fetch()
        let second = try await provider.fetch()

        XCTAssertEqual(first.schemaVersion, RustTopSnapshot.supportedSchemaVersion)
        XCTAssertEqual(second.schemaVersion, RustTopSnapshot.supportedSchemaVersion)
        XCTAssertEqual(first.kind, "system_snapshot")
        XCTAssertEqual(second.kind, "system_snapshot")

        let launches = try String(contentsOf: launchLog, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(launches.count, 1)
    }

    func testProviderKeepsLatestSnapshotWhenStreamOutpacesFetches() async throws {
        let tempDirectory = try makeTempDirectory("streaming-provider-latest")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let snapshotFile = tempDirectory.appendingPathComponent("snapshots.jsonl")
        let helper = tempDirectory.appendingPathComponent("rust_top_fake")
        let snapshotLines = try (1...8)
            .map { try encodedPreviewSnapshotLine(capturedAtUnix: UInt64($0)) }
            .joined(separator: "\n")
        try "\(snapshotLines)\n".write(to: snapshotFile, atomically: true, encoding: .utf8)

        let script = """
        #!/bin/sh
        if [ "$1" != "--stream-json" ]; then
          exit 64
        fi
        head -n 1 \(shellQuoted(snapshotFile.path))
        sleep 1
        tail -n +2 \(shellQuoted(snapshotFile.path))
        sleep 5
        """
        try writeExecutableScript(script, to: helper)

        let provider = RustTopSnapshotProvider(
            binaryURL: helper,
            timeoutSeconds: 2,
            streamIntervalMilliseconds: 250
        )
        defer { provider.stopStreaming() }

        let first = try await provider.fetch()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let snapshot = try await provider.fetch()

        XCTAssertEqual(first.capturedAtUnix, 1)
        XCTAssertEqual(snapshot.capturedAtUnix, 8)
    }

    func testProviderFallsBackToExportJSONWhenStreamingFails() async throws {
        let tempDirectory = try makeTempDirectory("streaming-fallback")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let snapshotFile = tempDirectory.appendingPathComponent("snapshot.json")
        let launchLog = tempDirectory.appendingPathComponent("launches.log")
        let helper = tempDirectory.appendingPathComponent("rust_top_fake")
        try encodedPreviewSnapshotLine().write(to: snapshotFile, atomically: true, encoding: .utf8)

        let script = """
        #!/bin/sh
        echo "$1" >> \(shellQuoted(launchLog.path))
        if [ "$1" = "--stream-json" ]; then
          echo "streaming not supported" >&2
          exit 64
        fi
        if [ "$1" = "--export-json" ]; then
          cp \(shellQuoted(snapshotFile.path)) "$2"
          exit 0
        fi
        exit 65
        """
        try writeExecutableScript(script, to: helper)

        let provider = RustTopSnapshotProvider(
            binaryURL: helper,
            timeoutSeconds: 2,
            streamIntervalMilliseconds: 333
        )
        defer { provider.stopStreaming() }

        let snapshot = try await provider.fetch()

        XCTAssertEqual(snapshot.schemaVersion, RustTopSnapshot.supportedSchemaVersion)
        let launches = try String(contentsOf: launchLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(launches, ["--stream-json", "--export-json"])
    }

    private func encodedPreviewSnapshotLine() throws -> String {
        try encodedPreviewSnapshotLine(capturedAtUnix: RustTopSnapshot.preview.capturedAtUnix)
    }

    private func encodedPreviewSnapshotLine(capturedAtUnix: UInt64) throws -> String {
        let preview = RustTopSnapshot.preview
        let snapshot = RustTopSnapshot(
            schemaVersion: preview.schemaVersion,
            kind: preview.kind,
            capturedAtUnix: capturedAtUnix,
            hostname: preview.hostname,
            osName: preview.osName,
            osVersion: preview.osVersion,
            kernelVersion: preview.kernelVersion,
            uptimeSeconds: preview.uptimeSeconds,
            cpuUsagePercent: preview.cpuUsagePercent,
            memory: preview.memory,
            disks: preview.disks,
            network: preview.network,
            gpus: preview.gpus,
            batteries: preview.batteries,
            sensors: preview.sensors,
            launchdJobs: preview.launchdJobs,
            processCount: preview.processCount,
            topProcesses: preview.topProcesses,
            alerts: preview.alerts
        )
        let data = try JSONEncoder().encode(snapshot)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func string(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }

    private func makeTempDirectory(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rusttop-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeExecutableScript(_ script: String, to url: URL) throws {
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
