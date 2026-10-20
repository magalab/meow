import CoreGraphics
import MeowCapture
import Testing

struct CapturePixelMagnifierGeometryTests {
    @Test("Pixel magnifier maps local points using each display scale")
    func mapsDisplayScale() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        let standard = CapturePixelMagnifierGeometry.sampleRect(
            at: CGPoint(x: 50, y: 40), in: bounds,
            imageWidth: 100, imageHeight: 80, scale: 1
        )
        let retina = CapturePixelMagnifierGeometry.sampleRect(
            at: CGPoint(x: 50, y: 40), in: bounds,
            imageWidth: 200, imageHeight: 160, scale: 2
        )
        #expect(standard == CGRect(x: 44, y: 34, width: 13, height: 13))
        #expect(retina == CGRect(x: 94, y: 74, width: 13, height: 13))
    }

    @Test("Pixel magnifier remains within image and screen edges")
    func clampsAtEdges() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        let sample = CapturePixelMagnifierGeometry.sampleRect(
            at: CGPoint(x: 100, y: 0), in: bounds,
            imageWidth: 200, imageHeight: 160, scale: 2
        )
        let frame = CapturePixelMagnifierGeometry.frame(
            near: CGPoint(x: 98, y: 2), in: CGRect(x: 0, y: 0, width: 300, height: 200)
        )
        #expect(sample == CGRect(x: 187, y: 147, width: 13, height: 13))
        #expect(frame.minX >= 0 && frame.maxX <= 300)
        #expect(frame.minY >= 0 && frame.maxY <= 200)
    }
}
