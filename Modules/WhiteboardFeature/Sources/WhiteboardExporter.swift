import AppKit
import CoreGraphics
import Foundation

enum WhiteboardExportError: LocalizedError {
    case unableToCreateContext
    case unableToEncodeImage
    case outputTooLarge

    var errorDescription: String? {
        switch self {
        case .unableToCreateContext:
            return String(localized: "whiteboard.error.export.context", bundle: .module)
        case .unableToEncodeImage:
            return String(localized: "whiteboard.error.export.encoding", bundle: .module)
        case .outputTooLarge:
            return String(localized: "whiteboard.error.export.too.large", bundle: .module)
        }
    }
}

enum WhiteboardExporter {
    static func png(
        document: WhiteboardDocument,
        scale: CGFloat = 2,
        background: WhiteboardOutputBackgroundStyle = .transparent,
        image: (UUID?) -> CGImage?
    ) throws -> Data {
        let contentBounds = bounds(for: document).insetBy(dx: -40, dy: -40)
        let width = max(1, Int(ceil(contentBounds.width * scale)))
        let height = max(1, Int(ceil(contentBounds.height * scale)))
        guard width <= 32_768,
              height <= 32_768,
              Double(width) * Double(height) <= 250_000_000
        else {
            throw WhiteboardExportError.outputTooLarge
        }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw WhiteboardExportError.unableToCreateContext
        }
        let outputRect = CGRect(x: 0, y: 0, width: width, height: height)
        switch background {
        case .transparent:
            context.clear(outputRect)
        case .paper:
            context.setFillColor(CGColor(
                red: 250 / 255,
                green: 250 / 255,
                blue: 247 / 255,
                alpha: 1
            ))
            context.fill(outputRect)
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -contentBounds.minX, y: -contentBounds.minY)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for element in document.elements where element.kind != .unknown {
            WhiteboardRenderer.draw(
                element: element,
                selected: false,
                image: image(element.imageResourceID),
                in: context
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let output = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])
        else {
            throw WhiteboardExportError.unableToEncodeImage
        }
        return data
    }

    static func svg(
        document: WhiteboardDocument,
        background: WhiteboardOutputBackgroundStyle = .transparent,
        imageData: (UUID?) -> Data?
    ) -> Data {
        let contentBounds = bounds(for: document).insetBy(dx: -40, dy: -40)
        var body = switch background {
        case .transparent:
            ""
        case .paper:
            "<rect x=\"\(number(contentBounds.minX))\" y=\"\(number(contentBounds.minY))\" width=\"\(number(contentBounds.width))\" height=\"\(number(contentBounds.height))\" fill=\"#FAFAF7\"/>\n"
        }
        for element in document.elements where element.kind != .unknown {
            body += svgElement(element, imageData: imageData)
        }
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(number(contentBounds.width))" height="\(number(contentBounds.height))" viewBox="\(number(contentBounds.minX)) \(number(contentBounds.minY)) \(number(contentBounds.width)) \(number(contentBounds.height))">
        \(body)</svg>
        """
        return Data(svg.utf8)
    }

    static func bounds(for document: WhiteboardDocument) -> CGRect {
        let visible = document.elements.filter { $0.kind != .unknown }
        guard let first = visible.first else {
            return CGRect(x: 0, y: 0, width: 1024, height: 768)
        }
        return visible.dropFirst().reduce(WhiteboardGeometry.renderedBounds(for: first)) {
            $0.union(WhiteboardGeometry.renderedBounds(for: $1))
        }
    }

    private static func svgElement(
        _ element: WhiteboardElement,
        imageData: (UUID?) -> Data?
    ) -> String {
        let frame = element.frame
        let stroke = escape(element.style.strokeHex)
        let fill = escape(element.style.fillHex ?? "none")
        let common = "stroke=\"\(stroke)\" fill=\"\(fill)\" stroke-width=\"\(number(element.style.lineWidth))\" opacity=\"\(number(element.style.opacity))\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
        let transform = element.rotation == 0
            ? ""
            : " transform=\"rotate(\(number(element.rotation * 180 / .pi)) \(number(frame.midX)) \(number(frame.midY)))\""
        switch element.kind {
        case .rectangle:
            return "<rect x=\"\(number(frame.minX))\" y=\"\(number(frame.minY))\" width=\"\(number(frame.width))\" height=\"\(number(frame.height))\" \(common)\(transform)/>\n"
        case .ellipse:
            return "<ellipse cx=\"\(number(frame.midX))\" cy=\"\(number(frame.midY))\" rx=\"\(number(frame.width / 2))\" ry=\"\(number(frame.height / 2))\" \(common)\(transform)/>\n"
        case .diamond:
            let points = "\(number(frame.midX)),\(number(frame.minY)) \(number(frame.maxX)),\(number(frame.midY)) \(number(frame.midX)),\(number(frame.maxY)) \(number(frame.minX)),\(number(frame.midY))"
            return "<polygon points=\"\(points)\" \(common)\(transform)/>\n"
        case .arrow, .line, .freehand:
            let points = element.points.map { "\(number($0.x)),\(number($0.y))" }.joined(separator: " ")
            let lineStyle = "stroke=\"\(stroke)\" fill=\"none\" stroke-width=\"\(number(element.style.lineWidth))\" opacity=\"\(number(element.style.opacity))\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
            var output = "<polyline points=\"\(points)\" \(lineStyle)\(transform)/>\n"
            if element.kind == .arrow,
               element.points.count >= 2,
               let endPoint = element.points.last?.cgPoint
            {
                let previous = element.points[element.points.count - 2].cgPoint
                let angle = atan2(endPoint.y - previous.y, endPoint.x - previous.x)
                let length = max(10, element.style.lineWidth * 4)
                let spread = Double.pi / 7
                let first = CGPoint(
                    x: endPoint.x - cos(angle - spread) * length,
                    y: endPoint.y - sin(angle - spread) * length
                )
                let second = CGPoint(
                    x: endPoint.x - cos(angle + spread) * length,
                    y: endPoint.y - sin(angle + spread) * length
                )
                output += "<path d=\"M \(number(first.x)) \(number(first.y)) L \(number(endPoint.x)) \(number(endPoint.y)) L \(number(second.x)) \(number(second.y))\" \(lineStyle)\(transform)/>\n"
            }
            return output
        case .text:
            let text = escape(element.text ?? "")
            return "<text x=\"\(number(frame.minX))\" y=\"\(number(frame.minY + element.style.fontSize))\" fill=\"\(stroke)\" font-family=\"-apple-system, sans-serif\" font-size=\"\(number(element.style.fontSize))\" opacity=\"\(number(element.style.opacity))\"\(transform)>\(text)</text>\n"
        case .image:
            guard let data = imageData(element.imageResourceID) else { return "" }
            return "<image x=\"\(number(frame.minX))\" y=\"\(number(frame.minY))\" width=\"\(number(frame.width))\" height=\"\(number(frame.height))\" href=\"data:image/png;base64,\(data.base64EncodedString())\" opacity=\"\(number(element.style.opacity))\"\(transform)/>\n"
        case .unknown:
            return ""
        }
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
