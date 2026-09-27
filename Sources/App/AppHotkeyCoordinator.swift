import Foundation

@MainActor
final class AppHotkeyCoordinator {
    enum Event {
        case toggleLauncher
        case openFinder
        case translate
        case textActions
        case screenshotDefault
        case screenshotDefaultAndEdit
        case scrollingScreenshot
        case screenshot(ScreenshotCaptureMode)
        case recording(ScreenshotCaptureMode)
        case pauseRecording
        case stopRecording
        case saveRecordingFrame
        case toggleRecordingMagnifier
        case uploadScreenshot
        case toggleWhiteboard
        #if MEOW_VOICE
        case speechPressed
        case speechReleased
        #endif
    }

    enum Kind: Hashable {
        case launcher
        case finder
        case translation
        case textActions
        case screenshotRegion
        case screenshotScrolling
        case screenshotEdit
        case screenshotWindow
        case screenshotDisplay
        case recordingDisplay
        case recordingRegion
        case recordingWindow
        case recordingPause
        case recordingStop
        case recordingFrame
        case recordingMagnifier
        case upload
        case whiteboard
        #if MEOW_VOICE
        case speech
        #endif
    }

    struct Shortcut: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    struct Actions {
        let invoke: @MainActor (Event) -> Void
        let restore: @MainActor (Kind, UInt32, UInt32) -> Void
        let registrationSucceeded: @MainActor (Kind) -> Void
        let registrationFailure: @MainActor (Kind, OSStatus) -> Void
    }

    // Carbon rejects duplicate key combinations, so this order defines the
    // stable priority for conflicting recording shortcuts.
    static let recordingHotkeyRegistrationOrder: [Kind] = [
        .recordingDisplay,
        .recordingFrame,
        .recordingMagnifier,
        .recordingRegion,
        .recordingWindow,
        .recordingPause,
        .recordingStop,
    ]

    private struct Registration {
        let result: HotkeyService.RegistrationResult
        let name: String
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private let hotkeyService: HotkeyService
    private var lastRegistered: [Kind: Shortcut] = [:]

    init(hotkeyService: HotkeyService) {
        self.hotkeyService = hotkeyService
    }

    func unregister() {
        hotkeyService.unregister()
        lastRegistered.removeAll()
    }

    func apply(settings: AppSettings, actions: Actions) {
        register(
            hotkeyService.registerToggleHotkey(
                keyCode: settings.hotkeyKeyCode,
                modifiers: settings.hotkeyModifiers,
                action: callback(.toggleLauncher, actions)
            ),
            kind: .launcher,
            name: "launcher",
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers,
            actions: actions
        )
        register(
            hotkeyService.registerFinderHotkey(
                keyCode: settings.finderHotkeyKeyCode,
                modifiers: settings.finderHotkeyModifiers,
                action: callback(.openFinder, actions)
            ),
            kind: .finder,
            name: "finder",
            keyCode: settings.finderHotkeyKeyCode,
            modifiers: settings.finderHotkeyModifiers,
            actions: actions
        )

        let translateResult = hotkeyService.registerTranslateHotkey(
            keyCode: settings.translateHotkeyKeyCode,
            modifiers: settings.translateHotkeyModifiers,
            action: callback(.translate, actions)
        )
        register(
            translateResult,
            kind: .translation,
            name: "translation",
            keyCode: settings.translateHotkeyKeyCode,
            modifiers: settings.translateHotkeyModifiers,
            actions: actions
        )

        let textActionsResult = hotkeyService.registerTextActionsHotkey(
            keyCode: settings.textActionsHotkeyKeyCode,
            modifiers: settings.textActionsHotkeyModifiers,
            action: callback(.textActions, actions)
        )
        register(
            textActionsResult,
            kind: .textActions,
            name: "selected-text actions",
            keyCode: settings.textActionsHotkeyKeyCode,
            modifiers: settings.textActionsHotkeyModifiers,
            actions: actions
        )

        #if MEOW_VOICE
        if settings.speech.enabled {
            register(
                hotkeyService.registerSpeechHotkey(
                    keyCode: settings.speech.hotkeyKeyCode,
                    modifiers: settings.speech.hotkeyModifiers,
                    pressedAction: callback(.speechPressed, actions),
                    releasedAction: callback(.speechReleased, actions)
                ),
                kind: .speech,
                name: "speech",
                keyCode: settings.speech.hotkeyKeyCode,
                modifiers: settings.speech.hotkeyModifiers,
                actions: actions
            )
        } else {
            hotkeyService.unregisterSpeechHotkey()
            lastRegistered[.speech] = nil
        }
        #else
        hotkeyService.unregisterSpeechHotkey()
        #endif

        applyScreenshot(settings.screenshot, actions: actions)
        applyRecording(settings.recording, actions: actions)
        applyUpload(settings.fileHosting, actions: actions)
        applyWhiteboard(settings.whiteboard, actions: actions)
    }

    private func applyScreenshot(_ settings: ScreenshotSettings, actions: Actions) {
        let kinds: [Kind] = [
            .screenshotRegion,
            .screenshotScrolling,
            .screenshotEdit,
            .screenshotWindow,
            .screenshotDisplay,
        ]
        guard settings.enabled else {
            hotkeyService.unregisterScreenshotHotkeys()
            forget(kinds)
            return
        }

        register(
            hotkeyService.registerScreenshotRegionHotkey(
                keyCode: settings.regionHotkeyKeyCode,
                modifiers: settings.regionHotkeyModifiers,
                action: callback(.screenshotDefault, actions)
            ),
            kind: .screenshotRegion,
            name: "screenshot region",
            keyCode: settings.regionHotkeyKeyCode,
            modifiers: settings.regionHotkeyModifiers,
            actions: actions
        )
        register(
            hotkeyService.registerScreenshotScrollingHotkey(
                keyCode: settings.scrollingHotkeyKeyCode,
                modifiers: settings.scrollingHotkeyModifiers,
                action: callback(.scrollingScreenshot, actions)
            ),
            kind: .screenshotScrolling,
            name: "screenshot scrolling",
            keyCode: settings.scrollingHotkeyKeyCode,
            modifiers: settings.scrollingHotkeyModifiers,
            actions: actions
        )
        register(
            hotkeyService.registerScreenshotEditHotkey(
                keyCode: settings.editHotkeyKeyCode,
                modifiers: settings.editHotkeyModifiers,
                action: callback(.screenshotDefaultAndEdit, actions)
            ),
            kind: .screenshotEdit,
            name: "screenshot edit",
            keyCode: settings.editHotkeyKeyCode,
            modifiers: settings.editHotkeyModifiers,
            actions: actions
        )
        register(
            hotkeyService.registerScreenshotWindowHotkey(
                keyCode: settings.windowHotkeyKeyCode,
                modifiers: settings.windowHotkeyModifiers,
                action: callback(.screenshot(.window), actions)
            ),
            kind: .screenshotWindow,
            name: "screenshot window",
            keyCode: settings.windowHotkeyKeyCode,
            modifiers: settings.windowHotkeyModifiers,
            actions: actions
        )
        register(
            hotkeyService.registerScreenshotDisplayHotkey(
                keyCode: settings.displayHotkeyKeyCode,
                modifiers: settings.displayHotkeyModifiers,
                action: callback(.screenshot(.display), actions)
            ),
            kind: .screenshotDisplay,
            name: "screenshot display",
            keyCode: settings.displayHotkeyKeyCode,
            modifiers: settings.displayHotkeyModifiers,
            actions: actions
        )
    }

    private func applyRecording(_ settings: RecordingSettings, actions: Actions) {
        let kinds = Self.recordingHotkeyRegistrationOrder
        guard settings.enabled else {
            hotkeyService.unregisterRecordingHotkeys()
            forget(kinds)
            return
        }

        for kind in kinds {
            let registration = recordingRegistration(for: kind, settings: settings, actions: actions)
            register(
                registration.result,
                kind: kind,
                name: registration.name,
                keyCode: registration.keyCode,
                modifiers: registration.modifiers,
                actions: actions
            )
        }
    }

    private func recordingRegistration(
        for kind: Kind,
        settings: RecordingSettings,
        actions: Actions
    ) -> Registration {
        switch kind {
        case .recordingDisplay:
            return Registration(
                result: hotkeyService.registerRecordingDisplayHotkey(
                    keyCode: settings.displayHotkeyKeyCode,
                    modifiers: settings.displayHotkeyModifiers,
                    action: callback(.recording(.display), actions)
                ),
                name: "recording display",
                keyCode: settings.displayHotkeyKeyCode,
                modifiers: settings.displayHotkeyModifiers
            )
        case .recordingFrame:
            return Registration(
                result: hotkeyService.registerRecordingFrameHotkey(
                    keyCode: settings.frameHotkeyKeyCode,
                    modifiers: settings.frameHotkeyModifiers,
                    action: callback(.saveRecordingFrame, actions)
                ),
                name: "recording frame",
                keyCode: settings.frameHotkeyKeyCode,
                modifiers: settings.frameHotkeyModifiers
            )
        case .recordingMagnifier:
            return Registration(
                result: hotkeyService.registerRecordingMagnifierHotkey(
                    keyCode: settings.magnifierHotkeyKeyCode,
                    modifiers: settings.magnifierHotkeyModifiers,
                    action: callback(.toggleRecordingMagnifier, actions)
                ),
                name: "recording magnifier",
                keyCode: settings.magnifierHotkeyKeyCode,
                modifiers: settings.magnifierHotkeyModifiers
            )
        case .recordingRegion:
            return Registration(
                result: hotkeyService.registerRecordingRegionHotkey(
                    keyCode: settings.regionHotkeyKeyCode,
                    modifiers: settings.regionHotkeyModifiers,
                    action: callback(.recording(.region), actions)
                ),
                name: "recording region",
                keyCode: settings.regionHotkeyKeyCode,
                modifiers: settings.regionHotkeyModifiers
            )
        case .recordingWindow:
            return Registration(
                result: hotkeyService.registerRecordingWindowHotkey(
                    keyCode: settings.windowHotkeyKeyCode,
                    modifiers: settings.windowHotkeyModifiers,
                    action: callback(.recording(.window), actions)
                ),
                name: "recording window",
                keyCode: settings.windowHotkeyKeyCode,
                modifiers: settings.windowHotkeyModifiers
            )
        case .recordingPause:
            return Registration(
                result: hotkeyService.registerRecordingPauseHotkey(
                    keyCode: settings.pauseHotkeyKeyCode,
                    modifiers: settings.pauseHotkeyModifiers,
                    action: callback(.pauseRecording, actions)
                ),
                name: "recording pause",
                keyCode: settings.pauseHotkeyKeyCode,
                modifiers: settings.pauseHotkeyModifiers
            )
        case .recordingStop:
            return Registration(
                result: hotkeyService.registerRecordingStopHotkey(
                    keyCode: settings.stopHotkeyKeyCode,
                    modifiers: settings.stopHotkeyModifiers,
                    action: callback(.stopRecording, actions)
                ),
                name: "recording stop",
                keyCode: settings.stopHotkeyKeyCode,
                modifiers: settings.stopHotkeyModifiers
            )
        default:
            MeowLog.hotkey.fault("Unexpected non-recording hotkey kind in recording registration")
            return Registration(
                result: .failed(-50),
                name: "unsupported recording",
                keyCode: 0,
                modifiers: 0
            )
        }
    }

    private func applyUpload(_ settings: FileHostSettings, actions: Actions) {
        guard settings.s3.isEnabled,
              settings.uploadHotkeyKeyCode != 0,
              settings.uploadHotkeyModifiers != 0
        else {
            hotkeyService.unregisterUploadHotkey()
            forget([.upload])
            return
        }

        register(
            hotkeyService.registerUploadHotkey(
                keyCode: settings.uploadHotkeyKeyCode,
                modifiers: settings.uploadHotkeyModifiers,
                action: callback(.uploadScreenshot, actions)
            ),
            kind: .upload,
            name: "upload screenshot",
            keyCode: settings.uploadHotkeyKeyCode,
            modifiers: settings.uploadHotkeyModifiers,
            actions: actions
        )
    }

    private func applyWhiteboard(_ settings: WhiteboardSettings, actions: Actions) {
        let normalized = settings.normalized()
        guard normalized.enabled else {
            hotkeyService.unregisterWhiteboardHotkey()
            forget([.whiteboard])
            return
        }

        register(
            hotkeyService.registerWhiteboardHotkey(
                keyCode: normalized.hotkeyKeyCode,
                modifiers: normalized.hotkeyModifiers,
                action: callback(.toggleWhiteboard, actions)
            ),
            kind: .whiteboard,
            name: "whiteboard",
            keyCode: normalized.hotkeyKeyCode,
            modifiers: normalized.hotkeyModifiers,
            actions: actions
        )
    }

    private func callback(_ event: Event, _ actions: Actions) -> () -> Void {
        { [actions] in
            Task { @MainActor in
                actions.invoke(event)
            }
        }
    }

    private func forget(_ kinds: [Kind]) {
        for kind in kinds {
            lastRegistered[kind] = nil
        }
    }

    private func register(
        _ result: HotkeyService.RegistrationResult,
        kind: Kind,
        name: String,
        keyCode: UInt32,
        modifiers: UInt32,
        actions: Actions
    ) {
        switch result {
        case .registered:
            lastRegistered[kind] = Shortcut(keyCode: keyCode, modifiers: modifiers)
            actions.registrationSucceeded(kind)
        case let .failed(status):
            MeowLog.hotkey.error(
                "Failed to register \(name, privacy: .public) hotkey: \(status, privacy: .public)"
            )
            actions.registrationFailure(kind, status)
            guard let previous = lastRegistered[kind],
                  previous.keyCode != keyCode || previous.modifiers != modifiers
            else { return }
            actions.restore(kind, previous.keyCode, previous.modifiers)
        }
    }
}
