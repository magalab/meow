import CoreGraphics
import CoreMedia
import CoreText
import CoreVideo
import Darwin

/// Composites the on-screen magnifier snapshot into the encoded frame. Access is
/// confined to RecordingWriter's serial queue.
final class RecordingMagnifierCompositor {
    private struct Overlay {
        let pixels: [UInt8] // premultiplied BGRA, top row first
        let width: Int
        let height: Int
        var frame: CGRect
    }

    let captureRect: CGRect?
    private var overlay: Overlay?
    private(set) var lastFailureReason: String?

    var isActive: Bool { overlay != nil }
    var overlayFrame: CGRect? { overlay?.frame }

    init(captureRect: CGRect?) {
        self.captureRect = captureRect
    }

    func setFrame(_ frame: CGRect) {
        overlay?.frame = frame
    }

    func setSnapshot(
        _ image: CGImage?, frame: CGRect, marker: CGPoint, zoom: Int, circular: Bool
    ) {
        guard let image, frame.width > 0, frame.height > 0 else {
            overlay = nil
            return
        }
        let width = max(1, Int((frame.width * 2).rounded()))
        let height = max(1, Int((frame.height * 2).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return }
        context.scaleBy(x: CGFloat(width) / frame.width, y: CGFloat(height) / frame.height)
        let bounds = CGRect(origin: .zero, size: frame.size)
        let insetBounds = bounds.insetBy(dx: 2, dy: 2)
        let outline = circular
            ? CGPath(ellipseIn: insetBounds, transform: nil)
            : CGPath(roundedRect: insetBounds, cornerWidth: 16, cornerHeight: 16, transform: nil)

        context.saveGState()
        context.addPath(outline)
        context.clip()
        context.setFillColor(CGColor(gray: 0.15, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)

        let center = CGPoint(
            x: min(max(0, marker.x), 1) * bounds.width,
            y: min(max(0, marker.y), 1) * bounds.height
        )
        let crosshair = CGMutablePath()
        crosshair.move(to: CGPoint(x: center.x - 13, y: center.y))
        crosshair.addLine(to: CGPoint(x: center.x + 13, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - 13))
        crosshair.addLine(to: CGPoint(x: center.x, y: center.y + 13))
        context.addPath(crosshair)
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.8))
        context.setLineWidth(2)
        context.strokePath()
        context.addPath(crosshair)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(1)
        context.strokePath()

        let labelRect = CGRect(
            x: circular ? bounds.width * 0.22 : 14, y: 12, width: 58, height: 25
        )
        context.addPath(CGPath(
            roundedRect: labelRect.insetBy(dx: -5, dy: -2),
            cornerWidth: 7, cornerHeight: 7, transform: nil
        ))
        context.setFillColor(CGColor(gray: 0, alpha: 0.7))
        context.fillPath()
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 16, nil)
        let attributes: [String: Any] = [
            kCTFontAttributeName as String: font,
            kCTForegroundColorAttributeName as String: CGColor(gray: 1, alpha: 1),
        ]
        if let text = CFAttributedStringCreate(
            kCFAllocatorDefault, "\(zoom)×" as CFString, attributes as CFDictionary
        ) {
            context.textPosition = CGPoint(x: labelRect.minX, y: labelRect.minY + 4)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        context.restoreGState()

        context.addPath(outline)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
        context.setLineWidth(4)
        context.strokePath()
        setImage(context.makeImage(), frame: frame)
    }

    func setImage(_ image: CGImage?, frame: CGRect) {
        guard let image, frame.width > 0, frame.height > 0 else {
            overlay = nil
            return
        }
        let width = image.width
        let height = image.height
        let stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)
        let created = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: stride,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        overlay = created ? Overlay(pixels: pixels, width: width, height: height, frame: frame) : nil
    }

    func composite(_ sample: CMSampleBuffer) -> CMSampleBuffer {
        lastFailureReason = nil
        guard let overlay, let captureRect else { return sample }
        guard overlay.frame.intersects(captureRect) else { return fail("outside capture area", sample) }
        guard let source = sample.imageBuffer else { return fail("missing image buffer", sample) }

        let pixelFormat = CVPixelBufferGetPixelFormatType(source)
        guard pixelFormat == kCVPixelFormatType_32BGRA
            || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || pixelFormat == kCVPixelFormatType_ARGB2101010LEPacked
        else { return fail("unsupported pixel format \(pixelFormat)", sample) }
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        var destination: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: String]]
        var status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, pixelFormat, attributes as CFDictionary, &destination
        )
        if status != kCVReturnSuccess {
            status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, nil, &destination)
        }
        guard status == kCVReturnSuccess, let destination else {
            return fail("pixel buffer allocation \(status)", sample)
        }
        let sourceLockStatus = CVPixelBufferLockBaseAddress(source, .readOnly)
        guard sourceLockStatus == kCVReturnSuccess else {
            return fail("source buffer lock \(sourceLockStatus)", sample)
        }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        let destinationLockStatus = CVPixelBufferLockBaseAddress(destination, [])
        guard destinationLockStatus == kCVReturnSuccess else {
            return fail("destination buffer lock \(destinationLockStatus)", sample)
        }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }

        let planeCount = CVPixelBufferGetPlaneCount(source)
        for plane in 0..<max(1, planeCount) {
            let sourceBase = planeCount == 0 ? CVPixelBufferGetBaseAddress(source) : CVPixelBufferGetBaseAddressOfPlane(source, plane)
            let destinationBase = planeCount == 0 ? CVPixelBufferGetBaseAddress(destination) : CVPixelBufferGetBaseAddressOfPlane(destination, plane)
            guard let sourceBase, let destinationBase else {
                return fail("missing plane \(plane) base address", sample)
            }
            let sourceStride = planeCount == 0 ? CVPixelBufferGetBytesPerRow(source) : CVPixelBufferGetBytesPerRowOfPlane(source, plane)
            let destinationStride = planeCount == 0 ? CVPixelBufferGetBytesPerRow(destination) : CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
            let rowBytes = planeCount == 0 ? width * 4 : CVPixelBufferGetWidthOfPlane(source, plane) * (plane == 0 ? 1 : 2)
            let rows = planeCount == 0 ? height : CVPixelBufferGetHeightOfPlane(source, plane)
            for row in 0..<rows {
                memcpy(destinationBase.advanced(by: row * destinationStride),
                       sourceBase.advanced(by: row * sourceStride), rowBytes)
            }
        }

        let scaleX = CGFloat(width) / captureRect.width
        let scaleY = CGFloat(height) / captureRect.height
        let minX = max(0, Int(floor((overlay.frame.minX - captureRect.minX) * scaleX)))
        let maxX = min(width, Int(ceil((overlay.frame.maxX - captureRect.minX) * scaleX)))
        let minY = max(0, Int(floor((captureRect.maxY - overlay.frame.maxY) * scaleY)))
        let maxY = min(height, Int(ceil((captureRect.maxY - overlay.frame.minY) * scaleY)))
        guard minX < maxX, minY < maxY else { return fail("empty pixel intersection", sample) }
        let packedBase = CVPixelBufferGetBaseAddress(destination)?.assumingMemoryBound(to: UInt8.self)
        let packedStride = CVPixelBufferGetBytesPerRow(destination)
        let yPixels = planeCount == 2
            ? CVPixelBufferGetBaseAddressOfPlane(destination, 0)?.assumingMemoryBound(to: UInt8.self) : nil
        let uvPixels = planeCount == 2
            ? CVPixelBufferGetBaseAddressOfPlane(destination, 1)?.assumingMemoryBound(to: UInt8.self) : nil
        let yStride = planeCount == 2 ? CVPixelBufferGetBytesPerRowOfPlane(destination, 0) : 0
        let uvStride = planeCount == 2 ? CVPixelBufferGetBytesPerRowOfPlane(destination, 1) : 0
        let sourceXs = (minX..<maxX).map { x -> Int in
            let globalX = captureRect.minX + (CGFloat(x) + 0.5) / scaleX
            let u = (globalX - overlay.frame.minX) / overlay.frame.width
            return u >= 0 && u < 1 ? min(overlay.width - 1, Int(u * CGFloat(overlay.width))) : -1
        }
        for y in minY..<maxY {
            let globalY = captureRect.maxY - (CGFloat(y) + 0.5) / scaleY
            let v = (overlay.frame.maxY - globalY) / overlay.frame.height
            guard v >= 0, v < 1 else { continue }
            let sy = min(overlay.height - 1, Int(v * CGFloat(overlay.height)))
            for (offset, sx) in sourceXs.enumerated() {
                guard sx >= 0 else { continue }
                let x = minX + offset
                let index = (sy * overlay.width + sx) * 4
                let alpha = CGFloat(overlay.pixels[index + 3]) / 255
                guard alpha > 0 else { continue }
                let blue = CGFloat(overlay.pixels[index]) / 255 / alpha
                let green = CGFloat(overlay.pixels[index + 1]) / 255 / alpha
                let red = CGFloat(overlay.pixels[index + 2]) / 255 / alpha
                if pixelFormat == kCVPixelFormatType_32BGRA {
                    guard let packedBase else { continue }
                    let p = packedBase.advanced(by: y * packedStride + x * 4)
                    p[0] = Self.blend(p[0], blue * 255, alpha)
                    p[1] = Self.blend(p[1], green * 255, alpha)
                    p[2] = Self.blend(p[2], red * 255, alpha)
                    p[3] = 255
                } else if pixelFormat == kCVPixelFormatType_ARGB2101010LEPacked {
                    guard let packedBase else { continue }
                    let p = UnsafeMutableRawPointer(packedBase.advanced(by: y * packedStride))
                        .assumingMemoryBound(to: UInt32.self)
                    let old = p[x]
                    let b = UInt32(Self.blend10(old & 0x3FF, blue, alpha))
                    let g = UInt32(Self.blend10((old >> 10) & 0x3FF, green, alpha))
                    let r = UInt32(Self.blend10((old >> 20) & 0x3FF, red, alpha))
                    p[x] = 0xC0000000 | (r << 20) | (g << 10) | b
                } else {
                    guard let yPixels, let uvPixels
                    else { continue }
                    let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                    let targetY = 16 + 219 * luminance
                    let yIndex = y * yStride + x
                    yPixels[yIndex] = Self.blend(yPixels[yIndex], targetY, alpha)
                    if x.isMultiple(of: 2) && y.isMultiple(of: 2) {
                        let uvIndex = (y / 2) * uvStride + x
                        uvPixels[uvIndex] = Self.blend(uvPixels[uvIndex], 128 + 112 * (blue - luminance) / (1 - 0.0722), alpha)
                        uvPixels[uvIndex + 1] = Self.blend(uvPixels[uvIndex + 1], 128 + 112 * (red - luminance) / (1 - 0.2126), alpha)
                    }
                }
            }
        }
        CVBufferPropagateAttachments(source, destination)
        var timing = CMSampleTimingInfo()
        let timingStatus = CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing)
        guard timingStatus == noErr else { return fail("sample timing \(timingStatus)", sample) }
        var destinationFormat: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: destination,
            formatDescriptionOut: &destinationFormat
        )
        guard formatStatus == noErr, let destinationFormat else {
            return fail("destination format description \(formatStatus)", sample)
        }
        var output: CMSampleBuffer?
        let result = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: destination,
            formatDescription: destinationFormat, sampleTiming: &timing, sampleBufferOut: &output
        )
        guard result == noErr, let output else {
            return fail("composited sample creation \(result)", sample)
        }
        return output
    }

    private func fail(_ reason: String, _ sample: CMSampleBuffer) -> CMSampleBuffer {
        lastFailureReason = reason
        return sample
    }

    private static func blend(_ original: UInt8, _ target: CGFloat, _ alpha: CGFloat) -> UInt8 {
        UInt8(clamping: Int((CGFloat(original) * (1 - alpha) + target * alpha).rounded()))
    }

    private static func blend10(_ original: UInt32, _ target: CGFloat, _ alpha: CGFloat) -> Int {
        min(1023, max(0, Int((CGFloat(original) * (1 - alpha) + target * 1023 * alpha).rounded())))
    }
}
