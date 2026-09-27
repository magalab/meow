import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@Test("Translation service stores trimmed Accessibility selections")
@MainActor
func translationServiceCapturesAccessibilitySelection() {
    let capturer = TestTranslationServiceCapturing()
    capturer.accessibilityText = "  selected text  "
    let service = TranslationService(capturer: capturer)

    #expect(service.captureViaAccessibility() == "selected text")
    #expect(service.pendingText == "selected text")
    #expect(!service.axPermissionDenied)
    #expect(capturer.temporaryCopyCallCount == 0)
}

@Test("Translation service falls back to temporary copy when Accessibility selection is empty")
@MainActor
func translationServiceUsesTemporaryCopyFallback() {
    let capturer = TestTranslationServiceCapturing()
    capturer.accessibilityText = "  "
    capturer.temporaryCopyText = "  copied selection  "
    let service = TranslationService(capturer: capturer)

    #expect(service.captureWithFallback() == "copied selection")
    #expect(service.pendingText == "copied selection")
    #expect(capturer.temporaryCopyCallCount == 1)
}

@Test("Translation service clears state when Accessibility permission is unavailable")
@MainActor
func translationServiceHandlesMissingAccessibilityPermission() {
    let capturer = TestTranslationServiceCapturing()
    capturer.isTrusted = false
    let service = TranslationService(capturer: capturer)

    #expect(service.captureWithFallback(promptForPermission: true).isEmpty)
    #expect(service.pendingText.isEmpty)
    #expect(service.axPermissionDenied)
    #expect(capturer.accessibilityCallCount == 0)
    #expect(capturer.temporaryCopyCallCount == 0)
    #expect(capturer.lastPromptForPermission == true)
}

@MainActor
private final class TestTranslationServiceCapturing: TranslationServiceCapturing {
    var isTrusted = true
    var accessibilityText: String?
    var temporaryCopyText: String?
    var accessibilityCallCount = 0
    var temporaryCopyCallCount = 0
    var lastPromptForPermission: Bool?

    func isAccessibilityTrusted(promptForPermission: Bool) -> Bool {
        lastPromptForPermission = promptForPermission
        return isTrusted
    }

    func captureSelectedTextViaAccessibility() -> String? {
        accessibilityCallCount += 1
        return accessibilityText
    }

    func captureSelectedTextViaTemporaryCopy() -> String? {
        temporaryCopyCallCount += 1
        return temporaryCopyText
    }
}
