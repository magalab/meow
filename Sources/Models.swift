import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L10n.langSystem
        case .english: return "English"
        case .chinese: return "中文"
        }
    }
}

struct AppSettings: Codable {
    var autoLaunch: Bool
    var showStatusItem: Bool
    var showDockIcon: Bool
    var hotkeyKeyCode: UInt32
    var hotkeyModifiers: UInt32
    var language: AppLanguage

    static let `default` = AppSettings(
        autoLaunch: false,
        showStatusItem: true,
        showDockIcon: false,
        hotkeyKeyCode: 49,
        hotkeyModifiers: 2048,
        language: .system
    )
}

struct AppEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleId: String?
    let url: URL
}

struct CommandEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let keywords: [String]
}

enum SearchItem: Identifiable, Hashable {
    case app(AppEntry)
    case command(CommandEntry)

    var id: String {
        switch self {
        case .app(let app):
            return "app:\(app.id)"
        case .command(let command):
            return "command:\(command.id)"
        }
    }

    var primaryText: String {
        switch self {
        case .app(let app):
            return app.name
        case .command(let command):
            return command.title
        }
    }

    var secondaryText: String {
        switch self {
        case .app:
            return L10n.categoryApplication
        case .command(let command):
            return command.subtitle
        }
    }

    var symbolName: String {
        switch self {
        case .app:
            return "app.fill"
        case .command(let command):
            if command.id == "meow.preferences" {
                return "slider.horizontal.3"
            }
            if command.id == "meow.quit" {
                return "power"
            }
            return "command"
        }
    }
}
