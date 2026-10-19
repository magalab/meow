import AppKit
import MeowClipboard
@preconcurrency import ApplicationServices
import SwiftUI

@MainActor
final class AppLauncherCoordinator {
    private let viewModel: LauncherViewModel
    private let keepAwakeService: KeepAwakeService
    private let clipboardStore: ClipboardStore
    private let windowCoordinator: AppWindowCoordinator

    init(
        viewModel: LauncherViewModel,
        keepAwakeService: KeepAwakeService,
        clipboardStore: ClipboardStore,
        windowCoordinator: AppWindowCoordinator
    ) {
        self.viewModel = viewModel
        self.keepAwakeService = keepAwakeService
        self.clipboardStore = clipboardStore
        self.windowCoordinator = windowCoordinator
    }

    func bindOutputCommands() {
        viewModel.onPasteClipboard = { [weak self] entry in
            guard let self else { return }
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                clipboardStore.writeToPasteboard(entry)
                simulatePaste()
            }
        }
        viewModel.onCopyText = { [weak self] text in
            guard let self else { return }
            hide()
            clipboardStore.writePrivateTextToPasteboard(text)
        }
        viewModel.onLaunchApplication = { [weak self] app in
            guard let self else { return }
            hide()
            DispatchQueue.main.async {
                NSWorkspace.shared.openApplication(
                    at: app.url,
                    configuration: NSWorkspace.OpenConfiguration(),
                    completionHandler: nil
                )
            }
        }
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
