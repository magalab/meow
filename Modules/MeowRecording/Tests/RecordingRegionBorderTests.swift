import Foundation
import Testing
import MeowRecording

@Test("Recording region border positions on the selected display")
@MainActor
func recordingRegionBorderUsesDisplayOrigin() {
    let frame = RecordingRegionBorderController.globalFrame(
        for: CGRect(x: 24, y: 30, width: 300, height: 160),
        screenFrame: CGRect(x: -1440, y: 120, width: 1440, height: 900)
    )
    #expect(frame == CGRect(x: -1416, y: 150, width: 300, height: 160))
}
