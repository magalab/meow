import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case noDisplays
    case displayUnavailable
    case captureFailed
    case invalidSelection
    case liveFrameUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return L10n.screenshotErrorPermissionDenied
        case .noDisplays: return L10n.screenshotErrorNoDisplays
        case .displayUnavailable: return L10n.screenshotErrorDisplayUnavailable
        case .captureFailed: return L10n.screenshotErrorCaptureFailed
        case .invalidSelection: return L10n.screenshotErrorInvalidSelection
        case .liveFrameUnavailable: return L10n.scrollingCaptureErrorLiveFrame
        }
    }
}

@MainActor
final class ScreenCaptureService {
    func prepareSession(
        includingApplicationWindowIDs: Set<CGWindowID> = []
    ) async throws -> CaptureSession {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw ScreenCaptureError.permissionDenied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard !content.displays.isEmpty else {
            throw ScreenCaptureError.noDisplays
        }

        let ownApplication = content.applications.first {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let includedOwnWindows = content.windows.filter {
            includingApplicationWindowIDs.contains($0.windowID)
        }
        var frozenDisplays: [FrozenDisplay] = []

        for display in content.displays {
            guard let screen = Self.screen(for: display.displayID) else { continue }
            let scale = screen.backingScaleFactor
            let filter = SCContentFilter(
                display: display,
                excludingApplications: ownApplication.map { [$0] } ?? [],
                exceptingWindows: includedOwnWindows
            )
            let configuration = Self.configuration(
                width: CGFloat(display.width),
                height: CGFloat(display.height),
                scale: scale
            )
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            frozenDisplays.append(
                FrozenDisplay(
                    display: display,
                    screen: screen,
                    image: image,
                    scale: scale
                )
            )
        }

        guard !frozenDisplays.isEmpty else {
            throw ScreenCaptureError.displayUnavailable
        }

        let windows = content.windows.filter { window in
            guard window.isOnScreen, window.windowLayer == 0 else { return false }
            guard window.frame.width >= 40, window.frame.height >= 40 else { return false }
            return window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
                || includingApplicationWindowIDs.contains(window.windowID)
        }

        return CaptureSession(
            content: content,
            displays: frozenDisplays,
            windows: windows
        )
    }

    func capture(
        _ selection: CaptureSelection,
        session: CaptureSession,
        includeWindowShadow: Bool = true
    ) async throws -> (CGImage, CaptureArtifactKind) {
        switch selection {
        case let .region(display, rect, scale):
            guard let frozen = session.displays.first(where: { $0.display.displayID == display.displayID }) else {
                throw ScreenCaptureError.displayUnavailable
            }
            let pixelRect = Self.pixelRect(
                for: rect,
                displayHeight: CGFloat(display.height),
                scale: scale
            )
            guard pixelRect.width >= 2,
                  pixelRect.height >= 2,
                  let cropped = frozen.image.cropping(to: pixelRect)
            else {
                throw ScreenCaptureError.invalidSelection
            }
            return (cropped, .region)

        case let .window(window, scale):
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = Self.configuration(
                width: window.frame.width,
                height: window.frame.height,
                scale: scale,
                ignoreWindowShadow: !includeWindowShadow
            )
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return (image, .window)

        case let .display(display, scale):
            guard let frozen = session.displays.first(where: { $0.display.displayID == display.displayID }) else {
                throw ScreenCaptureError.displayUnavailable
            }
            if frozen.scale == scale {
                return (frozen.image, .display)
            }
            return (frozen.image, .display)
        }
    }

    func captureLiveRegion(
        display: SCDisplay,
        rectInDisplayPoints: CGRect,
        scale: CGFloat
    ) async throws -> CGImage {
        guard rectInDisplayPoints.width >= 2, rectInDisplayPoints.height >= 2 else {
            throw ScreenCaptureError.invalidSelection
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let currentDisplay = content.displays.first(where: {
            $0.displayID == display.displayID
        }) else {
            throw ScreenCaptureError.displayUnavailable
        }
        let ownApplication = content.applications.first {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: currentDisplay,
            excludingApplications: ownApplication.map { [$0] } ?? [],
            exceptingWindows: []
        )
        let sourceRect = CGRect(
            x: rectInDisplayPoints.minX,
            y: CGFloat(currentDisplay.height) - rectInDisplayPoints.maxY,
            width: rectInDisplayPoints.width,
            height: rectInDisplayPoints.height
        ).integral
        guard sourceRect.minX >= 0,
              sourceRect.minY >= 0,
              sourceRect.maxX <= CGFloat(currentDisplay.width),
              sourceRect.maxY <= CGFloat(currentDisplay.height)
        else {
            throw ScreenCaptureError.invalidSelection
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = max(1, Int((sourceRect.width * scale).rounded()))
        configuration.height = max(1, Int((sourceRect.height * scale).rounded()))
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.captureResolution = .best

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ScreenCaptureError.liveFrameUnavailable
        }
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else { return false }
            return CGDirectDisplayID(number.uint32Value) == displayID
        }
    }

    static func appKitRect(fromCoreGraphics rect: CGRect) -> CGRect {
        let primaryTop = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? 0
        return CGRect(
            x: rect.minX,
            y: primaryTop - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func pixelRect(
        for rectInDisplayPoints: CGRect,
        displayHeight: CGFloat,
        scale: CGFloat
    ) -> CGRect {
        CGRect(
            x: rectInDisplayPoints.minX * scale,
            y: (displayHeight - rectInDisplayPoints.maxY) * scale,
            width: rectInDisplayPoints.width * scale,
            height: rectInDisplayPoints.height * scale
        ).integral
    }

    private static func configuration(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        ignoreWindowShadow: Bool = false
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((width * scale).rounded()))
        configuration.height = max(1, Int((height * scale).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = ignoreWindowShadow
        configuration.captureResolution = .best
        return configuration
    }
}
