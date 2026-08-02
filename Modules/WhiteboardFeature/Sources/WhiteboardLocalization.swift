import Foundation

@MainActor
enum WhiteboardLocalization {
    private static var activeBundle = Bundle.module

    static func setLanguage(code: String?) {
        guard let code,
              let path = Bundle.module.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            activeBundle = .module
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
