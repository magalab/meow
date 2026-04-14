import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chinese = "zh-Hans"

    var id: String {
        rawValue
    }

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

    var id: String {
        rawValue
    }

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
    var clipboardHistoryEnabled: Bool
    var showStatusItem: Bool
    var showDockIcon: Bool
    var hotkeyKeyCode: UInt32
    var hotkeyModifiers: UInt32
    var language: AppLanguage
    var theme: AppTheme

    private enum CodingKeys: String, CodingKey {
        case autoLaunch
        case clipboardHistoryEnabled
        case showStatusItem
        case showDockIcon
        case hotkeyKeyCode
        case hotkeyModifiers
        case language
        case theme
    }

    init(
        autoLaunch: Bool,
        clipboardHistoryEnabled: Bool,
        showStatusItem: Bool,
        showDockIcon: Bool,
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: UInt32,
        language: AppLanguage,
        theme: AppTheme
    ) {
        self.autoLaunch = autoLaunch
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
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
        clipboardHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled) ?? true
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
        try container.encode(clipboardHistoryEnabled, forKey: .clipboardHistoryEnabled)
        try container.encode(showStatusItem, forKey: .showStatusItem)
        try container.encode(showDockIcon, forKey: .showDockIcon)
        try container.encode(hotkeyKeyCode, forKey: .hotkeyKeyCode)
        try container.encode(hotkeyModifiers, forKey: .hotkeyModifiers)
        try container.encode(language, forKey: .language)
        try container.encode(theme, forKey: .theme)
    }

    static let `default` = AppSettings(
        autoLaunch: false,
        clipboardHistoryEnabled: true,
        showStatusItem: true,
        showDockIcon: false,
        hotkeyKeyCode: 49,
        hotkeyModifiers: 2048,
        language: .system,
        theme: .gingerCat
    )
}
