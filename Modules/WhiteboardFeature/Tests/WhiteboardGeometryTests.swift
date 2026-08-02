import CoreGraphics
import Foundation
import Testing
@testable import WhiteboardFeature

@Suite("Whiteboard geometry")
struct WhiteboardGeometryTests {
    @Test("Rotated elements use transformed hit testing and bounds")
    func rotatedHitTesting() {
        let element = WhiteboardElement(
            kind: .rectangle,
            origin: WhiteboardPoint(x: 0, y: 0),
            size: WhiteboardSize(width: 100, height: 20),
            rotation: .pi / 2
        )

        #expect(WhiteboardGeometry.contains(CGPoint(x: 50, y: 50), in: element, tolerance: 0))
        #expect(!WhiteboardGeometry.contains(CGPoint(x: 95, y: 10), in: element, tolerance: 0))
        let bounds = WhiteboardGeometry.renderedBounds(for: element)
        #expect(abs(bounds.width - 20) < 0.001)
        #expect(abs(bounds.height - 100) < 0.001)
    }

    @Test("Resize maps element points with the selection bounds")
    func resizeMapsPoints() {
        let line = WhiteboardElement(
            kind: .line,
            origin: WhiteboardPoint(x: 10, y: 20),
            size: WhiteboardSize(width: 100, height: 40),
            points: [WhiteboardPoint(x: 10, y: 20), WhiteboardPoint(x: 110, y: 60)]
        )

        let transformed = WhiteboardGeometry.transformed(
            line,
            from: CGRect(x: 10, y: 20, width: 100, height: 40),
            to: CGRect(x: 0, y: 0, width: 200, height: 80)
        )

        #expect(transformed.origin == WhiteboardPoint(x: 0, y: 0))
        #expect(transformed.size == WhiteboardSize(width: 200, height: 80))
        #expect(transformed.points == [WhiteboardPoint(x: 0, y: 0), WhiteboardPoint(x: 200, y: 80)])
    }

    @Test("Resize handles enforce a minimum size")
    func minimumResizeSize() {
        let result = WhiteboardGeometry.resizedBounds(
            CGRect(x: 0, y: 0, width: 100, height: 80),
            handle: .topLeft,
            to: CGPoint(x: 150, y: 120),
            minimumSize: 12
        )

        #expect(result.width == 12)
        #expect(result.height == 12)
    }
}
