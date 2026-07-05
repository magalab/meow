import AppKit
import Foundation

@MainActor
final class TextServiceProvider: NSObject {
    var onProcessText: ((String) -> Void)?

    @objc func processSelectedText(
        _ pasteboard: NSPasteboard,
        userData _: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = Self.selectedText(from: pasteboard) else {
            error.pointee = L10n.textActionsNoSelection as NSString
            return
        }

        onProcessText?(text)
    }

    static func selectedText(from pasteboard: NSPasteboard) -> String? {
        guard let value = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }
}
