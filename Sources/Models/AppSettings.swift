import Foundation

enum DateIconStyle: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
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

enum DockIconStyle: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
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

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
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

enum AppTheme: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
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
    var appearance: AppearanceSettings
    var language: AppLanguage {
        get { appearance.language }
        set { appearance.language = newValue }
    }
    var theme: AppTheme {
        get { appearance.theme }
        set { appearance.theme = newValue }
    }
    var dateIconStyle: DateIconStyle {
        get { appearance.dateIconStyle }
        set { appearance.dateIconStyle = newValue }
    }
    var dockIconStyle: DockIconStyle {
        get { appearance.dockIconStyle }
        set { appearance.dockIconStyle = newValue }
    }
    var clipboard: ClipboardSettings
    var clipboardHistoryEnabled: Bool {
        get { clipboard.historyEnabled }
        set { clipboard.historyEnabled = newValue }
    }
    var clipboardShowImagePreviews: Bool {
        get { clipboard.showImagePreviews }
        set { clipboard.showImagePreviews = newValue }
    }
    var clipboardRetention: ClipboardRetention {
        get { clipboard.retention }
        set { clipboard.retention = newValue }
    }
    var clipboardDisabledAppBundleIDs: [String] {
        get { clipboard.disabledAppBundleIDs }
        set { clipboard.disabledAppBundleIDs = newValue }
    }
    var clipboardImageStorageLimitMB: Int {
        get { clipboard.imageStorageLimitMB }
        set { clipboard.imageStorageLimitMB = max(128, newValue) }
    }
    var showStatusItem: Bool
    var showDockIcon: Bool
    var hotkeyKeyCode: UInt32
    var hotkeyModifiers: UInt32
    /// Key code for the Finder hotkey (default: 14 = kVK_ANSI_E).
    var finderHotkeyKeyCode: UInt32
    /// Carbon modifier flags for the Finder hotkey (default: 2048 = optionKey = ⌥E).
    var finderHotkeyModifiers: UInt32
    /// Key code for the translate-selection hotkey (default: 2 = kVK_ANSI_D).
    var translateHotkeyKeyCode: UInt32
    /// Carbon modifier flags for the translate-selection hotkey (default: 2048 = optionKey = ⌥D).
    var translateHotkeyModifiers: UInt32
    /// Key code for the selected-text actions hotkey (default: 7 = kVK_ANSI_X).
    var textActionsHotkeyKeyCode: UInt32
    /// Carbon modifier flags for the selected-text actions hotkey (default: 2048 = optionKey = ⌥X).
    var textActionsHotkeyModifiers: UInt32
    var ai: AISettings
    var fileHosting: FileHostSettings
    var screenshot: ScreenshotSettings
    var recording: RecordingSettings
    var whiteboard: WhiteboardSettings
    var speech: SpeechSettings
    var healthReminder: HealthReminderSettings
    var keepAwake: KeepAwakeSettings
    var authenticator: AuthenticatorSettings
    var authenticatorEnabled: Bool {
        get { authenticator.enabled }
        set { authenticator.enabled = newValue }
    }
    var authenticatorICloudSyncEnabled: Bool {
        get { authenticator.iCloudSyncEnabled }
        set { authenticator.iCloudSyncEnabled = newValue }
    }
    var systemMonitor: SystemMonitorSettings
    var keystrokeVisualizer: KeystrokeVisualizerSettings
    var keystrokeVisualizerEnabled: Bool {
        get { keystrokeVisualizer.enabled }
        set { keystrokeVisualizer.enabled = newValue }
    }
    var keystrokeVisualizerShowModifierOnly: Bool {
        get { keystrokeVisualizer.showModifierOnly }
        set { keystrokeVisualizer.showModifierOnly = newValue }
    }
    var keystrokeVisualizerOverlayPosition: KeystrokeOverlayPosition {
        get { keystrokeVisualizer.overlayPosition }
        set { keystrokeVisualizer.overlayPosition = newValue }
    }
    var keystrokeVisualizerOverlayPoint: KeystrokeOverlayPoint? {
        get { keystrokeVisualizer.overlayPoint }
        set { keystrokeVisualizer.overlayPoint = newValue }
    }
    var keystrokeVisualizerStyle: KeystrokeOverlayStyle {
        get { keystrokeVisualizer.style }
        set { keystrokeVisualizer.style = newValue }
    }
    var keystrokeVisualizerDisplayDuration: KeystrokeDisplayDuration {
        get { keystrokeVisualizer.displayDuration }
        set { keystrokeVisualizer.displayDuration = newValue }
    }
    var keystrokeVisualizerCustomDisplayDuration: Double {
        get { keystrokeVisualizer.customDisplayDuration }
        set { keystrokeVisualizer.customDisplayDuration = newValue }
    }
    var keystrokeVisualizerOpacity: Double {
        get { keystrokeVisualizer.opacity }
        set { keystrokeVisualizer.opacity = newValue }
    }
    var keystrokeVisualizerHistoryCount: KeystrokeHistoryCount {
        get { keystrokeVisualizer.historyCount }
        set { keystrokeVisualizer.historyCount = newValue }
    }
    var keystrokeVisualizerDisplayMode: KeystrokeDisplayMode {
        get { keystrokeVisualizer.displayMode }
        set { keystrokeVisualizer.displayMode = newValue }
    }

    init(
        autoLaunch: Bool,
        clipboardHistoryEnabled: Bool,
        clipboardShowImagePreviews: Bool,
        clipboardRetention: ClipboardRetention = .threeMonths,
        clipboardDisabledAppBundleIDs: [String] = ["com.apple.keychainaccess", "com.apple.Passwords"],
        clipboardImageStorageLimitMB: Int = 512,
        showStatusItem: Bool,
        showDockIcon: Bool,
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: UInt32,
        finderHotkeyKeyCode: UInt32 = 14,
        finderHotkeyModifiers: UInt32 = 2048,
        translateHotkeyKeyCode: UInt32,
        translateHotkeyModifiers: UInt32,
        textActionsHotkeyKeyCode: UInt32 = 7,
        textActionsHotkeyModifiers: UInt32 = 2048,
        language: AppLanguage,
        theme: AppTheme,
        dateIconStyle: DateIconStyle = .pawPrint,
        dockIconStyle: DockIconStyle = .calendar,
        ai: AISettings = .default,
        fileHosting: FileHostSettings = .default,
        screenshot: ScreenshotSettings = .default,
        recording: RecordingSettings = .default,
        whiteboard: WhiteboardSettings = .default,
        speech: SpeechSettings = .default,
        healthReminder: HealthReminderSettings = .default,
        keepAwake: KeepAwakeSettings = .default,
        authenticatorEnabled: Bool = false,
        authenticatorICloudSyncEnabled: Bool = false,
        systemMonitor: SystemMonitorSettings = .default,
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
        self.appearance = AppearanceSettings(
            language: language,
            theme: theme,
            dateIconStyle: dateIconStyle,
            dockIconStyle: dockIconStyle
        )
        self.clipboard = ClipboardSettings(
            historyEnabled: clipboardHistoryEnabled,
            showImagePreviews: clipboardShowImagePreviews,
            retention: clipboardRetention,
            disabledAppBundleIDs: clipboardDisabledAppBundleIDs,
            imageStorageLimitMB: clipboardImageStorageLimitMB
        )
        self.showStatusItem = showStatusItem
        self.showDockIcon = showDockIcon
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.finderHotkeyKeyCode = finderHotkeyKeyCode
        self.finderHotkeyModifiers = finderHotkeyModifiers
        self.translateHotkeyKeyCode = translateHotkeyKeyCode
        self.translateHotkeyModifiers = translateHotkeyModifiers
        self.textActionsHotkeyKeyCode = textActionsHotkeyKeyCode
        self.textActionsHotkeyModifiers = textActionsHotkeyModifiers
        self.ai = ai
        self.fileHosting = fileHosting
        self.screenshot = screenshot
        self.recording = recording
        self.whiteboard = whiteboard
        self.speech = speech
        self.healthReminder = healthReminder
        self.keepAwake = keepAwake
        self.authenticator = AuthenticatorSettings(
            enabled: authenticatorEnabled,
            iCloudSyncEnabled: authenticatorICloudSyncEnabled
        )
        self.systemMonitor = systemMonitor.normalized
        self.keystrokeVisualizer = KeystrokeVisualizerSettings(
            enabled: keystrokeVisualizerEnabled,
            showModifierOnly: keystrokeVisualizerShowModifierOnly,
            overlayPosition: keystrokeVisualizerOverlayPosition,
            overlayPoint: keystrokeVisualizerOverlayPoint,
            style: keystrokeVisualizerStyle,
            displayDuration: keystrokeVisualizerDisplayDuration,
            customDisplayDuration: keystrokeVisualizerCustomDisplayDuration,
            opacity: keystrokeVisualizerOpacity,
            historyCount: keystrokeVisualizerHistoryCount,
            displayMode: keystrokeVisualizerDisplayMode
        )
    }

    static let `default` = AppSettings(
        autoLaunch: false,
        clipboardHistoryEnabled: true,
        clipboardShowImagePreviews: true,
        showStatusItem: true,
        showDockIcon: false,
        hotkeyKeyCode: 49,
        hotkeyModifiers: 2048,
        finderHotkeyKeyCode: 14,
        finderHotkeyModifiers: 2048,
        translateHotkeyKeyCode: 2,
        translateHotkeyModifiers: 2048,
        textActionsHotkeyKeyCode: 7,
        textActionsHotkeyModifiers: 2048,
        language: .system,
        theme: .gingerCat
    )
}

extension AppSettings {
    // The removed TTS keys are intentionally omitted. Keyed decoding ignores
    // those legacy values, and the next settings save drops them from disk.
    private enum CodingKeys: String, CodingKey {
        case autoLaunch
        case clipboardHistoryEnabled
        case clipboardShowImagePreviews
        case clipboardRetention
        case clipboardDisabledAppBundleIDs
        case clipboardImageStorageLimitMB
        case showStatusItem
        case showDockIcon
        case hotkeyKeyCode
        case hotkeyModifiers
        case finderHotkeyKeyCode
        case finderHotkeyModifiers
        case translateHotkeyKeyCode
        case translateHotkeyModifiers
        case textActionsHotkeyKeyCode
        case textActionsHotkeyModifiers
        case language
        case theme
        case dateIconStyle
        case dockIconStyle
        case ai
        case fileHosting
        case screenshot
        case recording
        case whiteboard
        case speech
        case healthReminder
        case keepAwake
        case authenticatorEnabled
        case authenticatorICloudSyncEnabled
        case systemMonitor
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
        clipboard = ClipboardSettings(
            historyEnabled: try container.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled)
                ?? ClipboardSettings.default.historyEnabled,
            showImagePreviews: try container.decodeIfPresent(Bool.self, forKey: .clipboardShowImagePreviews)
                ?? ClipboardSettings.default.showImagePreviews,
            retention: try container.decodeIfPresent(ClipboardRetention.self, forKey: .clipboardRetention)
                ?? ClipboardSettings.default.retention,
            disabledAppBundleIDs: try container.decodeIfPresent(
                [String].self,
                forKey: .clipboardDisabledAppBundleIDs
            ) ?? ClipboardSettings.default.disabledAppBundleIDs,
            imageStorageLimitMB: try container.decodeIfPresent(Int.self, forKey: .clipboardImageStorageLimitMB)
                ?? ClipboardSettings.default.imageStorageLimitMB
        )
        showStatusItem = try container.decodeIfPresent(Bool.self, forKey: .showStatusItem) ?? Self.default.showStatusItem
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? Self.default.showDockIcon
        hotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? Self.default.hotkeyKeyCode
        hotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers) ?? Self.default.hotkeyModifiers
        finderHotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .finderHotkeyKeyCode)
            ?? Self.default.finderHotkeyKeyCode
        finderHotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .finderHotkeyModifiers)
            ?? Self.default.finderHotkeyModifiers
        translateHotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .translateHotkeyKeyCode) ?? Self.default.translateHotkeyKeyCode
        translateHotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .translateHotkeyModifiers) ?? Self.default.translateHotkeyModifiers
        textActionsHotkeyKeyCode = try container.decodeIfPresent(
            UInt32.self,
            forKey: .textActionsHotkeyKeyCode
        ) ?? Self.default.textActionsHotkeyKeyCode
        textActionsHotkeyModifiers = try container.decodeIfPresent(
            UInt32.self,
            forKey: .textActionsHotkeyModifiers
        ) ?? Self.default.textActionsHotkeyModifiers
        appearance = AppearanceSettings(
            language: try container.decodeIfPresent(AppLanguage.self, forKey: .language)
                ?? AppearanceSettings.default.language,
            theme: try container.decodeIfPresent(AppTheme.self, forKey: .theme)
                ?? AppearanceSettings.default.theme,
            dateIconStyle: try container.decodeIfPresent(DateIconStyle.self, forKey: .dateIconStyle)
                ?? AppearanceSettings.default.dateIconStyle,
            dockIconStyle: try container.decodeIfPresent(DockIconStyle.self, forKey: .dockIconStyle)
                ?? AppearanceSettings.default.dockIconStyle
        )
        ai = try container.decodeIfPresent(AISettings.self, forKey: .ai) ?? Self.default.ai
        fileHosting = try container.decodeIfPresent(FileHostSettings.self, forKey: .fileHosting) ?? Self.default.fileHosting
        screenshot = try container.decodeIfPresent(
            ScreenshotSettings.self,
            forKey: .screenshot
        ) ?? Self.default.screenshot
        recording = try container.decodeIfPresent(
            RecordingSettings.self,
            forKey: .recording
        ) ?? Self.default.recording
        whiteboard = try container.decodeIfPresent(
            WhiteboardSettings.self,
            forKey: .whiteboard
        ) ?? Self.default.whiteboard
        speech = try container.decodeIfPresent(SpeechSettings.self, forKey: .speech) ?? Self.default.speech
        healthReminder = try container.decodeIfPresent(
            HealthReminderSettings.self,
            forKey: .healthReminder
        ) ?? Self.default.healthReminder
        keepAwake = try container.decodeIfPresent(
            KeepAwakeSettings.self,
            forKey: .keepAwake
        ) ?? Self.default.keepAwake
        authenticator = AuthenticatorSettings(
            enabled: try container.decodeIfPresent(Bool.self, forKey: .authenticatorEnabled)
                ?? AuthenticatorSettings.default.enabled,
            iCloudSyncEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .authenticatorICloudSyncEnabled
            ) ?? AuthenticatorSettings.default.iCloudSyncEnabled
        )
        systemMonitor = (try container.decodeIfPresent(
            SystemMonitorSettings.self,
            forKey: .systemMonitor
        ) ?? Self.default.systemMonitor).normalized
        let overlayPoint = try container.decodeIfPresent(
            KeystrokeOverlayPoint.self,
            forKey: .keystrokeVisualizerOverlayPoint
        ) ?? KeystrokeVisualizerSettings.default.overlayPoint
        let overlayPosition = try container.decodeIfPresent(
            KeystrokeOverlayPosition.self,
            forKey: .keystrokeVisualizerOverlayPosition
        ) ?? (overlayPoint == nil
            ? KeystrokeVisualizerSettings.default.overlayPosition
            : .custom)
        keystrokeVisualizer = KeystrokeVisualizerSettings(
            enabled: try container.decodeIfPresent(Bool.self, forKey: .keystrokeVisualizerEnabled)
                ?? KeystrokeVisualizerSettings.default.enabled,
            showModifierOnly: try container.decodeIfPresent(Bool.self, forKey: .keystrokeVisualizerShowModifierOnly)
                ?? KeystrokeVisualizerSettings.default.showModifierOnly,
            overlayPosition: overlayPosition,
            overlayPoint: overlayPoint,
            style: try container.decodeIfPresent(KeystrokeOverlayStyle.self, forKey: .keystrokeVisualizerStyle)
                ?? KeystrokeVisualizerSettings.default.style,
            displayDuration: try container.decodeIfPresent(
                KeystrokeDisplayDuration.self,
                forKey: .keystrokeVisualizerDisplayDuration
            ) ?? KeystrokeVisualizerSettings.default.displayDuration,
            customDisplayDuration: try container.decodeIfPresent(
                Double.self,
                forKey: .keystrokeVisualizerCustomDisplayDuration
            ) ?? KeystrokeVisualizerSettings.default.customDisplayDuration,
            opacity: try container.decodeIfPresent(Double.self, forKey: .keystrokeVisualizerOpacity)
                ?? KeystrokeVisualizerSettings.default.opacity,
            historyCount: try container.decodeIfPresent(
                KeystrokeHistoryCount.self,
                forKey: .keystrokeVisualizerHistoryCount
            ) ?? KeystrokeVisualizerSettings.default.historyCount,
            displayMode: try container.decodeIfPresent(
                KeystrokeDisplayMode.self,
                forKey: .keystrokeVisualizerDisplayMode
            ) ?? KeystrokeVisualizerSettings.default.displayMode
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(autoLaunch, forKey: .autoLaunch)
        try container.encode(clipboardHistoryEnabled, forKey: .clipboardHistoryEnabled)
        try container.encode(clipboardShowImagePreviews, forKey: .clipboardShowImagePreviews)
        try container.encode(clipboardRetention, forKey: .clipboardRetention)
        try container.encode(clipboardDisabledAppBundleIDs, forKey: .clipboardDisabledAppBundleIDs)
        try container.encode(clipboardImageStorageLimitMB, forKey: .clipboardImageStorageLimitMB)
        try container.encode(showStatusItem, forKey: .showStatusItem)
        try container.encode(showDockIcon, forKey: .showDockIcon)
        try container.encode(hotkeyKeyCode, forKey: .hotkeyKeyCode)
        try container.encode(hotkeyModifiers, forKey: .hotkeyModifiers)
        try container.encode(finderHotkeyKeyCode, forKey: .finderHotkeyKeyCode)
        try container.encode(finderHotkeyModifiers, forKey: .finderHotkeyModifiers)
        try container.encode(translateHotkeyKeyCode, forKey: .translateHotkeyKeyCode)
        try container.encode(translateHotkeyModifiers, forKey: .translateHotkeyModifiers)
        try container.encode(textActionsHotkeyKeyCode, forKey: .textActionsHotkeyKeyCode)
        try container.encode(textActionsHotkeyModifiers, forKey: .textActionsHotkeyModifiers)
        try container.encode(language, forKey: .language)
        try container.encode(theme, forKey: .theme)
        try container.encode(dateIconStyle, forKey: .dateIconStyle)
        try container.encode(dockIconStyle, forKey: .dockIconStyle)
        try container.encode(ai, forKey: .ai)
        try container.encode(fileHosting, forKey: .fileHosting)
        try container.encode(screenshot, forKey: .screenshot)
        try container.encode(recording, forKey: .recording)
        try container.encode(whiteboard, forKey: .whiteboard)
        try container.encode(speech, forKey: .speech)
        try container.encode(healthReminder, forKey: .healthReminder)
        try container.encode(keepAwake, forKey: .keepAwake)
        try container.encode(authenticatorEnabled, forKey: .authenticatorEnabled)
        try container.encode(authenticatorICloudSyncEnabled, forKey: .authenticatorICloudSyncEnabled)
        try container.encode(systemMonitor, forKey: .systemMonitor)
        try container.encode(keystrokeVisualizerEnabled, forKey: .keystrokeVisualizerEnabled)
        try container.encode(keystrokeVisualizerShowModifierOnly, forKey: .keystrokeVisualizerShowModifierOnly)
        try container.encode(keystrokeVisualizerOverlayPosition, forKey: .keystrokeVisualizerOverlayPosition)
        try container.encodeIfPresent(keystrokeVisualizerOverlayPoint, forKey: .keystrokeVisualizerOverlayPoint)
        try container.encode(keystrokeVisualizerStyle, forKey: .keystrokeVisualizerStyle)
        try container.encode(keystrokeVisualizerDisplayDuration, forKey: .keystrokeVisualizerDisplayDuration)
        try container.encode(keystrokeVisualizerCustomDisplayDuration, forKey: .keystrokeVisualizerCustomDisplayDuration)
        try container.encode(keystrokeVisualizerOpacity, forKey: .keystrokeVisualizerOpacity)
        try container.encode(keystrokeVisualizerHistoryCount, forKey: .keystrokeVisualizerHistoryCount)
        try container.encode(keystrokeVisualizerDisplayMode, forKey: .keystrokeVisualizerDisplayMode)
    }
}
