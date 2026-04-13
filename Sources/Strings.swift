import Foundation

/// Manages the active language bundle for runtime language switching.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    /// Incrementing token forces SwiftUI views with `.id(refreshToken)` to rebuild.
    @Published private(set) var refreshToken: Int = 0

    private(set) var bundle: Bundle = .main

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
                    if let path = self.findLprojPath(in: resourcesPath, for: code) {
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
               let path = self.findLprojPath(in: resourceBundlePath, for: code) {
                langBundle = Bundle(path: path)
            }
        }

        // Fallback: try Bundle.main
        if langBundle == nil, let path = Bundle.main.path(forResource: code, ofType: "lproj") {
            langBundle = Bundle(path: path)
        }

        if let langBundle = langBundle {
            self.bundle = langBundle
            NSLog("[Meow i18n] ✅ Loaded language bundle for: \(code)")
        } else {
            self.bundle = Bundle.main
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
    static var searchPlaceholder: String { loc("search.placeholder") }
    static var filterAll: String { loc("filter.all") }
    static var categoryApplication: String { loc("category.application") }
    static var launcherSectionCommands: String { loc("launcher.section.commands") }
    static var launcherSectionApplications: String { loc("launcher.section.applications") }

    // MARK: - Preferences
    static var prefsTitle: String { loc("prefs.title") }
    static var prefsSubtitle: String { loc("prefs.subtitle") }
    static var prefsSectionGeneral: String { loc("prefs.section.general") }
    static var prefsSectionAppearance: String { loc("prefs.section.appearance") }

    static var prefsAutoLaunchTitle: String { loc("prefs.autolaunch.title") }
    static var prefsAutoLaunchSubtitle: String { loc("prefs.autolaunch.subtitle") }
    static var prefsHotkeyTitle: String { loc("prefs.hotkey.title") }
    static var prefsHotkeySubtitle: String { loc("prefs.hotkey.subtitle") }
    static var prefsHotkeyRecording: String { loc("prefs.hotkey.recording") }
    static var prefsHotkeyRecordingHint: String { loc("prefs.hotkey.recording.hint") }
    static var prefsDockTitle: String { loc("prefs.dock.title") }
    static var prefsDockSubtitle: String { loc("prefs.dock.subtitle") }
    static var prefsMenuBarTitle: String { loc("prefs.menubar.title") }
    static var prefsMenuBarSubtitle: String { loc("prefs.menubar.subtitle") }
    static var prefsThemeTitle: String { loc("prefs.theme.title") }
    static var prefsThemeSubtitle: String { loc("prefs.theme.subtitle") }
    static var prefsLanguageTitle: String { loc("prefs.language.title") }
    static var prefsLanguageSubtitle: String { loc("prefs.language.subtitle") }
    static var quitMeow: String { loc("quit.meow") }
    static var langSystem: String { loc("lang.system") }
    static var themeGingerCat: String { loc("theme.ginger-cat") }
    static var themeMistBlue: String { loc("theme.mist-blue") }
    static var themeGraphiteAmber: String { loc("theme.graphite-amber") }
    static var themeMossInk: String { loc("theme.moss-ink") }

    // MARK: - Status bar menu
    static var menuOpen: String { loc("menu.open") }
    static var menuPreferences: String { loc("menu.preferences") }
    static var menuAutoLaunch: String { loc("menu.autolaunch") }
    static var menuDock: String { loc("menu.dock") }
    static var menuMenuBar: String { loc("menu.menubar") }

    // MARK: - Built-in commands
    static var cmdPreferencesTitle: String { loc("cmd.preferences.title") }
    static var cmdPreferencesSubtitle: String { loc("cmd.preferences.subtitle") }
    static var cmdQuitTitle: String { loc("cmd.quit.title") }
    static var cmdQuitSubtitle: String { loc("cmd.quit.subtitle") }

    // MARK: - Window
    static var windowPrefsTitle: String { loc("window.prefs.title") }

    // MARK: - Private
    private static func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: LanguageManager.shared.bundle, comment: "")
    }
}
