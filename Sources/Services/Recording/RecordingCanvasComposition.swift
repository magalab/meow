@preconcurrency import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

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
    static func make(
        asset: AVAsset,
        sourceSize: CGSize,
        settings: RecordingCanvasSettings
    ) -> AVVideoComposition {
        let layout = RecordingCanvasLayout(sourceSize: sourceSize, settings: settings)
        let canvasRect = CGRect(origin: .zero, size: layout.renderSize)
        let contentRect = layout.contentRect
        let cornerRadius = layout.cornerRadius
        let red = settings.red
        let green = settings.green
        let blue = settings.blue
        let composition = AVMutableVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            let extent = source.extent
            guard extent.width > 0, extent.height > 0 else {
                request.finish(with: NSError(domain: "Meow.RecordingCanvas", code: 1))
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
            let background = CIImage(color: CIColor(
                red: CGFloat(red),
                green: CGFloat(green),
                blue: CGFloat(blue)
            )).cropped(to: canvasRect)
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
        }
        composition.renderSize = layout.renderSize
        return composition
    }

}
