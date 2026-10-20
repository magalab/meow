import Foundation

struct AppearanceSettings: Codable, Equatable, Sendable {
    var language: AppLanguage
    var theme: AppTheme
    var dateIconStyle: DateIconStyle
    var dockIconStyle: DockIconStyle

    static let `default` = AppearanceSettings(
        language: .system,
        theme: .gingerCat,
        dateIconStyle: .pawPrint,
        dockIconStyle: .calendar
    )
}
