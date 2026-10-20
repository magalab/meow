import Foundation

struct SystemMonitorSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var statusStyle: SystemMonitorStatusStyle
    var updateInterval: Double
    var historyDuration: SystemMonitorHistoryDuration
    var enabledModules: Set<SystemMonitorModule>

    static let `default` = SystemMonitorSettings(
        enabled: false,
        statusStyle: .icon,
        updateInterval: 2,
        historyDuration: .fiveMinutes,
        enabledModules: Set(SystemMonitorModule.allCases)
    )

    var normalized: SystemMonitorSettings {
        var copy = self
        copy.updateInterval = min(max(updateInterval, 1), 30)
        if copy.enabledModules.isEmpty {
            copy.enabledModules = Set(SystemMonitorModule.allCases)
        }
        return copy
    }

    var configuration: SystemMonitorConfiguration {
        SystemMonitorConfiguration(
            updateInterval: normalized.updateInterval,
            historyDuration: TimeInterval(normalized.historyDuration.rawValue),
            enabledModules: normalized.enabledModules
        )
    }

    init(
        enabled: Bool,
        statusStyle: SystemMonitorStatusStyle,
        updateInterval: Double,
        historyDuration: SystemMonitorHistoryDuration,
        enabledModules: Set<SystemMonitorModule>
    ) {
        self.enabled = enabled
        self.statusStyle = statusStyle
        self.updateInterval = updateInterval
        self.historyDuration = historyDuration
        self.enabledModules = enabledModules
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case statusStyle
        case updateInterval
        case historyDuration
        case enabledModules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? Self.default.enabled
        statusStyle = try container.decodeIfPresent(SystemMonitorStatusStyle.self, forKey: .statusStyle)
            ?? Self.default.statusStyle
        updateInterval = try container.decodeIfPresent(Double.self, forKey: .updateInterval)
            ?? Self.default.updateInterval
        historyDuration = try container.decodeIfPresent(SystemMonitorHistoryDuration.self, forKey: .historyDuration)
            ?? Self.default.historyDuration
        enabledModules = try container.decodeIfPresent(Set<SystemMonitorModule>.self, forKey: .enabledModules)
            ?? Self.default.enabledModules
    }
}
