import Foundation
import WhiteboardFeature

struct WhiteboardSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var idleVisibility: WhiteboardIdleVisibility
    var includeInCaptures: Bool
    var surfaceStyle: WhiteboardSurfaceStyle
    var guideStyle: WhiteboardGuideStyle
    var outputBackgroundStyle: WhiteboardOutputBackgroundStyle
    var editOpacity: Double
    var hotkeyKeyCode: UInt32
    var hotkeyModifiers: UInt32

    init(
        enabled: Bool,
        idleVisibility: WhiteboardIdleVisibility,
        includeInCaptures: Bool,
        surfaceStyle: WhiteboardSurfaceStyle,
        guideStyle: WhiteboardGuideStyle,
        outputBackgroundStyle: WhiteboardOutputBackgroundStyle,
        editOpacity: Double,
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: UInt32
    ) {
        self.enabled = enabled
        self.idleVisibility = idleVisibility
        self.includeInCaptures = includeInCaptures
        self.surfaceStyle = surfaceStyle
        self.guideStyle = guideStyle
        self.outputBackgroundStyle = outputBackgroundStyle
        self.editOpacity = editOpacity
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
    }

    static let `default` = WhiteboardSettings(
        enabled: false,
        idleVisibility: .hidden,
        includeInCaptures: true,
        surfaceStyle: .paper,
        guideStyle: .dots,
        outputBackgroundStyle: .transparent,
        editOpacity: 0.94,
        hotkeyKeyCode: 13,
        hotkeyModifiers: 2560
    )

    func normalized() -> WhiteboardSettings {
        var value = self
        value.editOpacity = min(1, max(0.2, editOpacity.isFinite ? editOpacity : Self.default.editOpacity))
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case idleVisibility
        case includeInCaptures
        case surfaceStyle
        case guideStyle
        case outputBackgroundStyle
        case backgroundStyle
        case editOpacity
        case hotkeyKeyCode
        case hotkeyModifiers
    }

    private enum LegacyBackgroundStyle: String, Codable {
        case clear
        case dots
        case grid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? Self.default.enabled
        idleVisibility = (try? container.decode(
            WhiteboardIdleVisibility.self,
            forKey: .idleVisibility
        )) ?? Self.default.idleVisibility
        includeInCaptures = (try? container.decode(
            Bool.self,
            forKey: .includeInCaptures
        )) ?? Self.default.includeInCaptures
        surfaceStyle = (try? container.decode(
            WhiteboardSurfaceStyle.self,
            forKey: .surfaceStyle
        )) ?? Self.default.surfaceStyle
        if let guide = try? container.decode(WhiteboardGuideStyle.self, forKey: .guideStyle) {
            guideStyle = guide
        } else if let legacy = try? container.decode(
            LegacyBackgroundStyle.self,
            forKey: .backgroundStyle
        ) {
            guideStyle = switch legacy {
            case .clear: .none
            case .dots: .dots
            case .grid: .grid
            }
        } else {
            guideStyle = Self.default.guideStyle
        }
        outputBackgroundStyle = (try? container.decode(
            WhiteboardOutputBackgroundStyle.self,
            forKey: .outputBackgroundStyle
        )) ?? Self.default.outputBackgroundStyle
        editOpacity = (try? container.decode(Double.self, forKey: .editOpacity))
            ?? Self.default.editOpacity
        hotkeyKeyCode = (try? container.decode(UInt32.self, forKey: .hotkeyKeyCode))
            ?? Self.default.hotkeyKeyCode
        hotkeyModifiers = (try? container.decode(UInt32.self, forKey: .hotkeyModifiers))
            ?? Self.default.hotkeyModifiers
        if hotkeyKeyCode == 13, hotkeyModifiers == 2304 {
            hotkeyModifiers = Self.default.hotkeyModifiers
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(idleVisibility, forKey: .idleVisibility)
        try container.encode(includeInCaptures, forKey: .includeInCaptures)
        try container.encode(surfaceStyle, forKey: .surfaceStyle)
        try container.encode(guideStyle, forKey: .guideStyle)
        try container.encode(outputBackgroundStyle, forKey: .outputBackgroundStyle)
        try container.encode(editOpacity, forKey: .editOpacity)
        try container.encode(hotkeyKeyCode, forKey: .hotkeyKeyCode)
        try container.encode(hotkeyModifiers, forKey: .hotkeyModifiers)
    }
}
