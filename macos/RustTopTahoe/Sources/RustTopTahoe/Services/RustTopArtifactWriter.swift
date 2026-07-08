import Foundation

struct RustTopArtifactWriter: Sendable {
    var provider: RustTopSnapshotProvider
    var timeoutSeconds: TimeInterval

    init(
        provider: RustTopSnapshotProvider = RustTopSnapshotProvider(),
        timeoutSeconds: TimeInterval = 30
    ) {
        self.provider = provider
        self.timeoutSeconds = timeoutSeconds
    }

    @discardableResult
    func writeJSONSnapshot(to destinationURL: URL) async throws -> RustTopArtifactWriteResult {
        try await run(.exportJSON(destinationURL))
    }

    @discardableResult
    func writeCSVSnapshot(to destinationURL: URL) async throws -> RustTopArtifactWriteResult {
        try await run(.exportCSV(destinationURL))
    }

    @discardableResult
    func writeIncidentBundle(to destinationURL: URL) async throws -> RustTopArtifactWriteResult {
        try await run(.incidentBundle(destinationURL))
    }

    @discardableResult
    func run(_ command: RustTopHelperCommand) async throws -> RustTopArtifactWriteResult {
        try await Task.detached(priority: .userInitiated) {
            try runBlocking(command)
        }.value
    }

    private func runBlocking(_ command: RustTopHelperCommand) throws -> RustTopArtifactWriteResult {
        let startedAt = Date()
        RustTopBridgeLog.artifact.info(
            """
            artifact_write_started command=\(command.logName, privacy: .public) \
            destination=\(command.destinationURL.lastPathComponent, privacy: .public) \
            destination_path=\(command.destinationURL.path, privacy: .private)
            """
        )

        do {
            let binary = try provider.resolvedBinaryURL()
            try command.prepareDestination()

            let process = Process()
            process.executableURL = binary
            process.arguments = command.arguments

            let errorPipe = Pipe()
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                throw RustTopArtifactWriterError.configuration(command.displayName, error.localizedDescription)
            }

            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                throw RustTopArtifactWriterError.timedOut(command.displayName, binary.path)
            }

            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw RustTopArtifactWriterError.processFailed(
                    command.displayName,
                    binary.path,
                    process.terminationStatus,
                    errorText ?? "No stderr output."
                )
            }

            let result = RustTopArtifactWriteResult(command: command, destinationURL: command.destinationURL)
            let latency = RustTopBridgeLatency(startedAt: startedAt, finishedAt: Date())
            RustTopBridgeLog.artifact.info(
                """
                artifact_write_succeeded command=\(command.logName, privacy: .public) \
                latency_ms=\(latency.milliseconds, privacy: .public) \
                destination_path=\(command.destinationURL.path, privacy: .private)
                """
            )
            return result
        } catch {
            let latency = RustTopBridgeLatency(startedAt: startedAt, finishedAt: Date())
            let failureState = RustTopBridgeFailureState.classify(error)
            RustTopBridgeLog.artifact.error(
                """
                artifact_write_failed command=\(command.logName, privacy: .public) \
                state=\(failureState.rawValue, privacy: .public) latency_ms=\(latency.milliseconds, privacy: .public) \
                destination_path=\(command.destinationURL.path, privacy: .private) detail=\(error.localizedDescription, privacy: .private)
                """
            )
            throw error
        }
    }
}

struct RustTopArtifactWriteResult: Equatable, Sendable {
    let command: RustTopHelperCommand
    let destinationURL: URL

    var successMessage: String {
        switch command {
        case .exportJSON:
            return "Exported JSON snapshot to \(destinationURL.path)"
        case .exportCSV:
            return "Exported CSV snapshot to \(destinationURL.path)"
        case .incidentBundle:
            return "Wrote incident bundle to \(destinationURL.path)"
        }
    }
}

enum RustTopHelperCommand: Equatable, Sendable {
    case exportJSON(URL)
    case exportCSV(URL)
    case incidentBundle(URL)

    var arguments: [String] {
        switch self {
        case .exportJSON(let destinationURL):
            return ["--export-json", destinationURL.path]
        case .exportCSV(let destinationURL):
            return ["--export-csv", destinationURL.path]
        case .incidentBundle(let destinationURL):
            return ["--incident-bundle", destinationURL.path]
        }
    }

    var destinationURL: URL {
        switch self {
        case .exportJSON(let destinationURL),
             .exportCSV(let destinationURL),
             .incidentBundle(let destinationURL):
            return destinationURL
        }
    }

    var displayName: String {
        switch self {
        case .exportJSON:
            return "JSON snapshot export"
        case .exportCSV:
            return "CSV snapshot export"
        case .incidentBundle:
            return "incident bundle"
        }
    }

    var logName: String {
        switch self {
        case .exportJSON:
            return "json_snapshot"
        case .exportCSV:
            return "csv_snapshot"
        case .incidentBundle:
            return "incident_bundle"
        }
    }

    fileprivate func prepareDestination(fileManager: FileManager = .default) throws {
        switch self {
        case .exportJSON(let destinationURL), .exportCSV(let destinationURL):
            let parentURL = destinationURL.deletingLastPathComponent()
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: parentURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw RustTopArtifactWriterError.destinationDirectoryMissing(parentURL.path)
            }
        case .incidentBundle(let destinationURL):
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    throw RustTopArtifactWriterError.destinationIsNotDirectory(destinationURL.path)
                }
                return
            }

            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        }
    }
}

enum RustTopArtifactWriterError: LocalizedError, Equatable, Sendable {
    case destinationDirectoryMissing(String)
    case destinationIsNotDirectory(String)
    case timedOut(String, String)
    case processFailed(String, String, Int32, String)
    case configuration(String, String)

    var failureState: RustTopBridgeFailureState {
        switch self {
        case .destinationDirectoryMissing, .destinationIsNotDirectory:
            return .destinationConfiguration
        case .timedOut:
            return .timeout
        case .processFailed(_, _, let status, let stderr):
            return RustTopBridgeFailureState.processFailureState(status: status, stderr: stderr)
        case .configuration(_, let message):
            return RustTopBridgeFailureState.configurationState(message)
        }
    }

    var errorDescription: String? {
        switch self {
        case .destinationDirectoryMissing(let path):
            return "Destination folder does not exist: \(path)"
        case .destinationIsNotDirectory(let path):
            return "Incident bundle destination is not a folder: \(path)"
        case .timedOut(let command, let binary):
            return "RustTop helper timed out during \(command): \(binary)"
        case .processFailed(let command, let binary, let status, let stderr):
            return "RustTop helper failed during \(command) with status \(status): \(binary). \(stderr)"
        case .configuration(let command, let message):
            return "RustTop helper configuration failed during \(command): \(message)"
        }
    }
}
