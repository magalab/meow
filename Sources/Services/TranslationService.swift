import AppKit
import Foundation

/// Captures text for translation.
///
/// Grabs the selected text from the frontmost app via the Accessibility API.
/// Falls back to a temporary copy operation when direct selection access is
/// unavailable, then restores the original pasteboard contents.
@MainActor
final class TranslationService: ObservableObject {
    @Published private(set) var pendingText: String = ""

    /// True when the last capture attempt found that AX permission is missing.
    @Published private(set) var axPermissionDenied: Bool = false

    private let capturer: any TranslationServiceCapturing

    init(capturer: any TranslationServiceCapturing = SystemTranslationServiceCapturing()) {
        self.capturer = capturer
    }

    /// Reads the current selection through Accessibility without changing the pasteboard.
    /// This is useful immediately before Meow activates its own launcher window.
    @discardableResult
    func captureViaAccessibility(promptForPermission: Bool = false) -> String {
        let trusted = capturer.isAccessibilityTrusted(promptForPermission: promptForPermission)
        axPermissionDenied = !trusted

        guard trusted else {
            pendingText = ""
            return ""
        }

        let trimmed = (capturer.captureSelectedTextViaAccessibility() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        pendingText = trimmed
        return trimmed
    }

    /// Captures text and stores it as `pendingText`.  Returns the captured text (may be empty).
    @discardableResult
    func capture() -> String {
        captureWithFallback(promptForPermission: true)
    }

    /// Captures the current selection through AX, falling back to a temporary copy operation.
    @discardableResult
    func captureWithFallback(promptForPermission: Bool = false) -> String {
        let trusted = capturer.isAccessibilityTrusted(promptForPermission: promptForPermission)
        axPermissionDenied = !trusted

        guard trusted else {
            pendingText = ""
            return ""
        }

        var text = capturer.captureSelectedTextViaAccessibility() ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = capturer.captureSelectedTextViaTemporaryCopy() ?? ""
            MeowLog.translation.debug(
                "Selection capture used temporary copy fallback: success=\(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, privacy: .public), length=\(text.count, privacy: .public)"
            )
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingText = trimmed
        return trimmed
    }
}
