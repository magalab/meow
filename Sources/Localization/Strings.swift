import Foundation
import os.lock

/// Manages the active language bundle for runtime language switching.
private struct LocalizationSnapshot: @unchecked Sendable {
    var bundle: Bundle
    var languageCode: String
}

private enum LocalizationRuntime {
    private static let snapshot = OSAllocatedUnfairLock(
        initialState: initialSnapshot()
    )

    private static func initialSnapshot() -> LocalizationSnapshot {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"
        let languageCode = preferredLanguage.hasPrefix("zh") ? "zh-Hans" : "en"
        if let path = Bundle.module.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path)
        {
            return LocalizationSnapshot(bundle: bundle, languageCode: languageCode)
        }
        return LocalizationSnapshot(bundle: Bundle.module, languageCode: languageCode)
    }

    static var bundle: Bundle {
        snapshot.withLock { $0.bundle }
    }

    static var languageCode: String {
        snapshot.withLock { $0.languageCode }
    }

    static func update(bundle: Bundle, languageCode: String) {
        snapshot.withLock {
            $0 = LocalizationSnapshot(bundle: bundle, languageCode: languageCode)
        }
    }
}

@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    /// Incrementing token forces SwiftUI views with `.id(refreshToken)` to rebuild.
    @Published private(set) var refreshToken: Int = 0

    var bundle: Bundle {
        LocalizationRuntime.bundle
    }

    var currentLanguageCode: String {
        LocalizationRuntime.languageCode
    }

    var isChinese: Bool {
        currentLanguageCode.hasPrefix("zh")
    }

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

        // SwiftPM test and `swift run` processes do not have an app bundle as
        // Bundle.main. Bundle.module points to the executable target's
        // processed resources in those environments.
        if langBundle == nil,
           let resourcesPath = Bundle.module.resourceURL?.path,
           let path = findLprojPath(in: resourcesPath, for: code)
        {
            langBundle = Bundle(path: path)
        }

        let resolvedBundle: Bundle
        if let langBundle = langBundle {
            resolvedBundle = langBundle
            MeowLog.localization.debug("Loaded language bundle for \(code, privacy: .public)")
        } else {
            resolvedBundle = Bundle.main
            MeowLog.localization.error("Could not load language bundle for \(code, privacy: .public); using fallback")
        }

        LocalizationRuntime.update(bundle: resolvedBundle, languageCode: code)
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
        NSLocalizedString(key, bundle: LocalizationRuntime.bundle, comment: "")
    }
}
