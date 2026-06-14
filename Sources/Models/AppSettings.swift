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

struct AISettings: Codable, Equatable, Sendable {
    var endpoint: String
    var apiKey: String
    var model: String
    var systemPrompt: String
    var chatHistoryEnabled: Bool
    var supportsVision: Bool
    var imageMaxDimension: Int
    var imageJPEGQuality: Double

    var isConfigured: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let `default` = AISettings(
        endpoint: "https://api.openai.com/v1/chat/completions",
        apiKey: "",
        model: "gpt-4o-mini",
        systemPrompt: "You are a concise, helpful assistant inside a lightweight macOS launcher.",
        chatHistoryEnabled: true,
        supportsVision: true,
        imageMaxDimension: 1600,
        imageJPEGQuality: 0.82
    )
}

extension AISettings {
    private enum CodingKeys: String, CodingKey {
        case endpoint
        case apiKey
        case model
        case systemPrompt
        case chatHistoryEnabled
        case supportsVision
        case imageMaxDimension
        case imageJPEGQuality
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? Self.default.endpoint
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? Self.default.apiKey
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? Self.default.model
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? Self.default.systemPrompt
        chatHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .chatHistoryEnabled) ?? Self.default.chatHistoryEnabled
        supportsVision = try container.decodeIfPresent(
            Bool.self,
            forKey: .supportsVision
        ) ?? Self.default.supportsVision
        imageMaxDimension = try container.decodeIfPresent(
            Int.self,
            forKey: .imageMaxDimension
        ) ?? Self.default.imageMaxDimension
        imageJPEGQuality = try container.decodeIfPresent(
            Double.self,
            forKey: .imageJPEGQuality
        ) ?? Self.default.imageJPEGQuality
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
    var ai: AISettings
    var screenshot: ScreenshotSettings
    var speech: SpeechSettings
    var healthReminder: HealthReminderSettings
    var authenticatorEnabled: Bool
    var authenticatorICloudSyncEnabled: Bool
    var keystrokeVisualizerEnabled: Bool
    var keystrokeVisualizerShowModifierOnly: Bool
    var keystrokeVisualizerOverlayPosition: KeystrokeOverlayPosition
    var keystrokeVisualizerOverlayPoint: KeystrokeOverlayPoint?
    var keystrokeVisualizerStyle: KeystrokeOverlayStyle
    var keystrokeVisualizerDisplayDuration: KeystrokeDisplayDuration
    var keystrokeVisualizerCustomDisplayDuration: Double
    var keystrokeVisualizerOpacity: Double
    var keystrokeVisualizerHistoryCount: KeystrokeHistoryCount
    var keystrokeVisualizerDisplayMode: KeystrokeDisplayMode

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
        dockIconStyle: DockIconStyle = .calendar,
        ai: AISettings = .default,
        screenshot: ScreenshotSettings = .default,
        speech: SpeechSettings = .default,
        healthReminder: HealthReminderSettings = .default,
        authenticatorEnabled: Bool = false,
        authenticatorICloudSyncEnabled: Bool = false,
        keystrokeVisualizerEnabled: Bool = false,
        keystrokeVisualizerShowModifierOnly: Bool = true,
        keystrokeVisualizerOverlayPosition: KeystrokeOverlayPosition = .bottomCenter,
        keystrokeVisualizerOverlayPoint: KeystrokeOverlayPoint? = nil,
        keystrokeVisualizerStyle: KeystrokeOverlayStyle = .compact,
        keystrokeVisualizerDisplayDuration: KeystrokeDisplayDuration = .normal,
        keystrokeVisualizerCustomDisplayDuration: Double = 1.4,
        keystrokeVisualizerOpacity: Double = 0.82,
        keystrokeVisualizerHistoryCount: KeystrokeHistoryCount = .one,
        keystrokeVisualizerDisplayMode: KeystrokeDisplayMode = .shortcutsAndSpecialKeys
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
        self.ai = ai
        self.screenshot = screenshot
        self.speech = speech
        self.healthReminder = healthReminder
        self.authenticatorEnabled = authenticatorEnabled
        self.authenticatorICloudSyncEnabled = authenticatorICloudSyncEnabled
        self.keystrokeVisualizerEnabled = keystrokeVisualizerEnabled
        self.keystrokeVisualizerShowModifierOnly = keystrokeVisualizerShowModifierOnly
        self.keystrokeVisualizerOverlayPosition = keystrokeVisualizerOverlayPosition
        self.keystrokeVisualizerOverlayPoint = keystrokeVisualizerOverlayPoint
        self.keystrokeVisualizerStyle = keystrokeVisualizerStyle
        self.keystrokeVisualizerDisplayDuration = keystrokeVisualizerDisplayDuration
        self.keystrokeVisualizerCustomDisplayDuration = keystrokeVisualizerCustomDisplayDuration
        self.keystrokeVisualizerOpacity = keystrokeVisualizerOpacity
        self.keystrokeVisualizerHistoryCount = keystrokeVisualizerHistoryCount
        self.keystrokeVisualizerDisplayMode = keystrokeVisualizerDisplayMode
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

extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case autoLaunch
        case clipboardHistoryEnabled
        case showStatusItem
        case showDockIcon
        case hotkeyKeyCode
        case hotkeyModifiers
        case translateHotkeyKeyCode
        case translateHotkeyModifiers
        case language
        case theme
        case dateIconStyle
        case dockIconStyle
        case ai
        case screenshot
        case speech
        case healthReminder
        case authenticatorEnabled
        case authenticatorICloudSyncEnabled
        case keystrokeVisualizerEnabled
        case keystrokeVisualizerShowModifierOnly
        case keystrokeVisualizerOverlayPosition
        case keystrokeVisualizerOverlayPoint
        case keystrokeVisualizerStyle
        case keystrokeVisualizerDisplayDuration
        case keystrokeVisualizerCustomDisplayDuration
        case keystrokeVisualizerOpacity
        case keystrokeVisualizerHistoryCount
        case keystrokeVisualizerDisplayMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoLaunch) ?? Self.default.autoLaunch
        clipboardHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled) ?? Self.default.clipboardHistoryEnabled
        showStatusItem = try container.decodeIfPresent(Bool.self, forKey: .showStatusItem) ?? Self.default.showStatusItem
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? Self.default.showDockIcon
        hotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? Self.default.hotkeyKeyCode
        hotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers) ?? Self.default.hotkeyModifiers
        translateHotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .translateHotkeyKeyCode) ?? Self.default.translateHotkeyKeyCode
        translateHotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .translateHotkeyModifiers) ?? Self.default.translateHotkeyModifiers
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? Self.default.language
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? Self.default.theme
        dateIconStyle = try container.decodeIfPresent(DateIconStyle.self, forKey: .dateIconStyle) ?? Self.default.dateIconStyle
        dockIconStyle = try container.decodeIfPresent(DockIconStyle.self, forKey: .dockIconStyle) ?? Self.default.dockIconStyle
        ai = try container.decodeIfPresent(AISettings.self, forKey: .ai) ?? Self.default.ai
        screenshot = try container.decodeIfPresent(
            ScreenshotSettings.self,
            forKey: .screenshot
        ) ?? Self.default.screenshot
        speech = try container.decodeIfPresent(SpeechSettings.self, forKey: .speech) ?? Self.default.speech
        healthReminder = try container.decodeIfPresent(
            HealthReminderSettings.self,
            forKey: .healthReminder
        ) ?? Self.default.healthReminder
        authenticatorEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .authenticatorEnabled
        ) ?? Self.default.authenticatorEnabled
        authenticatorICloudSyncEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .authenticatorICloudSyncEnabled
        ) ?? Self.default.authenticatorICloudSyncEnabled
        keystrokeVisualizerEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .keystrokeVisualizerEnabled
        ) ?? Self.default.keystrokeVisualizerEnabled
        keystrokeVisualizerShowModifierOnly = try container.decodeIfPresent(
            Bool.self,
            forKey: .keystrokeVisualizerShowModifierOnly
        ) ?? Self.default.keystrokeVisualizerShowModifierOnly
        keystrokeVisualizerOverlayPoint = try container.decodeIfPresent(
            KeystrokeOverlayPoint.self,
            forKey: .keystrokeVisualizerOverlayPoint
        ) ?? Self.default.keystrokeVisualizerOverlayPoint
        keystrokeVisualizerOverlayPosition = try container.decodeIfPresent(
            KeystrokeOverlayPosition.self,
            forKey: .keystrokeVisualizerOverlayPosition
        ) ?? (keystrokeVisualizerOverlayPoint == nil ? Self.default.keystrokeVisualizerOverlayPosition : .custom)
        keystrokeVisualizerStyle = try container.decodeIfPresent(
            KeystrokeOverlayStyle.self,
            forKey: .keystrokeVisualizerStyle
        ) ?? Self.default.keystrokeVisualizerStyle
        keystrokeVisualizerDisplayDuration = try container.decodeIfPresent(
            KeystrokeDisplayDuration.self,
            forKey: .keystrokeVisualizerDisplayDuration
        ) ?? Self.default.keystrokeVisualizerDisplayDuration
        keystrokeVisualizerCustomDisplayDuration = try container.decodeIfPresent(
            Double.self,
            forKey: .keystrokeVisualizerCustomDisplayDuration
        ) ?? Self.default.keystrokeVisualizerCustomDisplayDuration
        keystrokeVisualizerOpacity = try container.decodeIfPresent(
            Double.self,
            forKey: .keystrokeVisualizerOpacity
        ) ?? Self.default.keystrokeVisualizerOpacity
        keystrokeVisualizerHistoryCount = try container.decodeIfPresent(
            KeystrokeHistoryCount.self,
            forKey: .keystrokeVisualizerHistoryCount
        ) ?? Self.default.keystrokeVisualizerHistoryCount
        keystrokeVisualizerDisplayMode = try container.decodeIfPresent(
            KeystrokeDisplayMode.self,
            forKey: .keystrokeVisualizerDisplayMode
        ) ?? Self.default.keystrokeVisualizerDisplayMode
    }
}
