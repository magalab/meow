import Foundation

/// Manages the active language bundle for runtime language switching.
final class LanguageManager: ObservableObject {
    nonisolated(unsafe) static let shared = LanguageManager()

    /// Incrementing token forces SwiftUI views with `.id(refreshToken)` to rebuild.
    @Published private(set) var refreshToken: Int = 0

    private(set) var bundle: Bundle = .main
    private(set) var currentLanguageCode: String = "en"

    private init() {
        // Initialize to default language
        apply(.system)
    }

    func apply(_ language: AppLanguage) {
        let code: String
        switch language {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            code = preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        case .english:
            code = "en"
        case .chinese:
            code = "zh-Hans"
        }

        var langBundle: Bundle? = nil

        // Find the app bundle and access its Resources directory
        let exePath = CommandLine.arguments[0]
        var searchPath = (exePath as NSString).deletingLastPathComponent

        // Walk up to find .app bundle (e.g., MyApp.app/Contents/MacOS/Meow)
        let fileManager = FileManager.default
        repeat {
            let appBundleDir = (searchPath as NSString).lastPathComponent
            if appBundleDir.hasSuffix(".app") {
                // Found app bundle, look in Contents/Resources
                let resourcesPath = (searchPath as NSString).appendingPathComponent("Contents/Resources")
                if fileManager.fileExists(atPath: resourcesPath) {
                    // Try to load from app bundle resources
                    if let path = findLprojPath(in: resourcesPath, for: code) {
                        langBundle = Bundle(path: path)
                    }
                }
                break
            }

            let parent = (searchPath as NSString).deletingLastPathComponent
            if parent == searchPath { break } // reached root
            searchPath = parent
        } while langBundle == nil

        // Fallback: look for resource bundle in executable directory (swift run case)
        if langBundle == nil {
            let exeDir = (exePath as NSString).deletingLastPathComponent
            let resourceBundlePath = (exeDir as NSString).appendingPathComponent("Meow_Meow.bundle")
            if fileManager.fileExists(atPath: resourceBundlePath),
               let path = findLprojPath(in: resourceBundlePath, for: code)
            {
                langBundle = Bundle(path: path)
            }
        }

        // Fallback: try Bundle.main
        if langBundle == nil, let path = Bundle.main.path(forResource: code, ofType: "lproj") {
            langBundle = Bundle(path: path)
        }

        currentLanguageCode = code

        if let langBundle = langBundle {
            bundle = langBundle
            NSLog("[Meow i18n] ✅ Loaded language bundle for: \(code)")
        } else {
            bundle = Bundle.main
            NSLog("[Meow i18n] ⚠ Could not load language bundle for \(code), using fallback")
        }

        refreshToken += 1
    }

    private func findLprojPath(in containerPath: String, for code: String) -> String? {
        let fileManager = FileManager.default

        // Try exact code (e.g., zh-Hans)
        let exactPath = (containerPath as NSString).appendingPathComponent("\(code).lproj")
        if fileManager.fileExists(atPath: exactPath) {
            return exactPath
        }

        // Try lowercase variant (e.g., zh-hans)
        let lowercaseCode = code.lowercased()
        let lowercasePath = (containerPath as NSString).appendingPathComponent("\(lowercaseCode).lproj")
        if fileManager.fileExists(atPath: lowercasePath) {
            return lowercasePath
        }

        return nil
    }
}

/// Type-safe localized string lookup. All keys are defined in Localizable.strings.
/// Properties are computed dynamically to support runtime language switching.
enum L10n {
    // MARK: - Launcher

    static var searchPlaceholder: String {
        loc("search.placeholder")
    }

    static var filterAll: String {
        loc("filter.all")
    }

    static var categoryApplication: String {
        loc("category.application")
    }

    static var categoryClipboard: String {
        loc("category.clipboard")
    }

    static var launcherSectionCommands: String {
        loc("launcher.section.commands")
    }

    static var launcherSectionApplications: String {
        loc("launcher.section.applications")
    }

    static var launcherSectionClipboard: String {
        loc("launcher.section.clipboard")
    }

    static var clipboardDelete: String {
        loc("clipboard.delete")
    }

    static var clipboardClearAll: String {
        loc("clipboard.clear.all")
    }

    static var clipboardClearAllTitle: String {
        loc("clipboard.clear.all.title")
    }

    static var clipboardClearAllMessage: String {
        loc("clipboard.clear.all.message")
    }

    static var clipboardTypeText: String {
        loc("clipboard.type.text")
    }

    static var clipboardTypeImage: String {
        loc("clipboard.type.image")
    }

    static var clipboardTypeFile: String {
        loc("clipboard.type.file")
    }

    static var clipboardTypeURL: String {
        loc("clipboard.type.url")
    }

    static var clipboardTypeAudio: String {
        loc("clipboard.type.audio")
    }

    // MARK: - Action Menu

    static var actionMenuOpen: String {
        loc("action.menu.open")
    }

    static var actionMenuShowInFinder: String {
        loc("action.menu.show.in.finder")
    }

    static var actionMenuCopyPath: String {
        loc("action.menu.copy.path")
    }

    static var actionMenuPaste: String {
        loc("action.menu.paste")
    }

    static var actionMenuCopy: String {
        loc("action.menu.copy")
    }

    static var actionMenuAskAI: String {
        loc("action.menu.ask.ai")
    }

    static var actionMenuDelete: String {
        loc("action.menu.delete")
    }

    static var actionMenuExecute: String {
        loc("action.menu.execute")
    }

    static var actionCancel: String {
        loc("action.cancel")
    }

    // MARK: - Preferences

    static var prefsTitle: String {
        loc("prefs.title")
    }

    static var prefsSubtitle: String {
        loc("prefs.subtitle")
    }

    static var prefsSectionGeneral: String {
        loc("prefs.section.general")
    }

    static var prefsSectionKeyboard: String {
        loc("prefs.section.keyboard")
    }

    static var prefsSectionSpeech: String {
        loc("prefs.section.speech")
    }

    static var prefsSectionHealth: String {
        loc("prefs.section.health")
    }

    static var prefsSectionAI: String {
        loc("prefs.section.ai")
    }

    static var prefsSectionDock: String {
        loc("prefs.section.dock")
    }

    static var prefsSectionAppearance: String {
        loc("prefs.section.appearance")
    }

    static var prefsSectionAbout: String {
        loc("prefs.section.about")
    }

    static var prefsAutoLaunchTitle: String {
        loc("prefs.autolaunch.title")
    }

    static var prefsAutoLaunchSubtitle: String {
        loc("prefs.autolaunch.subtitle")
    }

    static var prefsClipboardTitle: String {
        loc("prefs.clipboard.title")
    }

    static var prefsClipboardSubtitle: String {
        loc("prefs.clipboard.subtitle")
    }

    static var prefsHotkeyTitle: String {
        loc("prefs.hotkey.title")
    }

    static var prefsHotkeySubtitle: String {
        loc("prefs.hotkey.subtitle")
    }

    static var prefsHotkeyRecording: String {
        loc("prefs.hotkey.recording")
    }

    static var prefsHotkeyRecordingHint: String {
        loc("prefs.hotkey.recording.hint")
    }

    // MARK: - Speech Recognition

    static var speechEnabledTitle: String { loc("speech.enabled.title") }
    static var speechEnabledSubtitle: String { loc("speech.enabled.subtitle") }
    static var speechHotkeyTitle: String { loc("speech.hotkey.title") }
    static var speechHotkeySubtitle: String { loc("speech.hotkey.subtitle") }
    static var speechSoundTitle: String { loc("speech.sound.title") }
    static var speechSoundSubtitle: String { loc("speech.sound.subtitle") }
    static var speechModelSelectionTitle: String { loc("speech.model.selection.title") }
    static var speechModelTitle: String { loc("speech.model.title") }
    static var speechModelDescription: String { loc("speech.model.description") }
    static var speechModelSenseVoiceTitle: String { loc("speech.model.sensevoice.title") }
    static var speechModelSenseVoiceSubtitle: String { loc("speech.model.sensevoice.subtitle") }
    static var speechModelSenseVoiceDownloadConfirmTitle: String { loc("speech.model.sensevoice.download.confirm.title") }
    static var speechModelSenseVoiceDownloadConfirmMessage: String { loc("speech.model.sensevoice.download.confirm.message") }
    static var speechModelParakeetTitle: String { loc("speech.model.parakeet.title") }
    static var speechModelParakeetSubtitle: String { loc("speech.model.parakeet.subtitle") }
    static var speechModelParakeetDownloadConfirmTitle: String { loc("speech.model.parakeet.download.confirm.title") }
    static var speechModelParakeetDownloadConfirmMessage: String { loc("speech.model.parakeet.download.confirm.message") }
    static var speechModelNotInstalled: String { loc("speech.model.not.installed") }
    static var speechModelInstalled: String { loc("speech.model.installed") }
    static var speechModelDownloading: String { loc("speech.model.downloading") }
    static var speechModelDownload: String { loc("speech.model.download") }
    static var speechModelDownloadConfirmTitle: String { loc("speech.model.download.confirm.title") }
    static var speechModelDownloadConfirmMessage: String { loc("speech.model.download.confirm.message") }
    static var speechModelDelete: String { loc("speech.model.delete") }
    static var speechModelOpenFolder: String { loc("speech.model.open.folder") }
    static var speechModelChecksumFailed: String { loc("speech.model.checksum.failed") }
    static var speechModelDownloadFailed: String { loc("speech.model.download.failed") }
    static var speechPermissionTitle: String { loc("speech.permission.title") }
    static var speechPermissionRequest: String { loc("speech.permission.request") }
    static var speechPermissionOpen: String { loc("speech.permission.open") }
    static var speechPermissionGranted: String { loc("speech.permission.granted") }
    static var speechPermissionGrantedSubtitle: String { loc("speech.permission.granted.subtitle") }
    static var speechPermissionNotDetermined: String { loc("speech.permission.not.determined") }
    static var speechPermissionDenied: String { loc("speech.permission.denied") }
    static var speechRetentionTitle: String { loc("speech.retention.title") }
    static var speechRetentionSubtitle: String { loc("speech.retention.subtitle") }
    static var speechRetention7Days: String { loc("speech.retention.7") }
    static var speechRetention30Days: String { loc("speech.retention.30") }
    static var speechRetention90Days: String { loc("speech.retention.90") }
    static var speechRetentionForever: String { loc("speech.retention.forever") }
    static var speechHistoryTitle: String { loc("speech.history.title") }
    static var speechHistoryEmpty: String { loc("speech.history.empty") }
    static var speechHistoryCopy: String { loc("speech.history.copy") }
    static var speechHistoryCopied: String { loc("speech.history.copied") }
    static var speechHistoryCount: String { loc("speech.history.count") }
    static var speechHistoryOpenFolder: String { loc("speech.history.open.folder") }
    static var speechHistoryClear: String { loc("speech.history.clear") }
    static var speechHistoryClearTitle: String { loc("speech.history.clear.title") }
    static var speechHistoryClearMessage: String { loc("speech.history.clear.message") }
    static var speechOverlayRecording: String { loc("speech.overlay.recording") }
    static var speechOverlayTranscribing: String { loc("speech.overlay.transcribing") }
    static var speechOverlayPasted: String { loc("speech.overlay.pasted") }
    static var speechOverlayCopied: String { loc("speech.overlay.copied") }
    static var speechOverlayCopiedHint: String { loc("speech.overlay.copied.hint") }
    static var speechOverlayCancelled: String { loc("speech.overlay.cancelled") }
    static var speechOverlayNeedsModel: String { loc("speech.overlay.needs.model") }
    static var speechOverlayNeedsModelHint: String { loc("speech.overlay.needs.model.hint") }
    static var speechOverlayRequestingPermission: String { loc("speech.overlay.requesting.permission") }
    static var speechOverlayReleaseHint: String { loc("speech.overlay.release.hint") }
    static var speechOverlayCancelHint: String { loc("speech.overlay.cancel.hint") }
    static var speechRecordingFailed: String { loc("speech.error.recording.failed") }
    static var speechTooShort: String { loc("speech.error.too.short") }

    static var prefsDockTitle: String {
        loc("prefs.dock.title")
    }

    static var prefsDockSubtitle: String {
        loc("prefs.dock.subtitle")
    }

    static var prefsMenuBarTitle: String {
        loc("prefs.menubar.title")
    }

    static var prefsMenuBarSubtitle: String {
        loc("prefs.menubar.subtitle")
    }

    static var prefsDateIconTitle: String {
        loc("prefs.dateicon.title")
    }

    static var prefsDateIconSubtitle: String {
        loc("prefs.dateicon.subtitle")
    }

    static var dateIconOutlinedDay: String {
        loc("dateicon.outlinedday")
    }

    static var dateIconRoundedOutlineDay: String {
        loc("dateicon.roundedoutlineday")
    }

    static var dateIconPawPrint: String {
        loc("dateicon.pawprint")
    }

    static var dateIconDayOnly: String {
        loc("dateicon.dayonly")
    }

    static var dateIconMonthDay: String {
        loc("dateicon.monthday")
    }

    static var dateIconWeekdayDay: String {
        loc("dateicon.weekdayday")
    }

    static var dateIconLunarDate: String {
        loc("dateicon.lunardate")
    }

    static var prefsDockIconTitle: String {
        loc("prefs.dockicon.title")
    }

    static var prefsDockIconSubtitle: String {
        loc("prefs.dockicon.subtitle")
    }

    static var dockIconDefault: String {
        loc("dockicon.default")
    }

    static var dockIconCalendar: String {
        loc("dockicon.calendar")
    }

    static var dockIconFlat: String {
        loc("dockicon.flat")
    }

    static var prefsThemeTitle: String {
        loc("prefs.theme.title")
    }

    static var prefsThemeSubtitle: String {
        loc("prefs.theme.subtitle")
    }

    static var prefsHealthEnabledTitle: String {
        loc("prefs.health.enabled.title")
    }

    static var prefsHealthEnabledSubtitle: String {
        loc("prefs.health.enabled.subtitle")
    }

    static var prefsHealthTodayTitle: String {
        loc("prefs.health.today.title")
    }

    static var prefsHealthDurationTitle: String {
        loc("prefs.health.duration.title")
    }

    static var prefsHealthDurationSubtitle: String {
        loc("prefs.health.duration.subtitle")
    }

    static var prefsHealthGoalTitle: String {
        loc("prefs.health.goal.title")
    }

    static var prefsHealthGoalSubtitle: String {
        loc("prefs.health.goal.subtitle")
    }

    static var prefsHealthModeTitle: String {
        loc("prefs.health.mode.title")
    }

    static var prefsHealthModeSubtitle: String {
        loc("prefs.health.mode.subtitle")
    }

    static var prefsHealthActivityTitle: String {
        loc("prefs.health.activity.title")
    }

    static var prefsHealthActivitySubtitle: String {
        loc("prefs.health.activity.subtitle")
    }

    static var prefsHealthSoundTitle: String {
        loc("prefs.health.sound.title")
    }

    static var prefsHealthSoundSubtitle: String {
        loc("prefs.health.sound.subtitle")
    }

    static var healthBreakModeGentle: String {
        loc("health.break.mode.gentle")
    }

    static var healthBreakModeStrict: String {
        loc("health.break.mode.strict")
    }

    static var healthWorkMinutesValue: String {
        loc("health.work.minutes.value")
    }

    static var healthBreakSecondsValue: String {
        loc("health.break.seconds.value")
    }

    static var healthGoalValue: String {
        loc("health.goal.value")
    }

    static var prefsKeystrokeEnabledTitle: String {
        loc("prefs.keystroke.enabled.title")
    }

    static var prefsKeystrokeEnabledSubtitle: String {
        loc("prefs.keystroke.enabled.subtitle")
    }

    static var prefsKeystrokeModifierTitle: String {
        loc("prefs.keystroke.modifier.title")
    }

    static var prefsKeystrokeModifierSubtitle: String {
        loc("prefs.keystroke.modifier.subtitle")
    }

    static var prefsKeystrokeDisplayModeTitle: String {
        loc("prefs.keystroke.display.mode.title")
    }

    static var prefsKeystrokeDisplayModeSubtitle: String {
        loc("prefs.keystroke.display.mode.subtitle")
    }

    static var prefsKeystrokePermissionTitle: String {
        loc("prefs.keystroke.permission.title")
    }

    static var prefsKeystrokePermissionSubtitle: String {
        loc("prefs.keystroke.permission.subtitle")
    }

    static var prefsKeystrokePermissionOpen: String {
        loc("prefs.keystroke.permission.open")
    }

    static var prefsKeystrokeStyleTitle: String {
        loc("prefs.keystroke.style.title")
    }

    static var prefsKeystrokeStyleSubtitle: String {
        loc("prefs.keystroke.style.subtitle")
    }

    static var prefsKeystrokePositionTitle: String {
        loc("prefs.keystroke.position.title")
    }

    static var prefsKeystrokeDurationTitle: String {
        loc("prefs.keystroke.duration.title")
    }

    static var prefsKeystrokeDurationSubtitle: String {
        loc("prefs.keystroke.duration.subtitle")
    }

    static var prefsKeystrokePositionSubtitle: String {
        loc("prefs.keystroke.position.subtitle")
    }

    static var prefsKeystrokePositionReset: String {
        loc("prefs.keystroke.position.reset")
    }

    static var prefsKeystrokeOpacityTitle: String {
        loc("prefs.keystroke.opacity.title")
    }

    static var prefsKeystrokeOpacitySubtitle: String {
        loc("prefs.keystroke.opacity.subtitle")
    }

    static var prefsKeystrokeHistoryCountTitle: String {
        loc("prefs.keystroke.history.count.title")
    }

    static var prefsKeystrokeHistoryCountSubtitle: String {
        loc("prefs.keystroke.history.count.subtitle")
    }

    static var keystrokeStyleCompact: String {
        loc("keystroke.style.compact")
    }

    static var keystrokeStyleProminent: String {
        loc("keystroke.style.prominent")
    }

    static var keystrokeDurationShort: String {
        loc("keystroke.duration.short")
    }

    static var keystrokeDurationNormal: String {
        loc("keystroke.duration.normal")
    }

    static var keystrokeDurationLong: String {
        loc("keystroke.duration.long")
    }

    static var keystrokeDurationPersistent: String {
        loc("keystroke.duration.persistent")
    }

    static var keystrokeDurationCustom: String {
        loc("keystroke.duration.custom")
    }

    static var keystrokePositionBottomCenter: String {
        loc("keystroke.position.bottom-center")
    }

    static var keystrokePositionTopCenter: String {
        loc("keystroke.position.top-center")
    }

    static var keystrokePositionBottomLeft: String {
        loc("keystroke.position.bottom-left")
    }

    static var keystrokePositionBottomRight: String {
        loc("keystroke.position.bottom-right")
    }

    static var keystrokePositionTopLeft: String {
        loc("keystroke.position.top-left")
    }

    static var keystrokePositionTopRight: String {
        loc("keystroke.position.top-right")
    }

    static var keystrokePositionCustom: String {
        loc("keystroke.position.custom")
    }

    static var keystrokeHistoryCountOne: String {
        loc("keystroke.history.count.one")
    }

    static var keystrokeHistoryCountTwo: String {
        loc("keystroke.history.count.two")
    }

    static var keystrokeHistoryCountThree: String {
        loc("keystroke.history.count.three")
    }

    static var keystrokeDisplayModeShortcutsAndSpecial: String {
        loc("keystroke.display.mode.shortcuts-special")
    }

    static var keystrokeDisplayModeShortcutsOnly: String {
        loc("keystroke.display.mode.shortcuts-only")
    }

    static var keystrokeDisplayModeAllKeys: String {
        loc("keystroke.display.mode.all-keys")
    }

    static var prefsLanguageTitle: String {
        loc("prefs.language.title")
    }

    static var prefsLanguageSubtitle: String {
        loc("prefs.language.subtitle")
    }

    static var prefsAIEndpointTitle: String {
        loc("prefs.ai.endpoint.title")
    }

    static var prefsAIEndpointSubtitle: String {
        loc("prefs.ai.endpoint.subtitle")
    }

    static var prefsAIKeyTitle: String {
        loc("prefs.ai.key.title")
    }

    static var prefsAIKeySubtitle: String {
        loc("prefs.ai.key.subtitle")
    }

    static var prefsAIKeyCopy: String {
        loc("prefs.ai.key.copy")
    }

    static var prefsAIKeyReveal: String {
        loc("prefs.ai.key.reveal")
    }

    static var prefsAIKeyHide: String {
        loc("prefs.ai.key.hide")
    }

    static var prefsAIModelTitle: String {
        loc("prefs.ai.model.title")
    }

    static var prefsAIModelSubtitle: String {
        loc("prefs.ai.model.subtitle")
    }

    static var prefsAIModelChoose: String {
        loc("prefs.ai.model.choose")
    }

    static var prefsAIModelsRefresh: String {
        loc("prefs.ai.models.refresh")
    }

    static var prefsAIModelsEmpty: String {
        loc("prefs.ai.models.empty")
    }

    static var prefsAIModelsLoaded: String {
        loc("prefs.ai.models.loaded")
    }

    static var prefsAIHistoryTitle: String {
        loc("prefs.ai.history.title")
    }

    static var prefsAIHistorySubtitle: String {
        loc("prefs.ai.history.subtitle")
    }

    static var prefsAIHistoryClear: String {
        loc("prefs.ai.history.clear")
    }

    static var prefsAIHistoryClearTitle: String {
        loc("prefs.ai.history.clear.title")
    }

    static var prefsAIHistoryClearMessage: String {
        loc("prefs.ai.history.clear.message")
    }

    static var prefsAIHistoryOpenFolder: String {
        loc("prefs.ai.history.open.folder")
    }

    static var prefsAboutVersion: String {
        loc("prefs.about.version")
    }

    static var prefsAboutBuild: String {
        loc("prefs.about.build")
    }

    static var prefsAboutPrivacy: String {
        loc("prefs.about.privacy")
    }

    static var prefsAboutPrivacySubtitle: String {
        loc("prefs.about.privacy.subtitle")
    }

    static var prefsAboutRepo: String {
        loc("prefs.about.repo")
    }

    static var prefsAboutOpenRepo: String {
        loc("prefs.about.open.repo")
    }

    static var quitMeow: String {
        loc("quit.meow")
    }

    static var langSystem: String {
        loc("lang.system")
    }

    static var themeGingerCat: String {
        loc("theme.ginger-cat")
    }

    static var themeMistBlue: String {
        loc("theme.mist-blue")
    }

    static var themeGraphiteAmber: String {
        loc("theme.graphite-amber")
    }

    static var themeMossInk: String {
        loc("theme.moss-ink")
    }

    // MARK: - Status bar menu

    static var menuOpen: String {
        loc("menu.open")
    }

    static var menuPreferences: String {
        loc("menu.preferences")
    }

    static var menuCalendar: String {
        loc("menu.calendar")
    }

    static var menuIconStyle: String {
        loc("menu.iconstyle")
    }

    static var calendarEventsTitle: String {
        loc("calendar.events.title")
    }

    static var calendarEventsEmpty: String {
        loc("calendar.events.empty")
    }

    static var calendarEventsLoading: String {
        loc("calendar.events.loading")
    }

    static var calendarEventsDenied: String {
        loc("calendar.events.denied")
    }

    static var calendarEventsRestricted: String {
        loc("calendar.events.restricted")
    }

    static var calendarEventsError: String {
        loc("calendar.events.error")
    }

    static var calendarAllDay: String {
        loc("calendar.events.allday")
    }

    static var menuAutoLaunch: String {
        loc("menu.autolaunch")
    }

    static var menuDock: String {
        loc("menu.dock")
    }

    static var menuMenuBar: String {
        loc("menu.menubar")
    }

    static var menuHealthStart: String {
        loc("menu.health.start")
    }

    static var menuHealthPause: String {
        loc("menu.health.pause")
    }

    static var menuHealthResume: String {
        loc("menu.health.resume")
    }

    static var menuHealthStartBreak: String {
        loc("menu.health.start.break")
    }

    static var menuHealthSettings: String {
        loc("menu.health.settings")
    }

    static var healthStatusIdle: String {
        loc("health.status.idle")
    }

    static var healthStatusWorking: String {
        loc("health.status.working")
    }

    static var healthStatusBreakReady: String {
        loc("health.status.break.ready")
    }

    static var healthStatusBreaking: String {
        loc("health.status.breaking")
    }

    static var healthStatusActivityPaused: String {
        loc("health.status.activity.paused")
    }

    static var healthStatusPaused: String {
        loc("health.status.paused")
    }

    // MARK: - Built-in commands

    static var cmdPreferencesTitle: String {
        loc("cmd.preferences.title")
    }

    static var cmdPreferencesSubtitle: String {
        loc("cmd.preferences.subtitle")
    }

    static var cmdAIChatTitle: String {
        loc("cmd.ai.chat.title")
    }

    static var cmdAIChatSubtitle: String {
        loc("cmd.ai.chat.subtitle")
    }

    static var cmdHealthStartTitle: String {
        loc("cmd.health.start.title")
    }

    static var cmdHealthStartSubtitle: String {
        loc("cmd.health.start.subtitle")
    }

    static var cmdHealthPauseTitle: String {
        loc("cmd.health.pause.title")
    }

    static var cmdHealthPauseSubtitle: String {
        loc("cmd.health.pause.subtitle")
    }

    static var cmdHealthBreakTitle: String {
        loc("cmd.health.break.title")
    }

    static var cmdHealthBreakSubtitle: String {
        loc("cmd.health.break.subtitle")
    }

    static var cmdHealthSkipTitle: String {
        loc("cmd.health.skip.title")
    }

    static var cmdHealthSkipSubtitle: String {
        loc("cmd.health.skip.subtitle")
    }

    static var cmdQuitTitle: String {
        loc("cmd.quit.title")
    }

    static var cmdQuitSubtitle: String {
        loc("cmd.quit.subtitle")
    }

    // MARK: - Window

    static var windowPrefsTitle: String {
        loc("window.prefs.title")
    }

    // MARK: - Translation panel

    static var translateTitle: String {
        loc("translate.title")
    }

    static var translateTranslating: String {
        loc("translate.translating")
    }

    static var translateNoSelection: String {
        loc("translate.no.selection")
    }

    static var translateDismiss: String {
        loc("translate.dismiss")
    }

    static var translateNeedAccessibility: String {
        loc("translate.need.accessibility")
    }

    // MARK: - Health reminder

    static var healthBreakReadyTitle: String {
        loc("health.break.ready.title")
    }

    static var healthBreakingTitle: String {
        loc("health.breaking.title")
    }

    static var healthTodayProgress: String {
        loc("health.today.progress")
    }

    static var healthSkippedToday: String {
        loc("health.skipped.today")
    }

    static var healthBreakReadyMessage: String {
        loc("health.break.ready.message")
    }

    static var healthBreakingMessage: String {
        loc("health.breaking.message")
    }

    static var healthActivityPausedMessage: String {
        loc("health.activity.paused.message")
    }

    static var healthStartBreak: String {
        loc("health.start.break")
    }

    static var healthDoneBreak: String {
        loc("health.done.break")
    }

    static var healthSkipBreak: String {
        loc("health.skip.break")
    }

    static var translateOpenPrivacy: String {
        loc("translate.open.privacy")
    }

    static var translateCopy: String {
        loc("translate.copy")
    }

    static var translateCopied: String {
        loc("translate.copied")
    }

    static var prefsTranslateHotkeyTitle: String {
        loc("prefs.translate.hotkey.title")
    }

    static var prefsTranslateHotkeySubtitle: String {
        loc("prefs.translate.hotkey.subtitle")
    }

    // MARK: - AI chat

    static var aiChatTitle: String {
        loc("ai.chat.title")
    }

    static var aiChatNoModel: String {
        loc("ai.chat.no.model")
    }

    static var aiChatHistoryTitle: String {
        loc("ai.chat.history.title")
    }

    static var aiChatHistoryEmpty: String {
        loc("ai.chat.history.empty")
    }

    static var aiChatNewConversation: String {
        loc("ai.chat.new.conversation")
    }

    static var aiChatDeleteConversation: String {
        loc("ai.chat.delete.conversation")
    }

    static var aiChatUntitledConversation: String {
        loc("ai.chat.untitled.conversation")
    }

    static var aiChatNotConfiguredTitle: String {
        loc("ai.chat.not.configured.title")
    }

    static var aiChatNotConfiguredSubtitle: String {
        loc("ai.chat.not.configured.subtitle")
    }

    static var aiChatOpenSettings: String {
        loc("ai.chat.open.settings")
    }

    static var aiChatEmptyTitle: String {
        loc("ai.chat.empty.title")
    }

    static var aiChatEmptySubtitle: String {
        loc("ai.chat.empty.subtitle")
    }

    static var aiChatInputPlaceholder: String {
        loc("ai.chat.input.placeholder")
    }

    static var aiChatYou: String {
        loc("ai.chat.you")
    }

    static var aiChatAssistant: String {
        loc("ai.chat.assistant")
    }

    static var aiChatCopy: String {
        loc("ai.chat.copy")
    }

    static var aiChatThinking: String {
        loc("ai.chat.thinking")
    }

    static var aiChatThinkingSection: String {
        loc("ai.chat.thinking.section")
    }

    static var aiChatPrivacyHint: String {
        loc("ai.chat.privacy.hint")
    }

    static var aiChatSend: String {
        loc("ai.chat.send")
    }

    static var aiClipboardPrompt: String {
        loc("ai.clipboard.prompt")
    }

    static var aiErrorNotConfigured: String {
        loc("ai.error.not.configured")
    }

    static var aiErrorInvalidEndpoint: String {
        loc("ai.error.invalid.endpoint")
    }

    static var aiErrorEmptyResponse: String {
        loc("ai.error.empty.response")
    }

    // MARK: - Private

    private static func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: LanguageManager.shared.bundle, comment: "")
    }
}
