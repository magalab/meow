import AppKit
@preconcurrency import ApplicationServices
import Foundation
import SwiftUI

@MainActor
final class AppCaptureCoordinator {
    struct Actions {
        let settings: @MainActor () -> AppSettings
        let hideTransientPanels: @MainActor () -> Void
        let prepareWhiteboard: @MainActor () -> Set<CGWindowID>
        let restoreWhiteboard: @MainActor () -> Void
        let upload: @MainActor (URL) async throws -> Void
        let refreshLauncher: @MainActor () -> Void
        let presentScreenshotError: @MainActor (Error) -> Void
        let presentUploadError: @MainActor (Error) -> Void
        let presentScrollingAccessibilityPrompt: @MainActor () -> Void
        let presentScrollingReducedImageWarning: @MainActor () -> Void
        let editImage: @MainActor (URL) -> Void
        let recognizeClipboardImage: @MainActor (ImageClipboardContent, Bool) -> Void
        let scanClipboardImageQRCode: @MainActor (ImageClipboardContent) -> Void
        let askAI: @MainActor (URL) -> Void
        let sendImageFileToWhiteboard: @MainActor (URL, String?) -> Void
    }

    private let screenCaptureService: ScreenCaptureService
    private let captureOverlayController: CaptureOverlayController
    private let captureEditorController: CaptureEditorController
    private let captureStore: CaptureStore
    private let scrollingCaptureHUDController: ScrollingCaptureHUDController
    private let imageRecognitionService: ImageRecognitionService
    private let clipboardStore: ClipboardStore
    private let pinnedImageController: PinnedImageController
    private let postCaptureActionsController: PostCaptureActionsController
    private let windowCoordinator: AppWindowCoordinator
    private let actions: Actions

    private var captureTask: Task<Void, Never>?
    private var scrollingCaptureController: ScrollingCaptureController?

    var isBusy: Bool {
        captureTask != nil
    }

    init(
        screenCaptureService: ScreenCaptureService,
        captureOverlayController: CaptureOverlayController,
        captureEditorController: CaptureEditorController,
        captureStore: CaptureStore,
        scrollingCaptureHUDController: ScrollingCaptureHUDController,
        imageRecognitionService: ImageRecognitionService,
        clipboardStore: ClipboardStore,
        pinnedImageController: PinnedImageController,
        postCaptureActionsController: PostCaptureActionsController,
        windowCoordinator: AppWindowCoordinator,
        actions: Actions
    ) {
        self.screenCaptureService = screenCaptureService
        self.captureOverlayController = captureOverlayController
        self.captureEditorController = captureEditorController
        self.captureStore = captureStore
        self.scrollingCaptureHUDController = scrollingCaptureHUDController
        self.imageRecognitionService = imageRecognitionService
        self.clipboardStore = clipboardStore
        self.pinnedImageController = pinnedImageController
        self.postCaptureActionsController = postCaptureActionsController
        self.windowCoordinator = windowCoordinator
        self.actions = actions
    }

    func cancel() {
        captureTask?.cancel()
        scrollingCaptureController?.cancel()
        scrollingCaptureHUDController.close()
    }

    func triggerScreenshot(
        mode: ScreenshotCaptureMode,
        editAfterCapture: Bool = false,
        uploadAfterCapture: Bool = false
    ) {
        guard captureTask == nil else { return }
        actions.hideTransientPanels()

        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var whiteboardPrepared = false
            defer {
                if whiteboardPrepared {
                    self.actions.restoreWhiteboard()
                }
                self.captureTask = nil
            }

            do {
                let settings = actions.settings()
                let includedWhiteboardWindowIDs = mode.includesApplicationOverlays
                    ? actions.prepareWhiteboard()
                    : []
                whiteboardPrepared = mode.includesApplicationOverlays && settings.whiteboard.enabled
                let session = try await screenCaptureService.prepareSession(
                    includingApplicationWindowIDs: includedWhiteboardWindowIDs
                )
                guard !Task.isCancelled else { return }
                guard let selection = await captureOverlayController.present(session: session, mode: mode) else {
                    return
                }
                guard !Task.isCancelled else { return }

                let (capturedImage, kind) = try await screenCaptureService.capture(
                    selection,
                    session: session,
                    includeWindowShadow: actions.settings().screenshot.includeWindowShadow
                )
                actions.restoreWhiteboard()
                whiteboardPrepared = false

                let outputImage: CGImage
                let outputKind: CaptureArtifactKind
                if editAfterCapture {
                    guard let edited = await captureEditorController.present(source: capturedImage) else {
                        return
                    }
                    outputImage = edited
                    outputKind = .edited
                } else {
                    outputImage = capturedImage
                    outputKind = kind
                }

                let artifact = try processCapturedImage(outputImage, kind: outputKind)
                if uploadAfterCapture {
                    try await actions.upload(artifact.imageURL)
                } else {
                    showPostCaptureActionsIfNeeded(for: artifact)
                }
            } catch {
                if uploadAfterCapture {
                    actions.presentUploadError(error)
                } else {
                    actions.presentScreenshotError(error)
                }
            }
        }
    }

    func triggerScrollingCapture() {
        guard captureTask == nil else { return }
        actions.hideTransientPanels()

        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                scrollingCaptureHUDController.close()
                scrollingCaptureController = nil
                captureTask = nil
            }

            do {
                let session = try await screenCaptureService.prepareSession()
                guard !Task.isCancelled else { return }
                guard let selection = await captureOverlayController.present(
                    session: session,
                    mode: .region
                ) else { return }
                guard !Task.isCancelled else { return }
                guard case let .region(display, rect, scale) = selection,
                      let frozenDisplay = session.displays.first(where: {
                          $0.display.displayID == display.displayID
                      })
                else {
                    throw ScreenCaptureError.invalidSelection
                }

                let controller = ScrollingCaptureController(
                    captureService: screenCaptureService,
                    display: display,
                    screen: frozenDisplay.screen,
                    rectInDisplayPoints: rect,
                    scale: scale,
                    settings: actions.settings().screenshot.scrollingCapture
                )
                scrollingCaptureController = controller
                controller.onProgress = { [weak self] progress in
                    self?.scrollingCaptureHUDController.update(progress: progress)
                }
                controller.onPreview = { [weak self] preview in
                    self?.scrollingCaptureHUDController.update(preview: preview)
                }
                controller.onIssue = { [weak self] message in
                    self?.scrollingCaptureHUDController.showIssue(message)
                }
                controller.onAccessibilityPermissionRequired = { [weak self] in
                    self?.actions.presentScrollingAccessibilityPrompt()
                }

                scrollingCaptureHUDController.show(
                    relativeTo: rect,
                    on: frozenDisplay.screen,
                    onPauseResume: { [weak controller] in
                        controller?.togglePause()
                    },
                    onToggleAutoScroll: { [weak self, weak controller] in
                        guard let self, let controller else { return }
                        if controller.toggleAutoScroll() == .permissionRequired {
                            self.actions.presentScrollingAccessibilityPrompt()
                        }
                    },
                    onFinish: { [weak controller] in
                        controller?.finish()
                    },
                    onCancel: { [weak controller] in
                        controller?.cancel()
                    }
                )

                let result = await controller.run()
                guard !Task.isCancelled else { return }
                switch result {
                case .cancelled:
                    return
                case let .failed(error):
                    throw error
                case let .completed(finalImage):
                    let artifact = try processCapturedImage(finalImage.image, kind: .scrolling)
                    if finalImage.isReduced {
                        actions.presentScrollingReducedImageWarning()
                    }
                    showPostCaptureActionsIfNeeded(for: artifact)
                }
            } catch {
                actions.presentScreenshotError(error)
            }
        }
    }

    func processCapturedImage(
        _ image: CGImage,
        kind: CaptureArtifactKind
    ) throws -> CaptureArtifact {
        let settings = actions.settings().screenshot
        var externalURL: URL?

        if settings.outputMode == .save || settings.outputMode == .copyAndSave {
            externalURL = try captureStore.saveExternal(image: image, settings: settings)
        }

        let artifact: CaptureArtifact
        do {
            artifact = try captureStore.saveInternal(
                image: image,
                kind: kind,
                historyLimit: settings.historyLimit,
                retentionDays: settings.retentionDays,
                maxStorageMB: settings.maxStorageMB
            )
        } catch {
            if let externalURL {
                do {
                    try FileManager.default.removeItem(at: externalURL)
                } catch {
                    MeowLog.capture.debug(
                        "Unable to clean up external capture \(externalURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            throw error
        }

        if actions.settings().clipboardHistoryEnabled {
            clipboardStore.insertCapture(artifact)
        }
        switch settings.outputMode {
        case .copy:
            clipboardStore.writeCaptureToPasteboard(artifact)
        case .save:
            break
        case .copyAndSave:
            clipboardStore.writeCaptureToPasteboard(artifact)
        }

        if settings.playSound {
            NSSound(named: NSSound.Name("Grab"))?.play()
        }
        actions.refreshLauncher()
        if settings.automaticallyIndexOCRText, artifact.supportsAutomaticOCR {
            indexCaptureText(artifact)
        }
        return artifact
    }

    func showCaptureHistory() {
        windowCoordinator.showCaptureHistory(
            contentViewController: NSHostingController(
                rootView: makeCaptureHistoryView(theme: actions.settings().theme)
            ),
            title: L10n.screenshotHistoryTitle
        )
    }

    func makeCaptureHistoryView(theme: AppTheme) -> CaptureHistoryView {
        CaptureHistoryView(
            store: captureStore,
            theme: theme,
            onCopy: { [weak self] artifact in
                self?.clipboardStore.writeCaptureToPasteboard(artifact)
            },
            onPin: { [weak self] artifact in
                self?.pinnedImageController.pin(artifact)
            },
            onEdit: { [weak self] artifact in
                self?.actions.editImage(artifact.imageURL)
            },
            onRecognizeText: { [weak self] artifact in
                guard let self else { return }
                self.actions.recognizeClipboardImage(
                    self.imageContent(for: artifact),
                    false
                )
            },
            onTranslate: { [weak self] artifact in
                guard let self else { return }
                self.actions.recognizeClipboardImage(
                    self.imageContent(for: artifact),
                    true
                )
            },
            onScanQRCode: { [weak self] artifact in
                guard let self else { return }
                self.actions.scanClipboardImageQRCode(self.imageContent(for: artifact))
            },
            onAskAI: { [weak self] artifact in
                self?.actions.askAI(artifact.imageURL)
            },
            onSendToWhiteboard: actions.settings().whiteboard.enabled ? { [weak self] artifact in
                self?.actions.sendImageFileToWhiteboard(
                    artifact.imageURL,
                    artifact.imageURL.lastPathComponent
                )
            } : nil,
            onDelete: { [weak self] artifact in
                guard let self else { return }
                self.clipboardStore.removeCaptureEntries(ids: Set([artifact.id]))
                self.captureStore.delete(artifact)
                self.actions.refreshLauncher()
            },
            onClear: { [weak self] in
                guard let self else { return }
                let ids = Set(self.captureStore.artifacts.map(\.id))
                self.clipboardStore.removeCaptureEntries(ids: ids)
                self.captureStore.clear()
                self.actions.refreshLauncher()
            }
        )
    }

    func showPostCaptureActionsIfNeeded(for artifact: CaptureArtifact) {
        let settings = actions.settings()
        guard settings.screenshot.showPostCaptureActions else { return }
        postCaptureActionsController.show(
            artifact: artifact,
            duration: settings.screenshot.postCaptureActionDuration,
            includesUpload: settings.fileHosting.s3.isEnabled,
            includesWhiteboard: settings.whiteboard.enabled
        ) { [weak self] action, artifact in
            self?.handlePostCaptureAction(action, artifact: artifact)
        }
    }

    private func handlePostCaptureAction(
        _ action: PostCaptureAction,
        artifact: CaptureArtifact
    ) {
        switch action {
        case .copy:
            clipboardStore.writeCaptureToPasteboard(artifact)
        case .save:
            do {
                guard let image = NSImage(contentsOf: artifact.imageURL),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                else {
                    throw CaptureStoreError.imageEncodingFailed
                }
                _ = try captureStore.saveExternal(
                    image: cgImage,
                    settings: actions.settings().screenshot
                )
            } catch {
                actions.presentScreenshotError(error)
            }
        case .edit:
            actions.editImage(artifact.imageURL)
        case .pin:
            pinnedImageController.pin(artifact)
        case .recognizeText:
            actions.recognizeClipboardImage(imageContent(for: artifact), false)
        case .translate:
            actions.recognizeClipboardImage(imageContent(for: artifact), true)
        case .askAI:
            actions.askAI(artifact.imageURL)
        case .whiteboard:
            actions.sendImageFileToWhiteboard(
                artifact.imageURL,
                artifact.imageURL.lastPathComponent
            )
        case .upload:
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await actions.upload(artifact.imageURL)
                } catch {
                    actions.presentUploadError(error)
                }
            }
        }
    }

    private func imageContent(for artifact: CaptureArtifact) -> ImageClipboardContent {
        ImageClipboardContent(
            thumbnailPath: artifact.thumbnailURL.path,
            originalPath: artifact.imageURL.path,
            sourceName: L10n.screenshotClipboardName,
            width: artifact.width,
            height: artifact.height,
            ownsCachedFiles: false
        )
    }

    private func indexCaptureText(_ artifact: CaptureArtifact) {
        let image = ImageClipboardContent(
            thumbnailPath: artifact.thumbnailURL.path,
            originalPath: artifact.imageURL.path,
            sourceName: L10n.screenshotClipboardName,
            width: artifact.width,
            height: artifact.height,
            ownsCachedFiles: false
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let text = try await imageRecognitionService.recognizeText(
                    in: image,
                    languages: actions.settings().screenshot.ocrLanguages.map(\.visionIdentifier)
                )
                captureStore.updateOCRText(text, for: artifact.id)
            } catch {
                // Images without text remain valid history entries.
            }
        }
    }
}
