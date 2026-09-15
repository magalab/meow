import AppKit
import Foundation

final class AppDiscoveryService {
    private let manager = FileManager.default

    func discoverApplications() -> [AppEntry] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true),
            manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]

        var seen = Set<String>()
        var entries: [AppEntry] = []

        for root in roots {
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                let id = url.path
                guard !seen.contains(id) else { continue }
                seen.insert(id)

                let name = url.deletingPathExtension().lastPathComponent
                let lower = name.lowercased()
                if lower.contains("appintents") || lower.contains("widget") || lower.contains("extension") {
                    continue
                }

                let bundle = Bundle(url: url)
                let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? name

                entries.append(
                    AppEntry(
                        id: id,
                        name: displayName,
                        bundleId: bundle?.bundleIdentifier,
                        url: url
                    )
                )
            }
        }

        // Some macOS builds expose Safari via system-managed symlink paths.
        // Ensure Safari is discoverable even when directory enumeration misses it.
        if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            let safariID = safariURL.path
            if !seen.contains(safariID) {
                seen.insert(safariID)
                entries.append(
                    AppEntry(
                        id: safariID,
                        name: "Safari",
                        bundleId: "com.apple.Safari",
                        url: safariURL
                    )
                )
            }
        }

        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
