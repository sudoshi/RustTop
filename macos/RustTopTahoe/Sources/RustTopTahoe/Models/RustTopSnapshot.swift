import Foundation

struct RustTopSnapshot: Codable, Identifiable, Sendable {
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let kind: String
    let capturedAtUnix: UInt64
    let hostname: String
    let osName: String
    let osVersion: String
    let kernelVersion: String
    let uptimeSeconds: UInt64
    let cpuUsagePercent: Double
    let memory: MemorySnapshot
    let disks: [DiskSnapshot]
    let network: NetworkSnapshot
    let gpus: [GpuSnapshot]
    let batteries: [BatterySnapshot]
    let sensors: [SensorSnapshot]
    let launchdJobs: [LaunchdJobSnapshot]
    let processCount: Int
    let topProcesses: [ProcessSnapshot]
    let alerts: [AlertSnapshot]

    var id: UInt64 { capturedAtUnix }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case kind
        case capturedAtUnix = "captured_at_unix"
        case hostname
        case osName = "os_name"
        case osVersion = "os_version"
        case kernelVersion = "kernel_version"
        case uptimeSeconds = "uptime_seconds"
        case cpuUsagePercent = "cpu_usage_percent"
        case memory
        case disks
        case network
        case gpus
        case batteries
        case sensors
        case launchdJobs = "launchd_jobs"
        case processCount = "process_count"
        case topProcesses = "top_processes"
        case alerts
    }

    static let preview = RustTopSnapshot(
        schemaVersion: 1,
        kind: "system_snapshot",
        capturedAtUnix: UInt64(Date().timeIntervalSince1970),
        hostname: "Mac Studio",
        osName: "macOS",
        osVersion: "26.0",
        kernelVersion: "25.0.0",
        uptimeSeconds: 217_390,
        cpuUsagePercent: 42.4,
        memory: MemorySnapshot(
            total: 68_719_476_736,
            used: 39_492_354_048,
            available: 29_227_122_688,
            usagePercent: 57.5,
            swapTotal: 8_589_934_592,
            swapUsed: 1_021_820_928,
            swapUsagePercent: 11.9,
            appMemory: 22_900_000_000,
            wiredMemory: 9_800_000_000,
            compressedMemory: 2_600_000_000,
            fileCache: 9_200_000_000,
            pressurePercent: 51.4,
            pressureLevel: "normal"
        ),
        disks: [
            DiskSnapshot(
                mountPoint: "/",
                fsType: "apfs",
                used: 512_000_000_000,
                total: 1_000_000_000_000,
                available: 488_000_000_000,
                usagePercent: 51.2,
                readRate: 12_400_000,
                writeRate: 4_800_000
            )
        ],
        network: NetworkSnapshot(totalRxRate: 184_000, totalTxRate: 62_000),
        gpus: [
            GpuSnapshot(
                name: "Apple GPU",
                usagePercent: 31.0,
                vramUsed: 8_400_000_000,
                vramTotal: 16_000_000_000,
                temperature: 52.0,
                powerWatts: 18.4
            )
        ],
        batteries: [],
        sensors: [
            SensorSnapshot(label: "CPU Proximity", temperature: 54.0, critical: 100.0),
            SensorSnapshot(label: "GPU Proximity", temperature: 48.0, critical: 100.0)
        ],
        launchdJobs: [
            LaunchdJobSnapshot(
                label: "com.apple.WindowServer",
                domain: "System",
                kind: "Daemon",
                path: "/System/Library/LaunchDaemons/com.apple.WindowServer.plist",
                state: "Installed"
            ),
            LaunchdJobSnapshot(
                label: "com.example.rusttop.agent",
                domain: "User",
                kind: "Agent",
                path: "~/Library/LaunchAgents/com.example.rusttop.agent.plist",
                state: "Installed"
            )
        ],
        processCount: 436,
        topProcesses: [
            ProcessSnapshot(pid: 741, name: "WindowServer", cpuUsage: 14.2, memory: 421_000_000, status: "Run"),
            ProcessSnapshot(pid: 1342, name: "Xcode", cpuUsage: 9.8, memory: 2_120_000_000, status: "Sleep"),
            ProcessSnapshot(pid: 908, name: "RustTopTahoe", cpuUsage: 4.1, memory: 138_000_000, status: "Run")
        ],
        alerts: []
    )
}

extension RustTopSnapshot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)

        guard schemaVersion == Self.supportedSchemaVersion else {
            throw SnapshotSchemaCompatibilityError.unsupportedVersion(
                actual: schemaVersion,
                supported: Self.supportedSchemaVersion
            )
        }

        self.schemaVersion = schemaVersion
        kind = try container.decode(String.self, forKey: .kind)
        capturedAtUnix = try container.decode(UInt64.self, forKey: .capturedAtUnix)
        hostname = try container.decode(String.self, forKey: .hostname)
        osName = try container.decode(String.self, forKey: .osName)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        kernelVersion = try container.decode(String.self, forKey: .kernelVersion)
        uptimeSeconds = try container.decode(UInt64.self, forKey: .uptimeSeconds)
        cpuUsagePercent = try container.decode(Double.self, forKey: .cpuUsagePercent)
        memory = try container.decode(MemorySnapshot.self, forKey: .memory)
        disks = try container.decode([DiskSnapshot].self, forKey: .disks)
        network = try container.decode(NetworkSnapshot.self, forKey: .network)
        gpus = try container.decodeIfPresent([GpuSnapshot].self, forKey: .gpus) ?? []
        batteries = try container.decodeIfPresent([BatterySnapshot].self, forKey: .batteries) ?? []
        sensors = try container.decodeIfPresent([SensorSnapshot].self, forKey: .sensors) ?? []
        launchdJobs = try container.decodeIfPresent([LaunchdJobSnapshot].self, forKey: .launchdJobs) ?? []
        processCount = try container.decode(Int.self, forKey: .processCount)
        topProcesses = try container.decode([ProcessSnapshot].self, forKey: .topProcesses)
        alerts = try container.decodeIfPresent([AlertSnapshot].self, forKey: .alerts) ?? []
    }
}

enum SnapshotSchemaCompatibilityError: LocalizedError, Equatable, Sendable {
    case unsupportedVersion(actual: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let actual, let supported):
            return "RustTop snapshot schema version \(actual) is not supported. This app supports schema version \(supported)."
        }
    }
}

struct MemorySnapshot: Codable, Sendable {
    let total: UInt64
    let used: UInt64
    let available: UInt64
    let usagePercent: Double
    let swapTotal: UInt64
    let swapUsed: UInt64
    let swapUsagePercent: Double
    let appMemory: UInt64?
    let wiredMemory: UInt64?
    let compressedMemory: UInt64?
    let fileCache: UInt64?
    let pressurePercent: Double?
    let pressureLevel: String?

    enum CodingKeys: String, CodingKey {
        case total
        case used
        case available
        case usagePercent = "usage_percent"
        case swapTotal = "swap_total"
        case swapUsed = "swap_used"
        case swapUsagePercent = "swap_usage_percent"
        case appMemory = "app_memory"
        case wiredMemory = "wired_memory"
        case compressedMemory = "compressed_memory"
        case fileCache = "file_cache"
        case pressurePercent = "pressure_percent"
        case pressureLevel = "pressure_level"
    }
}

struct DiskSnapshot: Codable, Identifiable, Sendable {
    let mountPoint: String
    let fsType: String
    let used: UInt64
    let total: UInt64
    let available: UInt64
    let usagePercent: Double
    let readRate: UInt64
    let writeRate: UInt64

    var id: String { mountPoint }

    enum CodingKeys: String, CodingKey {
        case mountPoint = "mount_point"
        case fsType = "fs_type"
        case used
        case total
        case available
        case usagePercent = "usage_percent"
        case readRate = "read_rate"
        case writeRate = "write_rate"
    }
}

struct NetworkSnapshot: Codable, Sendable {
    let totalRxRate: UInt64
    let totalTxRate: UInt64

    enum CodingKeys: String, CodingKey {
        case totalRxRate = "total_rx_rate"
        case totalTxRate = "total_tx_rate"
    }
}

struct GpuSnapshot: Codable, Identifiable, Sendable {
    let name: String
    let usagePercent: Double
    let vramUsed: UInt64
    let vramTotal: UInt64
    let temperature: Double?
    let powerWatts: Double?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case usagePercent = "usage_percent"
        case vramUsed = "vram_used"
        case vramTotal = "vram_total"
        case temperature
        case powerWatts = "power_watts"
    }
}

struct BatterySnapshot: Codable, Identifiable, Sendable {
    let name: String
    let status: String
    let capacityPercent: Double?
    let healthPercent: Double?
    let cycleCount: UInt32?
    let powerSource: String?
    let adapterWatts: Double?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case capacityPercent = "capacity_percent"
        case healthPercent = "health_percent"
        case cycleCount = "cycle_count"
        case powerSource = "power_source"
        case adapterWatts = "adapter_watts"
    }
}

struct SensorSnapshot: Codable, Identifiable, Sendable {
    let label: String
    let temperature: Double?
    let critical: Double?

    var id: String { label }
}

struct LaunchdJobSnapshot: Codable, Identifiable, Sendable {
    let label: String
    let domain: String
    let kind: String
    let path: String
    let state: String

    var id: String { path }
}

struct ProcessSnapshot: Codable, Identifiable, Sendable {
    let pid: UInt32
    let name: String
    let cpuUsage: Double
    let memory: UInt64
    let status: String

    var id: UInt32 { pid }

    enum CodingKeys: String, CodingKey {
        case pid
        case name
        case cpuUsage = "cpu_usage"
        case memory
        case status
    }
}

struct AlertSnapshot: Codable, Identifiable, Sendable {
    let key: String
    let label: String
    let value: Double
    let threshold: Double
    let unit: AlertUnit
    let severity: AlertSeverity
    let activeSeconds: UInt64

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key
        case label
        case value
        case threshold
        case unit
        case severity
        case activeSeconds = "active_seconds"
    }
}

enum AlertSeverity: String, Codable, Sendable {
    case warning = "Warning"
    case critical = "Critical"
}

enum AlertUnit: String, Codable, Sendable {
    case percent = "Percent"
    case celsius = "Celsius"
}
