import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
@Test("Hotkey router maps every event to the existing action")
func hotkeyRouterDispatchesEvents() {
    let recorder = HotkeyRouterRecorder()
    let router = AppHotkeyRouter(actions: makeHotkeyRouterActions(recorder: recorder))
    let actions = router.makeCoordinatorActions()

    actions.invoke(.toggleLauncher)
    actions.invoke(.openFinder)
    actions.invoke(.translate)
    actions.invoke(.textActions)
    actions.invoke(.screenshotDefault)
    actions.invoke(.screenshotDefaultAndEdit)
    actions.invoke(.scrollingScreenshot)
    actions.invoke(.screenshot(.window))
    actions.invoke(.recording(.display))
    actions.invoke(.pauseRecording)
    actions.invoke(.stopRecording)
    actions.invoke(.saveRecordingFrame)
    actions.invoke(.toggleRecordingMagnifier)
    actions.invoke(.uploadScreenshot)
    actions.invoke(.toggleWhiteboard)
    #if MEOW_VOICE
    actions.invoke(.speechPressed)
    actions.invoke(.speechReleased)
    #endif

    var expected = [
        "toggleLauncher",
        "openFinder",
        "translate",
        "textActions",
        "screenshot:region:false:false",
        "screenshot:region:true:false",
        "scrollingScreenshot",
        "screenshot:window:false:false",
        "recording:display",
        "pauseRecording",
        "stopRecording",
        "saveRecordingFrame",
        "toggleRecordingMagnifier",
        "screenshot:region:false:true",
        "toggleWhiteboard",
    ]
    #if MEOW_VOICE
    expected += ["speechPressed", "speechReleased"]
    #endif
    #expect(recorder.calls == expected)
}

@MainActor
@Test("Hotkey restore updates every setting field for its registration kind")
func hotkeyRouterRestoresPriorShortcuts() {
    let recorder = HotkeyRouterRecorder()
    let router = AppHotkeyRouter(actions: makeHotkeyRouterActions(recorder: recorder))
    var cases: [(AppHotkeyCoordinator.Kind, (AppSettings) -> Bool)] = [
        (.launcher, { $0.hotkeyKeyCode == 100 && $0.hotkeyModifiers == 200 }),
        (.finder, { $0.finderHotkeyKeyCode == 101 && $0.finderHotkeyModifiers == 201 }),
        (.translation, { $0.translateHotkeyKeyCode == 102 && $0.translateHotkeyModifiers == 202 }),
        (.textActions, { $0.textActionsHotkeyKeyCode == 103 && $0.textActionsHotkeyModifiers == 203 }),
        (.screenshotRegion, { $0.screenshot.regionHotkeyKeyCode == 104 && $0.screenshot.regionHotkeyModifiers == 204 }),
        (.screenshotScrolling, { $0.screenshot.scrollingHotkeyKeyCode == 105 && $0.screenshot.scrollingHotkeyModifiers == 205 }),
        (.screenshotEdit, { $0.screenshot.editHotkeyKeyCode == 106 && $0.screenshot.editHotkeyModifiers == 206 }),
        (.screenshotWindow, { $0.screenshot.windowHotkeyKeyCode == 107 && $0.screenshot.windowHotkeyModifiers == 207 }),
        (.screenshotDisplay, { $0.screenshot.displayHotkeyKeyCode == 108 && $0.screenshot.displayHotkeyModifiers == 208 }),
        (.recordingDisplay, { $0.recording.displayHotkeyKeyCode == 109 && $0.recording.displayHotkeyModifiers == 209 }),
        (.recordingRegion, { $0.recording.regionHotkeyKeyCode == 110 && $0.recording.regionHotkeyModifiers == 210 }),
        (.recordingWindow, { $0.recording.windowHotkeyKeyCode == 111 && $0.recording.windowHotkeyModifiers == 211 }),
        (.recordingPause, { $0.recording.pauseHotkeyKeyCode == 112 && $0.recording.pauseHotkeyModifiers == 212 }),
        (.recordingStop, { $0.recording.stopHotkeyKeyCode == 113 && $0.recording.stopHotkeyModifiers == 213 }),
        (.recordingFrame, { $0.recording.frameHotkeyKeyCode == 114 && $0.recording.frameHotkeyModifiers == 214 }),
        (.recordingMagnifier, { $0.recording.magnifierHotkeyKeyCode == 115 && $0.recording.magnifierHotkeyModifiers == 215 }),
        (.upload, { $0.fileHosting.uploadHotkeyKeyCode == 116 && $0.fileHosting.uploadHotkeyModifiers == 216 }),
        (.whiteboard, { $0.whiteboard.hotkeyKeyCode == 117 && $0.whiteboard.hotkeyModifiers == 217 }),
    ]
    #if MEOW_VOICE
    cases.append((.speech, { $0.speech.hotkeyKeyCode == 118 && $0.speech.hotkeyModifiers == 218 }))
    #endif

    for (offset, (kind, isRestored)) in cases.enumerated() {
        let keyCode = UInt32(100 + offset)
        let modifiers = UInt32(200 + offset)
        router.makeCoordinatorActions().restore(kind, keyCode, modifiers)
        #expect(isRestored(recorder.settings))
    }

    #expect(recorder.settingsUpdates == cases.count)
}

@MainActor
@Test("Hotkey registration results preserve error and conflict feedback")
func hotkeyRouterReportsRegistrationResults() {
    let recorder = HotkeyRouterRecorder()
    recorder.settings.textActionsHotkeyKeyCode = 37
    recorder.settings.textActionsHotkeyModifiers = 2048
    let router = AppHotkeyRouter(actions: makeHotkeyRouterActions(recorder: recorder))
    let actions = router.makeCoordinatorActions()

    actions.registrationSucceeded(.finder)
    actions.registrationSucceeded(.whiteboard)
    actions.registrationFailure(.finder, -9876)
    actions.registrationFailure(.textActions, -9877)
    actions.registrationFailure(.whiteboard, -9878)

    #expect(recorder.calls == [
        "finderError:nil",
        "whiteboardError:nil",
        "finderError:\(String(format: L10n.prefsFinderHotkeyError, -9876))",
        "textActionsConflict:37:2048",
        "whiteboardError:\(String(format: L10n.whiteboardHotkeyError, -9878))",
    ])
}

@MainActor
private final class HotkeyRouterRecorder {
    var calls: [String] = []
    var settings = AppSettings.default
    var settingsUpdates = 0
}

@MainActor
private func makeHotkeyRouterActions(recorder: HotkeyRouterRecorder) -> AppHotkeyRouter.Actions {
    AppHotkeyRouter.Actions(
        settings: { recorder.settings },
        updateSettings: {
            recorder.settings = $0
            recorder.settingsUpdates += 1
        },
        toggleLauncher: { recorder.calls.append("toggleLauncher") },
        openFinder: { recorder.calls.append("openFinder") },
        translate: { recorder.calls.append("translate") },
        textActions: { recorder.calls.append("textActions") },
        scrollingScreenshot: { recorder.calls.append("scrollingScreenshot") },
        screenshot: { mode, edit, upload in
            recorder.calls.append("screenshot:\(mode.rawValue):\(edit):\(upload)")
        },
        recording: { recorder.calls.append("recording:\($0.rawValue)") },
        pauseRecording: { recorder.calls.append("pauseRecording") },
        stopRecording: { recorder.calls.append("stopRecording") },
        saveRecordingFrame: { recorder.calls.append("saveRecordingFrame") },
        toggleRecordingMagnifier: { recorder.calls.append("toggleRecordingMagnifier") },
        toggleWhiteboard: { recorder.calls.append("toggleWhiteboard") },
        speechPressed: { recorder.calls.append("speechPressed") },
        speechReleased: { recorder.calls.append("speechReleased") },
        setFinderRegistrationError: { recorder.calls.append("finderError:\($0 ?? "nil")") },
        setWhiteboardRegistrationError: { recorder.calls.append("whiteboardError:\($0 ?? "nil")") },
        presentTextActionsHotkeyConflict: { keyCode, modifiers in
            recorder.calls.append("textActionsConflict:\(keyCode):\(modifiers)")
        }
    )
}
