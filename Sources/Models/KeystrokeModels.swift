import Foundation

protocol KeystrokeDisplayNameProviding {
    var displayName: String { get }
}

enum KeystrokeOverlayStyle: String, Codable, CaseIterable, Identifiable, KeystrokeDisplayNameProviding {
    case compact
    case prominent

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .compact: return L10n.keystrokeStyleCompact
        case .prominent: return L10n.keystrokeStyleProminent
        }
    }
}

enum KeystrokeDisplayDuration: String, Codable, CaseIterable, Identifiable, KeystrokeDisplayNameProviding {
    case short
    case normal
    case long
    case persistent
    case custom

    var id: String {
        rawValue
    }

    func seconds(customSeconds: Double) -> TimeInterval {
        switch self {
        case .short: return 0.9
        case .normal: return 1.4
        case .long: return 2.5
        case .persistent: return 4.0
        case .custom: return min(max(customSeconds, 0.3), 10.0)
        }
    }

    var displayName: String {
        switch self {
        case .short: return L10n.keystrokeDurationShort
        case .normal: return L10n.keystrokeDurationNormal
        case .long: return L10n.keystrokeDurationLong
        case .persistent: return L10n.keystrokeDurationPersistent
        case .custom: return L10n.keystrokeDurationCustom
        }
    }
}

enum KeystrokeOverlayPosition: String, Codable, CaseIterable, Identifiable, KeystrokeDisplayNameProviding {
    case bottomCenter
    case topCenter
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight
    case custom

    static let allCases: [KeystrokeOverlayPosition] = [
        .bottomCenter,
        .topCenter,
        .bottomLeft,
        .bottomRight,
        .topLeft,
        .topRight,
        .custom,
    ]

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .bottomCenter: return L10n.keystrokePositionBottomCenter
        case .topCenter: return L10n.keystrokePositionTopCenter
        case .bottomLeft: return L10n.keystrokePositionBottomLeft
        case .bottomRight: return L10n.keystrokePositionBottomRight
        case .topLeft: return L10n.keystrokePositionTopLeft
        case .topRight: return L10n.keystrokePositionTopRight
        case .custom: return L10n.keystrokePositionCustom
        }
    }
}

enum KeystrokeHistoryCount: Int, Codable, CaseIterable, Identifiable, KeystrokeDisplayNameProviding {
    case one = 1
    case two = 2
    case three = 3

    var id: Int {
        rawValue
    }

    var displayName: String {
        switch self {
        case .one: return L10n.keystrokeHistoryCountOne
        case .two: return L10n.keystrokeHistoryCountTwo
        case .three: return L10n.keystrokeHistoryCountThree
        }
    }
}

enum KeystrokeDisplayMode: String, Codable, CaseIterable, Identifiable, KeystrokeDisplayNameProviding {
    case shortcutsAndSpecialKeys
    case shortcutsOnly
    case allKeys

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .shortcutsAndSpecialKeys: return L10n.keystrokeDisplayModeShortcutsAndSpecial
        case .shortcutsOnly: return L10n.keystrokeDisplayModeShortcutsOnly
        case .allKeys: return L10n.keystrokeDisplayModeAllKeys
        }
    }
}

struct KeystrokeOverlayPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
}

enum KeystrokePermissionState: Equatable {
    case unknown
    case trusted
    case denied
    case unavailable
}

struct KeystrokeDisplayItem: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let isModifierOnly: Bool
}
