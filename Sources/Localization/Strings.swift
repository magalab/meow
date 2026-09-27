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
        if let bundle = localizedBundle(for: languageCode) {
            return LocalizationSnapshot(bundle: bundle, languageCode: languageCode)
        }
        return LocalizationSnapshot(bundle: Bundle.main, languageCode: languageCode)
    }

    /// Finds localized resources without touching SwiftPM's `Bundle.module`
    /// accessor. The generated accessor assumes the resource bundle sits next
    /// to the app bundle, while our DMG packaging keeps it in Contents/Resources.
    static func localizedBundle(for languageCode: String) -> Bundle? {
        let fileManager = FileManager.default
        let executableURL = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        let executableDirectory = executableURL.deletingLastPathComponent()
        let bundleNames = [
            "Meow_\(BuildEdition.productName).bundle",
            "Meow_Meow.bundle",
        ]
        let languageNames = [languageCode, languageCode.lowercased()]

        var containers: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            containers.append(resourceURL)
        }
        containers.append(Bundle.main.bundleURL)
        containers.append(executableDirectory)
        let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        containers.append(workingDirectory)
        var ancestor = executableDirectory
        for _ in 0 ..< 6 {
            ancestor.deleteLastPathComponent()
            containers.append(ancestor)
        }

        let buildDirectory = workingDirectory.appendingPathComponent(".build", isDirectory: true)
        if let enumerator = fileManager.enumerator(
            at: buildDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                guard bundleNames.contains(url.lastPathComponent),
                      (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                else { continue }
                containers.append(url.deletingLastPathComponent())
            }
        }

        var visited = Set<String>()
        for container in containers {
            let containerPath = container.standardizedFileURL.path
            guard visited.insert(containerPath).inserted else { continue }

            for bundleName in bundleNames {
                let resourceBundleURL = container.appendingPathComponent(bundleName)
                guard let resourceBundle = Bundle(url: resourceBundleURL) else { continue }
                let hasLocalization = languageNames.contains {
                    resourceBundle.path(forResource: $0, ofType: "lproj") != nil
                }
                guard hasLocalization else { continue }
                return resourceBundle
            }

            let localizedPath = languageNames
                .map { container.appendingPathComponent("\($0).lproj") }
                .first { fileManager.fileExists(atPath: $0.path) }
            if localizedPath != nil {
                if containerPath == Bundle.main.resourceURL?.standardizedFileURL.path ||
                    containerPath == Bundle.main.bundleURL.standardizedFileURL.path
                {
                    return Bundle.main
                }
                return Bundle(url: container)
            }
        }

        return nil
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

        let langBundle = LocalizationRuntime.localizedBundle(for: code)

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

}

/// Type-safe localized string lookup. All keys are defined in Localizable.strings.
/// Properties are computed dynamically to support runtime language switching.
enum L10n {
    static func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: LocalizationRuntime.bundle, comment: "")
    }
}
