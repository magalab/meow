import AppKit
import CoreGraphics

enum WhiteboardRenderer {
    static func draw(
        element: WhiteboardElement,
        selected: Bool,
        image: CGImage? = nil,
        in context: CGContext
    ) {
        context.saveGState()
        context.setAlpha(CGFloat(element.style.opacity))
        context.setLineWidth(CGFloat(element.style.lineWidth))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(NSColor(whiteboardHex: element.style.strokeHex).cgColor)
        if let fillHex = element.style.fillHex {
            context.setFillColor(NSColor(whiteboardHex: fillHex).cgColor)
        }

        let frame = element.frame
        if element.rotation != 0 {
            context.translateBy(x: frame.midX, y: frame.midY)
            context.rotate(by: CGFloat(element.rotation))
            context.translateBy(x: -frame.midX, y: -frame.midY)
        }

        switch element.kind {
        case .rectangle:
            drawPath(CGPath(rect: frame, transform: nil), element: element, in: context)
        case .ellipse:
            drawPath(CGPath(ellipseIn: frame, transform: nil), element: element, in: context)
        case .diamond:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: frame.midX, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.midY))
            path.addLine(to: CGPoint(x: frame.midX, y: frame.maxY))
            path.addLine(to: CGPoint(x: frame.minX, y: frame.midY))
            path.closeSubpath()
            drawPath(path, element: element, in: context)
        case .arrow, .line:
            drawLine(element, arrowhead: element.kind == .arrow, in: context)
        case .freehand:
            drawFreehand(element, in: context)
        case .text:
            drawText(element)
        case .image:
            if let image {
                let nsImage = NSImage(cgImage: image, size: frame.size)
                nsImage.draw(in: frame)
            }
        case .unknown:
            break
        }

        if selected {
            context.setAlpha(1)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [5, 4])
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.stroke(frame.insetBy(dx: -5, dy: -5))
            context.setLineDash(phase: 0, lengths: [])
        }
        context.restoreGState()
    }

    static func drawDraft(
        kind: WhiteboardElementKind,
        start: CGPoint,
        current: CGPoint,
        points: [CGPoint],
        style: WhiteboardElementStyle,
        in context: CGContext
    ) {
        let frame = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        let draftPoints: [CGPoint]
        if kind == .arrow || kind == .line {
            draftPoints = [start, current]
        } else {
            draftPoints = points
        }
        let draft = WhiteboardElement(
            kind: kind,
            origin: WhiteboardPoint(frame.origin),
            size: WhiteboardSize(width: frame.width, height: frame.height),
            points: draftPoints.map(WhiteboardPoint.init),
            style: style
        )
        draw(element: draft, selected: false, in: context)
    }

    private static func drawPath(
        _ path: CGPath,
        element: WhiteboardElement,
        in context: CGContext
    ) {
        context.addPath(path)
        if element.style.fillHex != nil {
            context.drawPath(using: .fillStroke)
        } else {
            context.strokePath()
        }
    }

    private static func drawFreehand(_ element: WhiteboardElement, in context: CGContext) {
        guard let first = element.points.first?.cgPoint else { return }
        context.beginPath()
        context.move(to: first)
        for point in element.points.dropFirst() {
            context.addLine(to: point.cgPoint)
        }
        context.strokePath()
    }

    private static func drawLine(
        _ element: WhiteboardElement,
        arrowhead: Bool,
        in context: CGContext
    ) {
        guard element.points.count >= 2 else { return }
        let start = element.points[0].cgPoint
        let previous = element.points[element.points.count - 2].cgPoint
        let end = element.points[element.points.count - 1].cgPoint
        context.beginPath()
        context.move(to: start)
        for point in element.points.dropFirst() {
            context.addLine(to: point.cgPoint)
        }
        context.strokePath()

        guard arrowhead else { return }
        let angle = atan2(end.y - previous.y, end.x - previous.x)
        let length = max(10, CGFloat(element.style.lineWidth) * 4)
        let spread = CGFloat.pi / 7
        context.beginPath()
        context.move(to: end)
        context.addLine(to: CGPoint(
            x: end.x - cos(angle - spread) * length,
            y: end.y - sin(angle - spread) * length
        ))
        context.move(to: end)
        context.addLine(to: CGPoint(
            x: end.x - cos(angle + spread) * length,
            y: end.y - sin(angle + spread) * length
        ))
        context.strokePath()
    }

    private static func drawText(_ element: WhiteboardElement) {
        guard let text = element.text, !text.isEmpty else { return }
        let color = NSColor(whiteboardHex: element.style.strokeHex)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: CGFloat(element.style.fontSize)),
        ]
        NSString(string: text).draw(
            in: element.frame,
            withAttributes: attributes
        )
    }
}

extension NSColor {
    convenience init(whiteboardHex value: String) {
        let cleaned = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let parsed = UInt64(cleaned, radix: 16) ?? 0x1F2937
        if cleaned.count == 8 {
            self.init(
                calibratedRed: CGFloat((parsed >> 24) & 0xFF) / 255,
                green: CGFloat((parsed >> 16) & 0xFF) / 255,
                blue: CGFloat((parsed >> 8) & 0xFF) / 255,
                alpha: CGFloat(parsed & 0xFF) / 255
            )
        } else {
            self.init(
                calibratedRed: CGFloat((parsed >> 16) & 0xFF) / 255,
                green: CGFloat((parsed >> 8) & 0xFF) / 255,
                blue: CGFloat(parsed & 0xFF) / 255,
                alpha: 1
            )
        }
    }

    var whiteboardHexString: String {
        guard let color = usingColorSpace(.sRGB) else { return "#1F2937" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}
