import Foundation

public enum SystemMonitorModule: String, Codable, CaseIterable, Hashable, Sendable {
    case cpu
    case memory
    case gpu
    case network
    case disk
    case power
    case thermal
}

public enum SystemMonitorStatusStyle: String, Codable, CaseIterable, Sendable {
    case icon
    case cpu
    case memory
    case cpuAndMemory
}

public enum SystemMonitorHistoryDuration: Int, Codable, CaseIterable, Sendable {
    case fiveMinutes = 300
    case tenMinutes = 600
}

public struct SystemMonitorConfiguration: Sendable, Equatable {
    public var updateInterval: TimeInterval
    public var historyDuration: TimeInterval
    public var enabledModules: Set<SystemMonitorModule>

    public init(
        updateInterval: TimeInterval = 2,
        historyDuration: TimeInterval = 300,
        enabledModules: Set<SystemMonitorModule> = Set(SystemMonitorModule.allCases)
    ) {
        self.updateInterval = min(max(updateInterval, 1), 30)
        self.historyDuration = min(max(historyDuration, 60), 1_800)
        self.enabledModules = enabledModules
    }

    public var historyCapacity: Int {
        max(30, Int(historyDuration / updateInterval))
    }
}

public enum SystemThermalPressure: String, Codable, Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical
}

public enum SystemMemoryPressureSource: String, Sendable, Equatable {
    case systemPressureLevel
    case usedMemoryRatioFallback
}

public struct SystemMetricsSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public var cpuUsage: Double?
    public var memoryUsedFraction: Double?
    public var memoryPressureFraction: Double?
    public var memoryPressureSource: SystemMemoryPressureSource?
    public var gpuUsageFraction: Double?
    public var gpuMemoryUsedBytes: UInt64?
    public var gpuMemoryTotalBytes: UInt64?
    public var networkDownloadBytesPerSecond: Double?
    public var networkUploadBytesPerSecond: Double?
    public var localIPAddresses: [String]?
    public var publicIPAddress: String?
    public var diskUsedFraction: Double?
    public var diskReadBytesPerSecond: Double?
    public var diskWriteBytesPerSecond: Double?
    public var batteryFraction: Double?
    public var batteryIsCharging: Bool?
    public var thermalPressure: SystemThermalPressure?
    public var cpuTemperatureCelsius: Double?

    public init(capturedAt: Date = Date()) {
        self.capturedAt = capturedAt
    }
}
