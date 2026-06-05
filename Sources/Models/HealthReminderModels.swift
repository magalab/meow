import Foundation

enum HealthReminderPhase: String, Codable, Equatable, Sendable {
    case idle
    case working
    case breakReady
    case breaking
    case paused
}

enum HealthBreakMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case gentle
    case strict

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .gentle: return L10n.healthBreakModeGentle
        case .strict: return L10n.healthBreakModeStrict
        }
    }
}

struct HealthReminderSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var workMinutes: Int
    var breakSeconds: Int
    var dailyGoal: Int
    var breakMode: HealthBreakMode
    var soundEnabled: Bool
    var activityDetectionEnabled: Bool

    static let `default` = HealthReminderSettings(
        enabled: false,
        workMinutes: 45,
        breakSeconds: 120,
        dailyGoal: 8,
        breakMode: .gentle,
        soundEnabled: false,
        activityDetectionEnabled: true
    )
}

extension HealthReminderSettings {
    private enum CodingKeys: String, CodingKey {
        case enabled
        case workMinutes
        case breakSeconds
        case dailyGoal
        case breakMode
        case soundEnabled
        case activityDetectionEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? Self.default.enabled
        workMinutes = try container.decodeIfPresent(Int.self, forKey: .workMinutes) ?? Self.default.workMinutes
        breakSeconds = try container.decodeIfPresent(Int.self, forKey: .breakSeconds) ?? Self.default.breakSeconds
        dailyGoal = try container.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? Self.default.dailyGoal
        breakMode = try container.decodeIfPresent(HealthBreakMode.self, forKey: .breakMode) ?? Self.default.breakMode
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? Self.default.soundEnabled
        activityDetectionEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .activityDetectionEnabled
        ) ?? Self.default.activityDetectionEnabled
    }
}

struct HealthReminderState: Equatable, Sendable {
    var phase: HealthReminderPhase
    var remainingSeconds: Int
    var completedBreaksToday: Int
    var skippedBreaksToday: Int
    var activityPaused: Bool
    var pausedFrom: HealthReminderPhase?

    static let idle = HealthReminderState(
        phase: .idle,
        remainingSeconds: 0,
        completedBreaksToday: 0,
        skippedBreaksToday: 0,
        activityPaused: false,
        pausedFrom: nil
    )
}

struct HealthReminderDayRecord: Codable, Equatable, Sendable {
    var date: String
    var completedBreaks: Int
    var skippedBreaks: Int
}

enum HealthReminderCommand: Equatable {
    case start
    case pauseResume
    case startBreak
    case skipBreak
}
