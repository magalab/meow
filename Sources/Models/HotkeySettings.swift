import Foundation

struct HotkeySettings: Codable, Equatable, Sendable {
    var launcherKeyCode: UInt32
    var launcherModifiers: UInt32
    var finderKeyCode: UInt32
    var finderModifiers: UInt32
    var translateKeyCode: UInt32
    var translateModifiers: UInt32
    var textActionsKeyCode: UInt32
    var textActionsModifiers: UInt32

    static let `default` = HotkeySettings(
        launcherKeyCode: 49,
        launcherModifiers: 2048,
        finderKeyCode: 14,
        finderModifiers: 2048,
        translateKeyCode: 2,
        translateModifiers: 2048,
        textActionsKeyCode: 7,
        textActionsModifiers: 2048
    )
}
