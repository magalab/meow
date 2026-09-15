import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class AppClipboardActionCoordinator {
    struct Actions {
        let settings: @MainActor () -> AppSettings
        let hideLauncher: @MainActor () -> Void
        let presentTranslation: @MainActor (String, Bool, String?) -> Void
        let presentScreenshotError: @MainActor (Error) -> Void
        let presentUploadError: @MainActor (Error) -> Void
        let importImageFileToWhiteboard: @MainActor (URL, String?) -> Void
        let onArtifactReady: @MainActor (CaptureArtifact) -> Void
        let presentOTPAuthImport: @MainActor (String) -> Void
        let presentQRCodePayload: @MainActor (String) -> Void
    }

    private let imageRecognitionService: ImageRecognitionService
    private let captureEditorController: CaptureEditorController
    private let captureCoordinator: AppCaptureCoordinator
    private let fileUploadService: FileUploadService
    private let actions: Actions

    init(
        imageRecognitionService: ImageRecognitionService,
        captureEditorController: CaptureEditorController,
        captureCoordinator: AppCaptureCoordinator,
        fileUploadService: FileUploadService,
        actions: Actions
    ) {
        self.imageRecognitionService = imageRecognitionService
        self.captureEditorController = captureEditorController
        self.captureCoordinator = captureCoordinator
        self.fileUploadService = fileUploadService
        self.actions = actions
    }

    func recognizeClipboardImage(_ image: ImageClipboardContent, translate: Bool) {
        actions.hideLauncher()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let text = try await imageRecognitionService.recognizeText(
                    in: image,
                    languages: actions.settings().screenshot.ocrLanguages.map(\.visionIdentifier)
                )
                if translate {
                    actions.presentTranslation(
                        text,
                        false,
                        image.originalPath ?? image.thumbnailPath
                    )
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    let alert = NSAlert()
                    alert.messageText = L10n.screenshotOCRCopiedTitle
                    alert.informativeText = L10n.screenshotOCRCopiedMessage
                    alert.addButton(withTitle: L10n.actionOK)
                    alert.runModal()
                }
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L10n.screenshotOCRErrorTitle
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: L10n.actionOK)
                alert.runModal()
            }
        }
    }

    func scanClipboardImageQRCode(_ image: ImageClipboardContent) {
        actions.hideLauncher()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let payload = try await imageRecognitionService.detectQRCode(in: image)
                if payload.lowercased().hasPrefix("otpauth://") {
                    actions.presentOTPAuthImport(payload)
                } else {
                    actions.presentQRCodePayload(payload)
                }
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L10n.screenshotQRErrorTitle
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: L10n.actionOK)
                alert.runModal()
            }
        }
    }

    func editClipboardImage(_ image: ImageClipboardContent) {
        let path = image.originalPath ?? image.thumbnailPath
        editImage(at: URL(fileURLWithPath: path))
    }

    func openClipboardImage(_ image: ImageClipboardContent) {
        actions.hideLauncher()
        let path = image.originalPath ?? image.thumbnailPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func saveClipboardImageAs(_ imageContent: ImageClipboardContent) {
        actions.hideLauncher()
        let path = imageContent.originalPath ?? imageContent.thumbnailPath
        guard let image = NSImage(contentsOfFile: path) else {
            actions.presentScreenshotError(ImageRecognitionError.imageUnavailable)
            return
        }

        let sourceExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = sourceExtension == "jpg" || sourceExtension == "jpeg"
            ? "\(imageContent.sourceName).jpg"
            : "\(imageContent.sourceName).png"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let fileExtension = destination.pathExtension.lowercased()
            let data: Data?
            if fileExtension == "jpg" || fileExtension == "jpeg",
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            {
                data = NSBitmapImageRep(cgImage: cgImage).representation(
                    using: .jpeg,
                    properties: [.compressionFactor: 0.9]
                )
            } else {
                data = image.pngData()
            }
            guard let data else {
                throw CaptureStoreError.imageEncodingFailed
            }
            try data.write(to: destination, options: .atomic)
        } catch {
            actions.presentScreenshotError(error)
        }
    }

    func upload(fileURL: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await fileUploadService.upload(fileURL: fileURL)
            } catch {
                actions.presentUploadError(error)
            }
        }
    }

    func uploadFromClipboard() {
        guard actions.settings().fileHosting.s3.isEnabled else {
            actions.presentUploadError(UploadError.notConfigured)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await fileUploadService.uploadFromClipboard()
            } catch {
                actions.presentUploadError(error)
            }
        }
    }

    func sendImageToWhiteboard(_ image: ImageClipboardContent) {
        guard actions.settings().whiteboard.enabled else { return }
        actions.hideLauncher()
        let path = image.originalPath ?? image.thumbnailPath
        actions.importImageFileToWhiteboard(URL(fileURLWithPath: path), image.sourceName)
    }

    func imageContent(for artifact: CaptureArtifact) -> ImageClipboardContent {
        ImageClipboardContent(
            thumbnailPath: artifact.thumbnailURL.path,
            originalPath: artifact.imageURL.path,
            sourceName: L10n.screenshotClipboardName,
            width: artifact.width,
            height: artifact.height,
            ownsCachedFiles: false
        )
    }

    func editImage(at url: URL) {
        actions.hideLauncher()
        guard imageAtURLSupportsFullResolutionEditing(url) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.scrollingCaptureEditLimitTitle
            alert.informativeText = L10n.scrollingCaptureEditLimitMessage
            alert.addButton(withTitle: L10n.actionOK)
            alert.runModal()
            return
        }

        Task { @MainActor [weak self] in
            guard let self,
                  let image = NSImage(contentsOf: url),
                  let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let edited = await captureEditorController.present(source: source)
            else { return }

            do {
                let artifact = try captureCoordinator.processCapturedImage(edited, kind: .edited)
                actions.onArtifactReady(artifact)
            } catch {
                actions.presentScreenshotError(error)
            }
        }
    }

    private func imageAtURLSupportsFullResolutionEditing(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else { return true }
        let result = width.int64Value.multipliedReportingOverflow(by: height.int64Value)
        let pixelCount = result.overflow ? Int64.max : result.partialValue
        return pixelCount <= CaptureArtifact.fullResolutionEditingPixelLimit
    }
}
