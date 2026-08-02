import Foundation

enum WhiteboardResourceBundle {
    static let bundle = find(in: .main) ?? .main

    static func find(in mainBundle: Bundle) -> Bundle? {
        let bundleName = "Meow_WhiteboardFeature.bundle"
        var candidateURLs: [URL] = []

        if let resourceURL = mainBundle.resourceURL {
            candidateURLs.append(resourceURL.appendingPathComponent(bundleName, isDirectory: true))
        }
        candidateURLs.append(mainBundle.bundleURL.appendingPathComponent(bundleName, isDirectory: true))

        // SwiftPM test resources are siblings of the generated .xctest bundle.
        if mainBundle.bundleURL.pathExtension == "xctest" {
            candidateURLs.append(
                mainBundle.bundleURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(bundleName, isDirectory: true)
            )
        }

        var visitedPaths: Set<String> = []
        for candidateURL in candidateURLs where visitedPaths.insert(candidateURL.path).inserted {
            if let bundle = Bundle(url: candidateURL) {
                return bundle
            }
        }
        return nil
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

@MainActor
enum WhiteboardLocalization {
    private static var activeBundle = WhiteboardResourceBundle.bundle

    static func setLanguage(code: String?) {
        guard let code,
              let path = WhiteboardResourceBundle.bundle.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            activeBundle = WhiteboardResourceBundle.bundle
            return
        }
        activeBundle = bundle
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: activeBundle, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    static func toolTitle(_ tool: WhiteboardTool) -> String {
        text("whiteboard.tool.\(tool.rawValue)")
    }
}
