import AppKit
import WhiteboardFeature

@MainActor
final class AppWhiteboardCoordinator {
    struct Actions {
        let settings: @MainActor () -> WhiteboardSettings
        let latestScreenshot: @MainActor () -> URL?
        let hideLauncher: @MainActor () -> Void
        let setRecordingWindowIDs: @MainActor (Set<CGWindowID>) -> Void
    }

    private let controller: WhiteboardFeatureController
    private let actions: Actions
    private var preparedForRecording = false

    init(controller: WhiteboardFeatureController, actions: Actions) {
        self.controller = controller
        self.actions = actions
    }

    func apply(_ settings: WhiteboardSettings) {
        let normalized = settings.normalized()
        controller.apply(configuration: WhiteboardConfiguration(
            isEnabled: normalized.enabled,
            idleVisibility: normalized.idleVisibility,
            includeInCaptures: normalized.includeInCaptures,
            surfaceStyle: normalized.surfaceStyle,
            guideStyle: normalized.guideStyle,
            outputBackgroundStyle: normalized.outputBackgroundStyle,
            editOpacity: normalized.editOpacity,
            storageDirectory: storageDirectory,
            languageCode: LanguageManager.shared.currentLanguageCode,
            applicationName: BuildEdition.productName
        ))
        if !normalized.enabled {
            if preparedForRecording {
                actions.setRecordingWindowIDs([])
                preparedForRecording = false
            }
        }
    }

    func handle(_ command: WhiteboardCommand) {
        guard actions.settings().enabled else { return }
        actions.hideLauncher()
        switch command {
        case .show:
            controller.showBoard()
        case .toggleEditing:
            controller.toggleEditing()
        case .importLatestScreenshot:
            guard let url = actions.latestScreenshot() else {
                presentError(L10n.whiteboardNoRecentScreenshot)
                return
            }
            sendImageFile(at: url, sourceName: url.lastPathComponent)
        }
    }

    func sendImageFile(at url: URL, sourceName: String?) {
        guard actions.settings().enabled,
              let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            presentError(L10n.screenshotErrorCaptureFailed)
            return
        }
        controller.importImage(cgImage, sourceName: sourceName)
    }

    func prepareForCapture() -> Set<CGWindowID> {
        guard actions.settings().enabled else { return [] }
        let includeContent = actions.settings().includeInCaptures
        controller.prepareForScreenCapture(includeContent ? .includeContent : .excludeContent)
        guard includeContent, let windowID = controller.captureWindowNumber else { return [] }
        return [windowID]
    }

    func prepareForRecording() -> Set<CGWindowID> {
        guard !preparedForRecording else {
            if let windowID = controller.captureWindowNumber, actions.settings().includeInCaptures {
                return [windowID]
            }
            return []
        }
        let windowIDs = prepareForCapture()
        preparedForRecording = actions.settings().enabled
        actions.setRecordingWindowIDs(windowIDs)
        return windowIDs
    }

    func restoreAfterRecording() {
        guard preparedForRecording else { return }
        actions.setRecordingWindowIDs([])
        controller.restoreAfterScreenCapture()
        preparedForRecording = false
    }

    func presentError(_ message: String) {
        guard actions.settings().enabled else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.whiteboardErrorTitle
        alert.informativeText = message
        alert.addButton(withTitle: L10n.actionOK)
        alert.runModal()
    }

    private var storageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(BuildEdition.productName, isDirectory: true)
            .appendingPathComponent("Whiteboards", isDirectory: true)
    }
}
