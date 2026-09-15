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
            let bundleNames = ["Meow_\(BuildEdition.productName).bundle", "Meow_Meow.bundle"]
            for bundleName in bundleNames {
                let resourceBundlePath = (exeDir as NSString).appendingPathComponent(bundleName)
                if fileManager.fileExists(atPath: resourceBundlePath),
                   let path = findLprojPath(in: resourceBundlePath, for: code)
                {
                    langBundle = Bundle(path: path)
                    break
                }
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
    static func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: LanguageManager.shared.bundle, comment: "")
    }
}
