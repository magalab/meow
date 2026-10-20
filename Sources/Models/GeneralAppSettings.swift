import Foundation

struct GeneralAppSettings: Codable, Equatable, Sendable {
    var autoLaunch: Bool
    var showStatusItem: Bool
    var showDockIcon: Bool

    static let `default` = GeneralAppSettings(
        autoLaunch: false,
        showStatusItem: true,
        showDockIcon: false
    )
}
