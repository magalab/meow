import Foundation
import Testing
import MeowRecording

@Test("Recording magnifier placement remains continuous at screen edges")
@MainActor
func recordingMagnifierPlacement() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let size = CGSize(width: 300, height: 200)
    let middle = ScreenMagnifierController.panelFrame(
        near: CGPoint(x: 500, y: 350), visibleFrame: screen, preferredSize: size
    )
    #expect(middle.origin == CGPoint(x: 512, y: 138))
    let right = ScreenMagnifierController.panelFrame(
        near: CGPoint(x: 900, y: 350), visibleFrame: screen, preferredSize: size
    )
    #expect(right.origin == CGPoint(x: 692, y: 138))
    let bottom = ScreenMagnifierController.panelFrame(
        near: CGPoint(x: 500, y: 30), visibleFrame: screen, preferredSize: size
    )
    #expect(bottom.origin == CGPoint(x: 512, y: 8))
    let beforeEdge = ScreenMagnifierController.panelFrame(
        near: CGPoint(x: 679, y: 350), visibleFrame: screen, preferredSize: size
    )
    let afterEdge = ScreenMagnifierController.panelFrame(
        near: CGPoint(x: 681, y: 350), visibleFrame: screen, preferredSize: size
    )
    #expect(abs(beforeEdge.minX - afterEdge.minX) <= 2)
}

@Test("Recording magnifier crops the persistent stream around the pointer")
@MainActor
func recordingMagnifierStreamCrop() {
    let screen = CGRect(x: -1440, y: 100, width: 1440, height: 900)
    let image = CGSize(width: 2880, height: 1800)
    let capture = CGSize(width: 150, height: 100)
    let middle = ScreenMagnifierController.streamCropRect(
        centeredAt: CGPoint(x: -720, y: 550),
        in: screen, imageSize: image, captureSize: capture
    )
    #expect(middle == CGRect(x: 1290, y: 800, width: 300, height: 200))
    let edge = ScreenMagnifierController.streamCropRect(
        centeredAt: CGPoint(x: -1435, y: 995),
        in: screen, imageSize: image, captureSize: capture
    )
    #expect(edge == CGRect(x: 0, y: 1600, width: 300, height: 200))
    let smallDisplay = ScreenMagnifierController.streamCropRect(
        centeredAt: CGPoint(x: -290, y: 30),
        in: CGRect(x: -300, y: 20, width: 100, height: 70),
        imageSize: CGSize(width: 200, height: 140),
        captureSize: CGSize(width: 210, height: 140)
    )
    #expect(smallDisplay == CGRect(x: 0, y: 0, width: 200, height: 140))
}

@Test("Screen magnifier panel fits a small visible display area")
@MainActor
func screenMagnifierPanelFitsVisibleArea() {
    let visible = CGRect(x: -400, y: 80, width: 400, height: 260)
    let frame = ScreenMagnifierController.panelFrame(
        near: CGPoint(x: -2, y: 338),
        visibleFrame: visible,
        preferredSize: CGSize(width: 540, height: 360)
    )
    #expect(visible.contains(frame))
    #expect(frame.width < 540)
    #expect(abs(frame.width / frame.height - 1.5) < 0.001)
}
