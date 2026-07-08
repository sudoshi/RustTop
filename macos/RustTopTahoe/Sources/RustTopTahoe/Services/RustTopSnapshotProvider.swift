import Foundation

struct RustTopSnapshotProvider: Sendable {
    var binaryURL: URL?
    var timeoutSeconds: TimeInterval = 8
    var streamIntervalMilliseconds: Int = 1_000
    var prefersStreaming = true

    private let streamBridge: RustTopStreamingSnapshotBridge

    init(
        binaryURL: URL? = nil,
        timeoutSeconds: TimeInterval = 8,
        streamIntervalMilliseconds: Int = 1_000,
        prefersStreaming: Bool = true,
        streamBridge: RustTopStreamingSnapshotBridge = RustTopStreamingSnapshotBridge()
    ) {
        self.binaryURL = binaryURL
        self.timeoutSeconds = timeoutSeconds
        self.streamIntervalMilliseconds = streamIntervalMilliseconds
        self.prefersStreaming = prefersStreaming
        self.streamBridge = streamBridge
    }

    func fetch() async throws -> RustTopSnapshot {
        try await fetchResult().snapshot
    }

    func fetchResult() async throws -> RustTopSnapshotFetchResult {
        try await Task.detached(priority: .userInitiated) {
            try fetchBlocking()
        }.value
    }

    private func fetchBlocking() throws -> RustTopSnapshotFetchResult {
        let startedAt = Date()

        do {
            let binary = try resolvedBinaryURL()
            RustTopBridgeLog.snapshot.info(
                """
                snapshot_fetch_started helper=\(binary.lastPathComponent, privacy: .public) \
                helper_path=\(binary.path, privacy: .private)
                """
            )

            if prefersStreaming {
                do {
                    let snapshot = try streamBridge.fetchSnapshot(
                        binary: binary,
                        intervalMilliseconds: streamIntervalMilliseconds,
                        timeoutSeconds: timeoutSeconds,
                        decode: decodeSnapshot
                    )
                    let latency = RustTopBridgeLatency(startedAt: startedAt, finishedAt: Date())
                    RustTopBridgeLog.snapshot.info(
                        """
                        snapshot_stream_fetch_succeeded helper=\(binary.lastPathComponent, privacy: .public) \
                        latency_ms=\(latency.milliseconds, privacy: .public)
                        """
                    )
                    return RustTopSnapshotFetchResult(snapshot: snapshot, latency: latency)
                } catch {
                    let streamError = SnapshotProviderError.classify(error)
                    RustTopBridgeLog.snapshot.warning(
                        """
                        snapshot_stream_unavailable state=\(streamError.failureState.rawValue, privacy: .public) \
                        detail=\(streamError.localizedDescription, privacy: .private)
                        """
                    )
                    streamBridge.stop()
                }
            }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("rusttop-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: outputURL) }

            let snapshot = try exportSnapshot(binary: binary, outputURL: outputURL)
            let latency = RustTopBridgeLatency(startedAt: startedAt, finishedAt: Date())
            RustTopBridgeLog.snapshot.info(
                """
                snapshot_fetch_succeeded helper=\(binary.lastPathComponent, privacy: .public) \
                latency_ms=\(latency.milliseconds, privacy: .public)
                """
            )
            return RustTopSnapshotFetchResult(snapshot: snapshot, latency: latency)
        } catch {
            let providerError = SnapshotProviderError.classify(error)
            let latency = RustTopBridgeLatency(startedAt: startedAt, finishedAt: Date())
            RustTopBridgeLog.snapshot.error(
                """
                snapshot_fetch_failed state=\(providerError.failureState.rawValue, privacy: .public) \
                latency_ms=\(latency.milliseconds, privacy: .public) detail=\(providerError.localizedDescription, privacy: .private)
                """
            )
            throw providerError
        }
    }

    func stopStreaming() {
        streamBridge.stop()
    }

    private func exportSnapshot(binary: URL, outputURL: URL) throws -> RustTopSnapshot {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--export-json", outputURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw SnapshotProviderError.configuration(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw SnapshotProviderError.timedOut(binary.path)
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SnapshotProviderError.processFailed(
                binary.path,
                process.terminationStatus,
                errorText ?? "No stderr output."
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: outputURL)
        } catch {
            throw SnapshotProviderError.configuration(
                "RustTop helper did not write a readable JSON snapshot: \(error.localizedDescription)"
            )
        }

        return try decodeSnapshot(data)
    }

    func decodeSnapshot(_ data: Data) throws -> RustTopSnapshot {
        do {
            return try JSONDecoder().decode(RustTopSnapshot.self, from: data)
        } catch {
            throw SnapshotProviderError.decodeFailure(error)
        }
    }

    func resolvedBinaryURL() throws -> URL {
        try resolvedBinaryURL(
            environment: ProcessInfo.processInfo.environment,
            resourceURL: Bundle.main.resourceURL,
            sourceRepoRoot: sourceDerivedRepoRoot(),
            currentDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            isExecutable: { url in isExecutable(url) }
        )
    }

    func resolvedBinaryURL(
        environment: [String: String],
        resourceURL: URL?,
        sourceRepoRoot: URL?,
        currentDirectoryURL: URL,
        isExecutable: (URL) -> Bool
    ) throws -> URL {
        if let binaryURL, isExecutable(binaryURL) {
            return binaryURL
        }

        let candidates = candidateBinaryURLs(
            environment: environment,
            resourceURL: resourceURL,
            sourceRepoRoot: sourceRepoRoot,
            currentDirectoryURL: currentDirectoryURL
        )
        if let match = candidates.first(where: isExecutable) {
            return match
        }

        throw SnapshotProviderError.binaryNotFound(candidates.map(\.path))
    }

    func candidateBinaryURLs(
        environment: [String: String],
        resourceURL: URL?,
        sourceRepoRoot: URL?,
        currentDirectoryURL: URL
    ) -> [URL] {
        var candidates: [URL] = []

        if let override = environment["RUSTTOP_BINARY"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }

        if let resourceURL {
            candidates.append(resourceURL.appendingPathComponent("rust_top"))
        }

        if let repoRoot = sourceRepoRoot {
            candidates.append(repoRoot.appendingPathComponent("target/release/rust_top"))
            candidates.append(repoRoot.appendingPathComponent("target/debug/rust_top"))
        }

        let current = currentDirectoryURL
        candidates.append(current.appendingPathComponent("target/release/rust_top"))
        candidates.append(current.appendingPathComponent("target/debug/rust_top"))
        candidates.append(current.appendingPathComponent("../../target/release/rust_top").standardizedFileURL)
        candidates.append(current.appendingPathComponent("../../target/debug/rust_top").standardizedFileURL)

        return candidates
    }

    private func sourceDerivedRepoRoot() -> URL? {
        let sourceFile = URL(fileURLWithPath: #filePath)
        var cursor = sourceFile
        for _ in 0..<6 {
            cursor.deleteLastPathComponent()
        }
        return cursor
    }

    private func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }
}

struct RustTopStreamingLineBuffer: Sendable {
    private var buffer = Data()

    mutating func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }

        buffer.append(data)
        var lines: [Data] = []
        let newline = UInt8(ascii: "\n")
        let carriageReturn = UInt8(ascii: "\r")

        while let newlineIndex = buffer.firstIndex(of: newline) {
            var line = Data(buffer[..<newlineIndex])
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            if line.last == carriageReturn {
                line.removeLast()
            }
            if !line.isEmpty {
                lines.append(line)
            }
        }

        return lines
    }
}

final class RustTopStreamingSnapshotBridge: @unchecked Sendable {
    private let condition = NSCondition()
    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var binaryPath: String?
    private var intervalMilliseconds: Int?
    private var lineBuffer = RustTopStreamingLineBuffer()
    private var pendingLines: [Data] = []
    private var stderrData = Data()
    private let maxCapturedStderrBytes = 64 * 1024

    deinit {
        stop()
    }

    static func normalizedIntervalMilliseconds(_ value: Int) -> Int {
        min(max(value, 250), 60_000)
    }

    static func streamArguments(intervalMilliseconds: Int) -> [String] {
        [
            "--stream-json",
            "--interval-ms",
            "\(normalizedIntervalMilliseconds(intervalMilliseconds))"
        ]
    }

    func fetchSnapshot(
        binary: URL,
        intervalMilliseconds: Int,
        timeoutSeconds: TimeInterval,
        decode: (Data) throws -> RustTopSnapshot
    ) throws -> RustTopSnapshot {
        let normalizedInterval = Self.normalizedIntervalMilliseconds(intervalMilliseconds)

        condition.lock()
        let line: Data
        do {
            try ensureProcessLocked(binary: binary, intervalMilliseconds: normalizedInterval)
            line = try nextLineLocked(timeoutSeconds: timeoutSeconds, binaryPath: binary.path)
            condition.unlock()
        } catch {
            condition.unlock()
            stop()
            throw error
        }

        do {
            return try decode(line)
        } catch {
            stop()
            throw SnapshotProviderError.decodeFailure(error)
        }
    }

    func stop() {
        condition.lock()
        stopLocked()
        condition.unlock()
    }

    private func ensureProcessLocked(binary: URL, intervalMilliseconds: Int) throws {
        if let process,
           process.isRunning,
           binaryPath == binary.path,
           self.intervalMilliseconds == intervalMilliseconds {
            return
        }

        stopLocked()

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        process.executableURL = binary
        process.arguments = Self.streamArguments(intervalMilliseconds: intervalMilliseconds)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutHandle.readabilityHandler = { [weak self] handle in
            self?.ingestStdout(handle.availableData)
        }
        stderrHandle.readabilityHandler = { [weak self] handle in
            self?.ingestStderr(handle.availableData)
        }
        process.terminationHandler = { [weak self] _ in
            self?.signalProcessTerminated()
        }

        self.process = process
        self.stdoutHandle = stdoutHandle
        self.stderrHandle = stderrHandle
        self.binaryPath = binary.path
        self.intervalMilliseconds = intervalMilliseconds
        lineBuffer = RustTopStreamingLineBuffer()
        pendingLines = []
        stderrData = Data()

        do {
            try process.run()
        } catch {
            stopLocked()
            throw SnapshotProviderError.configuration(error.localizedDescription)
        }
    }

    private func nextLineLocked(timeoutSeconds: TimeInterval, binaryPath: String) throws -> Data {
        let timeout = max(0.1, timeoutSeconds)
        let deadline = Date().addingTimeInterval(timeout)

        while pendingLines.isEmpty {
            if let process, !process.isRunning {
                let status = process.terminationStatus
                let stderr = capturedStderrLocked()
                stopLocked()
                throw SnapshotProviderError.processFailed(binaryPath, status, stderr)
            }

            if Date() >= deadline {
                stopLocked()
                throw SnapshotProviderError.timedOut(binaryPath)
            }

            if !condition.wait(until: deadline), pendingLines.isEmpty {
                stopLocked()
                throw SnapshotProviderError.timedOut(binaryPath)
            }
        }

        return pendingLines.removeFirst()
    }

    private func ingestStdout(_ data: Data) {
        condition.lock()
        if data.isEmpty {
            stdoutHandle?.readabilityHandler = nil
            condition.broadcast()
            condition.unlock()
            return
        }

        let lines = lineBuffer.append(data)
        if !lines.isEmpty {
            pendingLines = [lines[lines.index(before: lines.endIndex)]]
            condition.broadcast()
        }
        condition.unlock()
    }

    private func ingestStderr(_ data: Data) {
        guard !data.isEmpty else { return }

        condition.lock()
        stderrData.append(data)
        if stderrData.count > maxCapturedStderrBytes {
            stderrData.removeFirst(stderrData.count - maxCapturedStderrBytes)
        }
        condition.unlock()
    }

    private func signalProcessTerminated() {
        condition.lock()
        condition.broadcast()
        condition.unlock()
    }

    private func stopLocked() {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        if let process, process.isRunning {
            process.terminate()
        }

        process = nil
        stdoutHandle = nil
        stderrHandle = nil
        binaryPath = nil
        intervalMilliseconds = nil
        lineBuffer = RustTopStreamingLineBuffer()
        pendingLines = []
        stderrData = Data()
        condition.broadcast()
    }

    private func capturedStderrLocked() -> String {
        let text = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text! : "No stderr output."
    }
}

enum SnapshotProviderError: LocalizedError, Equatable, Sendable {
    case binaryNotFound([String])
    case timedOut(String)
    case processFailed(String, Int32, String)
    case badJSON(String)
    case schemaMismatch(String)
    case configuration(String)

    var failureState: RustTopBridgeFailureState {
        switch self {
        case .binaryNotFound:
            return .missingHelper
        case .timedOut:
            return .timeout
        case .badJSON:
            return .badJSON
        case .schemaMismatch:
            return .schemaMismatch
        case .processFailed(_, let status, let stderr):
            return RustTopBridgeFailureState.processFailureState(status: status, stderr: stderr)
        case .configuration(let message):
            return RustTopBridgeFailureState.configurationState(message)
        }
    }

    static func classify(_ error: Error) -> SnapshotProviderError {
        if let providerError = error as? SnapshotProviderError {
            return providerError
        }

        return decodeFailure(error)
    }

    static func decodeFailure(_ error: Error) -> SnapshotProviderError {
        if let providerError = error as? SnapshotProviderError {
            return providerError
        }

        if error is SnapshotSchemaCompatibilityError {
            return .schemaMismatch(RustTopBridgeErrorMessage.decodingMessage(for: error))
        }

        if error is DecodingError {
            return .badJSON(RustTopBridgeErrorMessage.decodingMessage(for: error))
        }

        return .configuration(error.localizedDescription)
    }

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let candidates):
            let paths = candidates.prefix(5).joined(separator: ", ")
            return "RustTop helper binary was not found. Checked: \(paths)"
        case .timedOut(let binary):
            return "RustTop helper timed out while collecting a snapshot: \(binary)"
        case .processFailed(let binary, let status, let stderr):
            return "RustTop helper failed with status \(status): \(binary). \(stderr)"
        case .badJSON(let message):
            return "RustTop helper returned invalid snapshot JSON. \(message)"
        case .schemaMismatch(let message):
            return "RustTop snapshot schema mismatch. \(message)"
        case .configuration(let message):
            return "RustTop helper bridge configuration failed. \(message)"
        }
    }
}
