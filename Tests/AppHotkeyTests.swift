import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
@Test("Recording hotkeys preserve their historical conflict priority")
func recordingHotkeyRegistrationPriority() {
    #expect(
        AppHotkeyCoordinator.recordingHotkeyRegistrationOrder == [
            .recordingDisplay,
            .recordingFrame,
            .recordingMagnifier,
            .recordingRegion,
            .recordingWindow,
            .recordingPause,
            .recordingStop,
        ]
    )
}
