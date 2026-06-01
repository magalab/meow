import Foundation

enum DateIconStyle: String, Codable, CaseIterable, Identifiable {
    case outlinedDay
    case roundedOutlineDay
    case pawPrint
    case dayOnly
    case monthDay
    case weekdayDay
    case lunarDate

    static let allCases: [DateIconStyle] = [
        .pawPrint,
        .outlinedDay,
        .roundedOutlineDay,
        .dayOnly,
        .monthDay,
        .weekdayDay,
        .lunarDate,
    ]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .outlinedDay: return L10n.dateIconOutlinedDay
        case .roundedOutlineDay: return L10n.dateIconRoundedOutlineDay
        case .pawPrint: return L10n.dateIconPawPrint
        case .dayOnly: return L10n.dateIconDayOnly
        case .monthDay: return L10n.dateIconMonthDay
        case .weekdayDay: return L10n.dateIconWeekdayDay
        case .lunarDate: return L10n.dateIconLunarDate
        }
    }
}

enum DockIconStyle: String, Codable, CaseIterable, Identifiable {
    case `default`
    case calendar
    case flat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return L10n.dockIconDefault
        case .calendar: return L10n.dockIconCalendar
        case .flat: return L10n.dockIconFlat
        }
    }
}

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
    /// Key code for the translate-selection hotkey (default: 2 = kVK_ANSI_D).
    var translateHotkeyKeyCode: UInt32
    /// Carbon modifier flags for the translate-selection hotkey (default: 2048 = optionKey = ⌥D).
    var translateHotkeyModifiers: UInt32
    var language: AppLanguage
    var theme: AppTheme
    var dateIconStyle: DateIconStyle
    var dockIconStyle: DockIconStyle

    init(
        autoLaunch: Bool,
        clipboardHistoryEnabled: Bool,
        showStatusItem: Bool,
        showDockIcon: Bool,
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: UInt32,
        translateHotkeyKeyCode: UInt32,
        translateHotkeyModifiers: UInt32,
        language: AppLanguage,
        theme: AppTheme,
        dateIconStyle: DateIconStyle = .pawPrint,
        dockIconStyle: DockIconStyle = .calendar
    ) {
        self.autoLaunch = autoLaunch
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
        self.showStatusItem = showStatusItem
        self.showDockIcon = showDockIcon
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.translateHotkeyKeyCode = translateHotkeyKeyCode
        self.translateHotkeyModifiers = translateHotkeyModifiers
        self.language = language
        self.theme = theme
        self.dateIconStyle = dateIconStyle
        self.dockIconStyle = dockIconStyle
    }

    static let `default` = AppSettings(
        autoLaunch: false,
        clipboardHistoryEnabled: true,
        showStatusItem: true,
        showDockIcon: false,
        hotkeyKeyCode: 49,
        hotkeyModifiers: 2048,
        translateHotkeyKeyCode: 2,
        translateHotkeyModifiers: 2048,
        language: .system,
        theme: .gingerCat
    )
}
