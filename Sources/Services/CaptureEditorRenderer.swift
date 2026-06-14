import AppKit
import CoreImage
import Foundation

enum CaptureEditorRenderError: LocalizedError {
    case contextCreationFailed
    case imageCreationFailed

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed: return L10n.editorErrorContext
        case .imageCreationFailed: return L10n.editorErrorImage
        }
    }
}

enum CaptureEditorRenderer {
    static func render(
        source: CGImage,
        commands: [CaptureEditorCommand],
        cropRect: CGRect?,
        outputSize: CGSize? = nil
    ) throws -> CGImage {
        let sourceRect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let crop = (cropRect ?? sourceRect).standardized.intersection(sourceRect).integral
        let destinationSize = outputSize ?? crop.size
        let width = max(1, Int(destinationSize.width.rounded()))
        let height = max(1, Int(destinationSize.height.rounded()))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CaptureEditorRenderError.contextCreationFailed
        }

        context.interpolationQuality = .high
        context.scaleBy(x: CGFloat(width) / crop.width, y: CGFloat(height) / crop.height)
        context.translateBy(x: -crop.minX, y: -crop.minY)
        context.draw(source, in: sourceRect)

        let pixelated = makePixelatedImage(source)
        for command in commands {
            render(command, in: context, pixelatedSource: pixelated)
        }

        guard let image = context.makeImage() else {
            throw CaptureEditorRenderError.imageCreationFailed
        }
        return image
    }

    static func drawPreview(
        source: CGImage,
        commands: [CaptureEditorCommand],
        cropRect: CGRect?,
        in context: CGContext
    ) {
        let sourceRect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.draw(source, in: sourceRect)
        let pixelated = makePixelatedImage(source)
        for command in commands {
            render(command, in: context, pixelatedSource: pixelated)
        }

        if let cropRect {
            context.saveGState()
            context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            context.addRect(sourceRect)
            context.addRect(cropRect)
            context.drawPath(using: .eoFill)
            context.setStrokeColor(NSColor.systemYellow.cgColor)
            context.setLineWidth(2)
            context.stroke(cropRect)
            context.restoreGState()
        }
    }

    private static func render(
        _ command: CaptureEditorCommand,
        in context: CGContext,
        pixelatedSource: CGImage?
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        switch command {
        case let .rectangle(rect, color, width):
            applyStroke(color, width: width, context: context)
            context.stroke(rect)

        case let .ellipse(rect, color, width):
            applyStroke(color, width: width, context: context)
            context.strokeEllipse(in: rect)

        case let .arrow(start, end, color, width):
            applyStroke(color, width: width, context: context)
            context.move(to: start)
            context.addLine(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength = max(12, width * 4)
            let spread = CGFloat.pi / 7
            context.move(to: end)
            context.addLine(
                to: CGPoint(
                    x: end.x - headLength * cos(angle - spread),
                    y: end.y - headLength * sin(angle - spread)
                )
            )
            context.move(to: end)
            context.addLine(
                to: CGPoint(
                    x: end.x - headLength * cos(angle + spread),
                    y: end.y - headLength * sin(angle + spread)
                )
            )
            context.strokePath()

        case let .pen(points, color, width):
            guard let first = points.first else { return }
            applyStroke(color, width: width, context: context)
            context.move(to: first)
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()

        case let .text(origin, text, color, fontSize):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: color.nsColor,
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            attributed.draw(at: origin)
            NSGraphicsContext.restoreGraphicsState()

        case let .number(center, value, color, radius):
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.setFillColor(color.nsColor.cgColor)
            context.fillEllipse(in: rect)
            let text = "\(value)" as NSString
            let font = NSFont.monospacedDigitSystemFont(ofSize: radius * 1.1, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let size = text.size(withAttributes: attributes)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            text.draw(
                at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                withAttributes: attributes
            )
            NSGraphicsContext.restoreGraphicsState()

        case let .highlight(rect, color):
            context.setBlendMode(.multiply)
            context.setFillColor(color.nsColor.withAlphaComponent(0.32).cgColor)
            context.fill(rect)

        case let .mosaic(rect):
            guard let pixelatedSource else { return }
            context.clip(to: rect)
            context.draw(
                pixelatedSource,
                in: CGRect(x: 0, y: 0, width: pixelatedSource.width, height: pixelatedSource.height)
            )
        }
    }

    private static func applyStroke(
        _ color: CaptureEditorColor,
        width: CGFloat,
        context: CGContext
    ) {
        context.setStrokeColor(color.nsColor.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
    }

    private static func makePixelatedImage(_ source: CGImage) -> CGImage? {
        let input = CIImage(cgImage: source)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(18, forKey: kCIInputScaleKey)
        guard let output = filter.outputImage else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(
            output,
            from: input.extent
        )
    }
}
