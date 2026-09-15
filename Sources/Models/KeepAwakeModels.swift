import Foundation

enum KeepAwakeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case display

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .system:
            return L10n.keepAwakeModeSystem
        case .display:
            return L10n.keepAwakeModeDisplay
        }
    }
}

enum KeepAwakeDuration: String, Codable, CaseIterable, Identifiable, Sendable {
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case sixtyMinutes
    case oneHundredTwentyMinutes
    case indefinite

    var id: String {
        rawValue
    }

    var minutes: Int? {
        switch self {
        case .fiveMinutes:
            return 5
        case .fifteenMinutes:
            return 15
        case .thirtyMinutes:
            return 30
        case .sixtyMinutes:
            return 60
        case .oneHundredTwentyMinutes:
            return 120
        case .indefinite:
            return nil
        }
    }

    var duration: Duration? {
        minutes.map { .seconds($0 * 60) }
    }

    var timeInterval: TimeInterval? {
        minutes.map { TimeInterval($0 * 60) }
    }

    var displayName: String {
        switch self {
        case .fiveMinutes:
            return L10n.keepAwakeDurationFiveMinutes
        case .fifteenMinutes:
            return L10n.keepAwakeDurationFifteenMinutes
        case .thirtyMinutes:
            return L10n.keepAwakeDurationThirtyMinutes
        case .sixtyMinutes:
            return L10n.keepAwakeDurationSixtyMinutes
        case .oneHundredTwentyMinutes:
            return L10n.keepAwakeDurationOneHundredTwentyMinutes
        case .indefinite:
            return L10n.keepAwakeDurationIndefinite
        }
    }
}

struct KeepAwakeSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var mode: KeepAwakeMode
    var duration: KeepAwakeDuration

    static let `default` = KeepAwakeSettings(
        enabled: false,
        mode: .system,
        duration: .thirtyMinutes
    )
}

extension KeepAwakeSettings {
    private enum CodingKeys: String, CodingKey {
        case enabled
        case mode
        case duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? Self.default.enabled
        mode = try container.decodeIfPresent(KeepAwakeMode.self, forKey: .mode) ?? Self.default.mode
        duration = try container.decodeIfPresent(KeepAwakeDuration.self, forKey: .duration) ?? Self.default.duration
    }
}

struct KeepAwakeSession: Equatable, Sendable {
    let id: UUID
    let mode: KeepAwakeMode
    let duration: KeepAwakeDuration
    let startedAt: Date
    let expiresAt: Date?
}

enum KeepAwakeState: Equatable, Sendable {
    case idle
    case starting
    case active(KeepAwakeSession)
    case unavailable(String)

    var activeSession: KeepAwakeSession? {
        guard case let .active(session) = self else { return nil }
        return session
    }

    var isStartingOrActive: Bool {
        switch self {
        case .starting, .active:
            return true
        case .idle, .unavailable:
            return false
        }
    }

    var errorMessage: String? {
        guard case let .unavailable(message) = self else { return nil }
        return message
    }
}
