import CoreGraphics
import Foundation

enum WhiteboardResizeHandle: CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

enum WhiteboardGeometry {
    static func selectionBounds(for elements: [WhiteboardElement]) -> CGRect? {
        guard let first = elements.first else { return nil }
        return elements.dropFirst().reduce(renderedBounds(for: first)) {
            $0.union(renderedBounds(for: $1))
        }
    }

    static func renderedBounds(for element: WhiteboardElement) -> CGRect {
        guard element.rotation != 0 else { return element.frame }
        let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
        let corners = [
            CGPoint(x: element.frame.minX, y: element.frame.minY),
            CGPoint(x: element.frame.maxX, y: element.frame.minY),
            CGPoint(x: element.frame.maxX, y: element.frame.maxY),
            CGPoint(x: element.frame.minX, y: element.frame.maxY),
        ].map { rotated($0, around: center, by: CGFloat(element.rotation)) }
        return bounds(for: corners)
    }

    static func contains(
        _ point: CGPoint,
        in element: WhiteboardElement,
        tolerance: CGFloat
    ) -> Bool {
        let frame = element.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let localPoint = rotated(point, around: center, by: -CGFloat(element.rotation))

        switch element.kind {
        case .ellipse:
            let radiusX = max(0.5, frame.width / 2 + tolerance)
            let radiusY = max(0.5, frame.height / 2 + tolerance)
            let dx = (localPoint.x - frame.midX) / radiusX
            let dy = (localPoint.y - frame.midY) / radiusY
            return dx * dx + dy * dy <= 1
        case .diamond:
            let radiusX = max(0.5, frame.width / 2 + tolerance)
            let radiusY = max(0.5, frame.height / 2 + tolerance)
            return abs(localPoint.x - frame.midX) / radiusX
                + abs(localPoint.y - frame.midY) / radiusY <= 1
        case .arrow, .line, .freehand:
            guard element.points.count >= 2 else { return false }
            return zip(element.points, element.points.dropFirst()).contains { first, second in
                distance(from: localPoint, toSegmentFrom: first.cgPoint, to: second.cgPoint)
                    <= tolerance + CGFloat(element.style.lineWidth) / 2
            }
        case .rectangle, .text, .image:
            return frame.insetBy(dx: -tolerance, dy: -tolerance).contains(localPoint)
        case .unknown:
            return false
        }
    }

    static func transformed(
        _ element: WhiteboardElement,
        from sourceBounds: CGRect,
        to targetBounds: CGRect
    ) -> WhiteboardElement {
        guard sourceBounds.width > 0, sourceBounds.height > 0 else { return element }
        let scaleX = targetBounds.width / sourceBounds.width
        let scaleY = targetBounds.height / sourceBounds.height
        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: targetBounds.minX + (point.x - sourceBounds.minX) * scaleX,
                y: targetBounds.minY + (point.y - sourceBounds.minY) * scaleY
            )
        }

        var value = element
        let mappedOrigin = map(element.origin.cgPoint)
        value.origin = WhiteboardPoint(mappedOrigin)
        value.size = WhiteboardSize(
            width: max(1, element.size.width * scaleX),
            height: max(1, element.size.height * scaleY)
        )
        value.points = element.points.map { WhiteboardPoint(map($0.cgPoint)) }
        value.updatedAt = Date()
        return value
    }

    static func rotated(
        _ element: WhiteboardElement,
        by angle: CGFloat,
        around pivot: CGPoint
    ) -> WhiteboardElement {
        var value = element
        let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
        let rotatedCenter = rotated(center, around: pivot, by: angle)
        value.origin = WhiteboardPoint(
            x: rotatedCenter.x - element.frame.width / 2,
            y: rotatedCenter.y - element.frame.height / 2
        )
        value.points = element.points.map {
            WhiteboardPoint(rotated($0.cgPoint, around: pivot, by: angle))
        }
        value.rotation = normalizedAngle(element.rotation + Double(angle))
        value.updatedAt = Date()
        return value
    }

    static func resizeHandlePositions(in bounds: CGRect) -> [WhiteboardResizeHandle: CGPoint] {
        [
            .topLeft: CGPoint(x: bounds.minX, y: bounds.minY),
            .top: CGPoint(x: bounds.midX, y: bounds.minY),
            .topRight: CGPoint(x: bounds.maxX, y: bounds.minY),
            .right: CGPoint(x: bounds.maxX, y: bounds.midY),
            .bottomRight: CGPoint(x: bounds.maxX, y: bounds.maxY),
            .bottom: CGPoint(x: bounds.midX, y: bounds.maxY),
            .bottomLeft: CGPoint(x: bounds.minX, y: bounds.maxY),
            .left: CGPoint(x: bounds.minX, y: bounds.midY),
        ]
    }

    static func resizedBounds(
        _ original: CGRect,
        handle: WhiteboardResizeHandle,
        to point: CGPoint,
        minimumSize: CGFloat
    ) -> CGRect {
        var minX = original.minX
        var maxX = original.maxX
        var minY = original.minY
        var maxY = original.maxY
        switch handle {
        case .topLeft:
            minX = min(point.x, maxX - minimumSize)
            minY = min(point.y, maxY - minimumSize)
        case .top:
            minY = min(point.y, maxY - minimumSize)
        case .topRight:
            maxX = max(point.x, minX + minimumSize)
            minY = min(point.y, maxY - minimumSize)
        case .right:
            maxX = max(point.x, minX + minimumSize)
        case .bottomRight:
            maxX = max(point.x, minX + minimumSize)
            maxY = max(point.y, minY + minimumSize)
        case .bottom:
            maxY = max(point.y, minY + minimumSize)
        case .bottomLeft:
            minX = min(point.x, maxX - minimumSize)
            maxY = max(point.y, minY + minimumSize)
        case .left:
            minX = min(point.x, maxX - minimumSize)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func anchoredRotatedResizeBounds(
        original: CGRect,
        resized: CGRect,
        handle: WhiteboardResizeHandle,
        rotation: CGFloat
    ) -> CGRect {
        guard rotation != 0 else { return resized }
        let originalCenter = CGPoint(x: original.midX, y: original.midY)
        let resizedCenter = CGPoint(x: resized.midX, y: resized.midY)
        let originalAnchor = fixedAnchor(in: original, for: handle)
        let resizedAnchor = fixedAnchor(in: resized, for: handle)
        let originalWorldAnchor = rotated(
            originalAnchor,
            around: originalCenter,
            by: rotation
        )
        let resizedWorldAnchor = rotated(
            resizedAnchor,
            around: resizedCenter,
            by: rotation
        )
        return resized.offsetBy(
            dx: originalWorldAnchor.x - resizedWorldAnchor.x,
            dy: originalWorldAnchor.y - resizedWorldAnchor.y
        )
    }

    static func rotated(_ point: CGPoint, around center: CGPoint, by angle: CGFloat) -> CGPoint {
        guard angle != 0 else { return point }
        let translated = CGPoint(x: point.x - center.x, y: point.y - center.y)
        let cosine = cos(angle)
        let sine = sin(angle)
        return CGPoint(
            x: center.x + translated.x * cosine - translated.y * sine,
            y: center.y + translated.x * sine + translated.y * cosine
        )
    }

    private static func distance(
        from point: CGPoint,
        toSegmentFrom start: CGPoint,
        to end: CGPoint
    ) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let nearest = CGPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return hypot(point.x - nearest.x, point.y - nearest.y)
    }

    private static func bounds(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func normalizedAngle(_ value: Double) -> Double {
        let fullTurn = Double.pi * 2
        var result = value.truncatingRemainder(dividingBy: fullTurn)
        if result > Double.pi { result -= fullTurn }
        if result < -Double.pi { result += fullTurn }
        return result
    }

    private static func fixedAnchor(
        in bounds: CGRect,
        for handle: WhiteboardResizeHandle
    ) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: bounds.maxX, y: bounds.maxY)
        case .top: return CGPoint(x: bounds.midX, y: bounds.maxY)
        case .topRight: return CGPoint(x: bounds.minX, y: bounds.maxY)
        case .right: return CGPoint(x: bounds.minX, y: bounds.midY)
        case .bottomRight: return CGPoint(x: bounds.minX, y: bounds.minY)
        case .bottom: return CGPoint(x: bounds.midX, y: bounds.minY)
        case .bottomLeft: return CGPoint(x: bounds.maxX, y: bounds.minY)
        case .left: return CGPoint(x: bounds.maxX, y: bounds.midY)
        }
    }
}
