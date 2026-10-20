import AppKit
import MeowCapture
import MeowRecording
@preconcurrency import ApplicationServices

@MainActor
struct AppMediaErrorPresenter {
    func presentRecordingError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.recordingErrorTitle
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.actionOK)
        if case .permissionDenied? = error as? RecordingError {
            alert.addButton(withTitle: L10n.screenshotOpenSettings)
        } else if case .cameraDenied? = error as? RecordingError {
            alert.addButton(withTitle: L10n.screenshotOpenSettings)
        }
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            let pane = if case .cameraDenied? = error as? RecordingError {
                "Privacy_Camera"
            } else {
                "Privacy_ScreenCapture"
            }
            openPrivacySettings(pane)
        }
    }

    func presentScrollingCaptureAccessibilityPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.scrollingCaptureAccessibilityTitle
        alert.informativeText = L10n.scrollingCaptureAccessibilityMessage
        alert.addButton(withTitle: L10n.screenshotOpenSettings)
        alert.addButton(withTitle: L10n.actionCancel)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if alert.runModal() == .alertFirstButtonReturn {
            openPrivacySettings("Privacy_Accessibility")
        }
    }

    func presentScrollingCaptureReducedImageWarning() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.scrollingCaptureReducedImageTitle
        alert.informativeText = L10n.scrollingCaptureReducedImageMessage
        alert.addButton(withTitle: L10n.actionOK)
        alert.runModal()
    }

    func presentScreenshotError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.screenshotErrorTitle
        if let captureError = error as? CaptureStoreError,
           case .imageEncodingFailed = captureError
        {
            alert.informativeText = L10n.screenshotErrorEncoding
        } else {
            alert.informativeText = error.localizedDescription
        }
        alert.addButton(withTitle: L10n.actionOK)
        if case .permissionDenied? = error as? ScreenCaptureError {
            alert.addButton(withTitle: L10n.screenshotOpenSettings)
        }
        if alert.runModal() == .alertSecondButtonReturn {
            openPrivacySettings("Privacy_ScreenCapture")
        }
    }

    func presentUploadError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.uploadErrorTitle
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.actionOK)
        alert.runModal()
    }

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
