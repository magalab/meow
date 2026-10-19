import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

@MainActor
final class AppLauncherCoordinator {
    private let viewModel: LauncherViewModel
    private let keepAwakeService: KeepAwakeService
    private let windowCoordinator: AppWindowCoordinator

    init(
        viewModel: LauncherViewModel,
        keepAwakeService: KeepAwakeService,
        windowCoordinator: AppWindowCoordinator
    ) {
        self.viewModel = viewModel
        self.keepAwakeService = keepAwakeService
        self.windowCoordinator = windowCoordinator
    }

    func show() {
        viewModel.updateKeepAwakeState(
            keepAwakeService.state,
            remainingMinutes: keepAwakeService.remainingMinutes
        )
        // Keep app list fresh so newly installed apps appear without restarting Meow.
        if !viewModel.refreshInstalledApps() {
            viewModel.refresh()
        }
        windowCoordinator.showLauncher { [weak self] in
            guard let self else { return NSViewController() }
            return NSHostingController(
                rootView: LauncherView(
                    viewModel: viewModel,
                    onDismiss: { [weak self] in self?.hide() },
                    onLauncherHeightChange: { [weak self] height in
                        self?.windowCoordinator.setLauncherHeight(height)
                    }
                )
            )
        }
    }

    func hide() {
        windowCoordinator.hideLauncher()
        viewModel.resetForHide()
        NotificationCenter.default.post(name: .meowLauncherDidHide, object: nil)
    }

    func toggle() {
        if windowCoordinator.isLauncherVisible {
            hide()
        } else {
            show()
        }
    }

    func openFinder() {
        hide()
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        guard NSWorkspace.shared.open(homeDirectory) else {
            MeowLog.app.error(
                "Failed to open Finder at \(homeDirectory.path, privacy: .private(mask: .hash))"
            )
            return
        }
    }

    /// Simulates Cmd+V to paste the clipboard content into the frontmost app.
    func simulatePaste() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        guard trusted else {
            // Try again in case the user approved the permission prompt just now.
            MeowLog.app.warning("Accessibility permission not granted; paste may not work")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
