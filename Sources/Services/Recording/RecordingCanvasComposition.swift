@preconcurrency import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

enum RecordingCanvasBackgroundStyle: String, CaseIterable, Identifiable, Sendable {
    case solid
    case gradient
    case stripes
    case dots
    case glow

    var id: String { rawValue }
}

struct RecordingCanvasRGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

enum RecordingCanvasAspect: String, CaseIterable, Identifiable, Sendable {
    case original
    case widescreen
    case portrait
    case square
    case classic

    var id: String { rawValue }

    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .widescreen: return 16 / 9
        case .portrait: return 9 / 16
        case .square: return 1
        case .classic: return 4 / 3
        }
    }
}

struct RecordingCanvasSettings: Equatable, Sendable {
    var aspect: RecordingCanvasAspect = .original
    var margin: Double = 0.08
    var cornerRadius: Double = 0.04
    var red: Double = 0.12
    var green: Double = 0.12
    var blue: Double = 0.14
    var backgroundStyle: RecordingCanvasBackgroundStyle = .solid
    var accentColor: RecordingCanvasRGB?
}

struct RecordingCanvasLayout: Equatable {
    let renderSize: CGSize
    let contentRect: CGRect
    let cornerRadius: CGFloat

    init(sourceSize: CGSize, settings: RecordingCanvasSettings) {
        let sourceWidth = max(2, sourceSize.width)
        let sourceHeight = max(2, sourceSize.height)
        var width = sourceWidth
        var height = sourceHeight
        if let ratio = settings.aspect.ratio {
            if width / height > ratio {
                height = width / ratio
            } else {
                width = height * ratio
            }
        }
        width = CGFloat(max(2, (Int(width.rounded(.up)) + 1) & ~1))
        height = CGFloat(max(2, (Int(height.rounded(.up)) + 1) & ~1))
        renderSize = CGSize(width: width, height: height)

        let inset = min(width, height) * CGFloat(min(0.3, max(0, settings.margin)))
        let available = CGRect(x: inset, y: inset, width: width - 2 * inset, height: height - 2 * inset)
        let scale = min(available.width / sourceWidth, available.height / sourceHeight)
        let size = CGSize(width: sourceWidth * scale, height: sourceHeight * scale)
        contentRect = CGRect(
            x: (width - size.width) / 2,
            y: (height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        cornerRadius = min(size.width, size.height) * CGFloat(min(0.2, max(0, settings.cornerRadius)))
    }
}

enum RecordingCanvasComposition {
    // CIImage is an immutable rendering recipe; sharing it across frame callbacks is safe.
    private struct SharedBackground: @unchecked Sendable {
        let image: CIImage
    }

    static func make(
        asset: AVAsset,
        sourceSize: CGSize,
        settings: RecordingCanvasSettings
    ) async throws -> AVVideoComposition {
        let layout = RecordingCanvasLayout(sourceSize: sourceSize, settings: settings)
        let canvasRect = CGRect(origin: .zero, size: layout.renderSize)
        let contentRect = layout.contentRect
        let cornerRadius = layout.cornerRadius
        let sharedBackground = SharedBackground(image: backgroundImage(in: canvasRect, settings: settings))
        let composition = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<AVMutableVideoComposition, Error>) in
            AVMutableVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
                let source = request.sourceImage
                let extent = source.extent
                guard extent.width > 0, extent.height > 0 else {
                    request.finish(with: source, context: nil)
                    return
                }
                let scale = min(contentRect.width / extent.width, contentRect.height / extent.height)
                let target = CGRect(
                    x: (canvasRect.width - extent.width * scale) / 2,
                    y: (canvasRect.height - extent.height * scale) / 2,
                    width: extent.width * scale,
                    height: extent.height * scale
                )
                let image = source
                    .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                    .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .transformed(by: CGAffineTransform(translationX: target.minX, y: target.minY))
                let background = sharedBackground.image
                let output: CIImage
                if cornerRadius > 0 {
                    let mask = CIFilter.roundedRectangleGenerator()
                    mask.extent = target
                    mask.radius = Float(cornerRadius)
                    mask.color = .white
                    let blend = CIFilter.blendWithMask()
                    blend.inputImage = image
                    blend.backgroundImage = background
                    blend.maskImage = mask.outputImage
                    output = blend.outputImage ?? background
                } else {
                    output = image.composited(over: background)
                }
                request.finish(with: output.cropped(to: canvasRect), context: nil)
            }, completionHandler: { composition, error in
                if let composition {
                    continuation.resume(returning: composition)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "Meow.RecordingCanvas", code: 1))
                }
            })
        }
        composition.renderSize = layout.renderSize
        return composition
    }

    static func backgroundImage(in rect: CGRect, settings: RecordingCanvasSettings) -> CIImage {
        let base = CIColor(red: settings.red, green: settings.green, blue: settings.blue)
        let solid = CIImage(color: base).cropped(to: rect)
        switch settings.backgroundStyle {
        case .solid:
            return solid
        case .gradient:
            let gradient = CIFilter.linearGradient()
            gradient.point0 = CGPoint(x: rect.midX, y: rect.minY)
            gradient.point1 = CGPoint(x: rect.midX, y: rect.maxY)
            gradient.color0 = CIColor(
                red: max(0, settings.red - 0.06),
                green: max(0, settings.green - 0.06),
                blue: max(0, settings.blue - 0.06)
            )
            if let accent = settings.accentColor {
                gradient.color1 = CIColor(
                    red: settings.red * 0.82 + accent.red * 0.18,
                    green: settings.green * 0.82 + accent.green * 0.18,
                    blue: settings.blue * 0.82 + accent.blue * 0.18
                )
            } else {
                gradient.color1 = CIColor(
                    red: min(1, settings.red + 0.08),
                    green: min(1, settings.green + 0.08),
                    blue: min(1, settings.blue + 0.08)
                )
            }
            return (gradient.outputImage ?? solid).cropped(to: rect)
        case .glow:
            let luminance = 0.2126 * settings.red + 0.7152 * settings.green + 0.0722 * settings.blue
            let fallback = RecordingCanvasRGB(
                red: settings.red * 0.55 + (luminance > 0.5 ? 0 : 0.45),
                green: settings.green * 0.55 + (luminance > 0.5 ? 0 : 0.45),
                blue: settings.blue * 0.55 + (luminance > 0.5 ? 0 : 0.45)
            )
            let accent = settings.accentColor ?? fallback
            let glow = CIFilter.radialGradient()
            glow.center = CGPoint(
                x: rect.minX + rect.width * 0.9,
                y: rect.minY + rect.height * 0.9
            )
            glow.radius0 = 0
            glow.radius1 = Float(min(rect.width, rect.height) * 0.8)
            glow.color0 = CIColor(red: accent.red, green: accent.green, blue: accent.blue, alpha: 0.36)
            glow.color1 = CIColor(red: accent.red, green: accent.green, blue: accent.blue, alpha: 0)
            return (glow.outputImage?.composited(over: solid) ?? solid).cropped(to: rect)
        case .stripes, .dots:
            guard let tile = patternTile(for: settings.backgroundStyle, in: rect, settings: settings) else {
                return solid
            }
            let tiled = CIFilter.affineTile()
            tiled.inputImage = CIImage(cgImage: tile)
            tiled.transform = .identity
            return (tiled.outputImage ?? solid).cropped(to: rect)
        }
    }

    private static func patternTile(
        for style: RecordingCanvasBackgroundStyle,
        in rect: CGRect,
        settings: RecordingCanvasSettings
    ) -> CGImage? {
        let side = max(32, Int((min(rect.width, rect.height) * 0.055).rounded()))
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: settings.red, green: settings.green, blue: settings.blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let luminance = 0.2126 * settings.red + 0.7152 * settings.green + 0.0722 * settings.blue
        let ink = luminance > 0.5 ? 0.0 : 1.0
        let accent = settings.accentColor ?? RecordingCanvasRGB(red: ink, green: ink, blue: ink)
        context.setFillColor(CGColor(
            red: accent.red, green: accent.green, blue: accent.blue,
            alpha: settings.accentColor == nil ? 0.11 : 0.18
        ))
        switch style {
        case .stripes:
            let width = max(3, CGFloat(side) * 0.12)
            for offset in stride(from: -side, through: side * 2, by: side) {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: CGFloat(offset) + width, y: 0))
                path.addLine(to: CGPoint(x: CGFloat(offset) + CGFloat(side) + width, y: CGFloat(side)))
                path.addLine(to: CGPoint(x: CGFloat(offset) + CGFloat(side), y: CGFloat(side)))
                path.closeSubpath()
                context.addPath(path)
                context.fillPath()
            }
        case .dots:
            let diameter = max(4, CGFloat(side) * 0.14)
            context.fillEllipse(in: CGRect(
                x: (CGFloat(side) - diameter) / 2,
                y: (CGFloat(side) - diameter) / 2,
                width: diameter,
                height: diameter
            ))
        case .solid, .gradient, .glow:
            break
        }
        return context.makeImage()
    }
}
