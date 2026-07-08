import Foundation
import OSLog

struct RustTopBridgeLatency: Equatable, Sendable {
    let startedAt: Date
    let finishedAt: Date
    let duration: TimeInterval

    init(startedAt: Date, finishedAt: Date) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        duration = max(0, finishedAt.timeIntervalSince(startedAt))
    }

    var milliseconds: Double {
        duration * 1_000
    }
}

struct RustTopSnapshotFetchResult: Sendable {
    let snapshot: RustTopSnapshot
    let latency: RustTopBridgeLatency
}

enum RustTopBridgeFailureState: String, Equatable, Sendable {
    case missingHelper = "missing_helper"
    case timeout
    case processFailure = "process_failure"
    case badJSON = "bad_json"
    case schemaMismatch = "schema_mismatch"
    case permissionsIssue = "permissions_issue"
    case collectorPanic = "collector_panic"
    case destinationConfiguration = "destination_configuration"

    static func classify(_ error: Error) -> RustTopBridgeFailureState {
        if let providerError = error as? SnapshotProviderError {
            return providerError.failureState
        }

        if let writerError = error as? RustTopArtifactWriterError {
            return writerError.failureState
        }

        if error is SnapshotSchemaCompatibilityError {
            return .schemaMismatch
        }

        if error is DecodingError {
            return .badJSON
        }

        return .destinationConfiguration
    }

    static func processFailureState(status _: Int32, stderr: String) -> RustTopBridgeFailureState {
        if messageIndicatesCollectorPanic(stderr) {
            return .collectorPanic
        }

        if messageIndicatesPermissionsIssue(stderr) {
            return .permissionsIssue
        }

        return .processFailure
    }

    static func configurationState(_ message: String) -> RustTopBridgeFailureState {
        messageIndicatesPermissionsIssue(message) ? .permissionsIssue : .destinationConfiguration
    }

    private static func messageIndicatesCollectorPanic(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("panicked at")
            || lowercased.contains("thread 'main' panicked")
            || lowercased.contains("rust backtrace")
            || lowercased.contains("rust_backtrace")
    }

    private static func messageIndicatesPermissionsIssue(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("permission denied")
            || lowercased.contains("operation not permitted")
            || lowercased.contains("not authorized")
            || lowercased.contains("access denied")
    }
}

enum RustTopBridgeLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "RustTopTahoe"

    static let snapshot = Logger(subsystem: subsystem, category: "SnapshotBridge")
    static let artifact = Logger(subsystem: subsystem, category: "ArtifactBridge")
}

enum RustTopBridgeErrorMessage {
    static func decodingMessage(for error: Error) -> String {
        if let schemaError = error as? SnapshotSchemaCompatibilityError {
            return schemaError.localizedDescription
        }

        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }

        switch decodingError {
        case .dataCorrupted(let context):
            return "Snapshot JSON is malformed at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "Snapshot JSON is missing required key '\(key.stringValue)' at \(codingPathDescription(context.codingPath))."
        case .typeMismatch(let type, let context):
            return "Snapshot JSON type mismatch for \(type) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Snapshot JSON is missing value for \(type) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return decodingError.localizedDescription
        }
    }

    private static func codingPathDescription(_ path: [CodingKey]) -> String {
        let components = path.map(\.stringValue).filter { !$0.isEmpty }
        return components.isEmpty ? "<root>" : components.joined(separator: ".")
    }
}
