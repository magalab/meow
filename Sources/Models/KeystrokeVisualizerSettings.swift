import Foundation

struct KeystrokeVisualizerSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var showModifierOnly: Bool
    var overlayPosition: KeystrokeOverlayPosition
    var overlayPoint: KeystrokeOverlayPoint?
    var style: KeystrokeOverlayStyle
    var displayDuration: KeystrokeDisplayDuration
    var customDisplayDuration: Double
    var opacity: Double
    var historyCount: KeystrokeHistoryCount
    var displayMode: KeystrokeDisplayMode

    static let `default` = KeystrokeVisualizerSettings(
        enabled: false,
        showModifierOnly: true,
        overlayPosition: .bottomCenter,
        overlayPoint: nil,
        style: .compact,
        displayDuration: .normal,
        customDisplayDuration: 1.4,
        opacity: 0.82,
        historyCount: .one,
        displayMode: .shortcutsAndSpecialKeys
    )

    init(
        enabled: Bool,
        showModifierOnly: Bool,
        overlayPosition: KeystrokeOverlayPosition,
        overlayPoint: KeystrokeOverlayPoint?,
        style: KeystrokeOverlayStyle,
        displayDuration: KeystrokeDisplayDuration,
        customDisplayDuration: Double,
        opacity: Double,
        historyCount: KeystrokeHistoryCount,
        displayMode: KeystrokeDisplayMode
    ) {
        self.enabled = enabled
        self.showModifierOnly = showModifierOnly
        self.overlayPosition = overlayPosition
        self.overlayPoint = overlayPoint
        self.style = style
        self.displayDuration = displayDuration
        self.customDisplayDuration = customDisplayDuration
        self.opacity = opacity
        self.historyCount = historyCount
        self.displayMode = displayMode
    }
}
