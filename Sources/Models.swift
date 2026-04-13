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

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case gingerCat = "ginger-cat"
    case mistBlue = "mist-blue"
    case graphiteAmber = "graphite-amber"
    case mossInk = "moss-ink"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gingerCat: return L10n.themeGingerCat
        case .mistBlue: return L10n.themeMistBlue
        case .graphiteAmber: return L10n.themeGraphiteAmber
        case .mossInk: return L10n.themeMossInk
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
    var theme: AppTheme

    private enum CodingKeys: String, CodingKey {
        case autoLaunch
        case showStatusItem
        case showDockIcon
        case hotkeyKeyCode
        case hotkeyModifiers
        case language
        case theme
    }

    init(
        autoLaunch: Bool,
        showStatusItem: Bool,
        showDockIcon: Bool,
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: UInt32,
        language: AppLanguage,
        theme: AppTheme
    ) {
        self.autoLaunch = autoLaunch
        self.showStatusItem = showStatusItem
        self.showDockIcon = showDockIcon
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.language = language
        self.theme = theme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoLaunch) ?? false
        showStatusItem = try container.decodeIfPresent(Bool.self, forKey: .showStatusItem) ?? true
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        hotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? 49
        hotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers) ?? 2048
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .gingerCat
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(autoLaunch, forKey: .autoLaunch)
        try container.encode(showStatusItem, forKey: .showStatusItem)
        try container.encode(showDockIcon, forKey: .showDockIcon)
        try container.encode(hotkeyKeyCode, forKey: .hotkeyKeyCode)
        try container.encode(hotkeyModifiers, forKey: .hotkeyModifiers)
        try container.encode(language, forKey: .language)
        try container.encode(theme, forKey: .theme)
    }

    static let `default` = AppSettings(
        autoLaunch: false,
        showStatusItem: true,
        showDockIcon: false,
        hotkeyKeyCode: 49,
        hotkeyModifiers: 2048,
        language: .system,
        theme: .gingerCat
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
