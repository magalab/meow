import CoreGraphics
import CoreMedia
import CoreVideo
import Darwin
import QuartzCore

/// Runs only on RecordingWriter's serial queue. The on-screen preview window
/// never has to pass through ScreenCaptureKit's content filter.
final class RecordingMouseClickCompositor {
    private struct Click {
        let point: CGPoint
        let time: CFTimeInterval
    }

    private let captureRect: CGRect?
    private var color: (CGFloat, CGFloat, CGFloat)
    private var clicks: [Click] = []
    private var enabled: Bool
    private static let duration: CFTimeInterval = 0.42

    init(captureRect: CGRect?, enabled: Bool, theme: AppTheme) {
        self.captureRect = captureRect
        self.enabled = enabled
        color = Self.colorComponents(for: theme)
    }

    func apply(enabled: Bool, theme: AppTheme) {
        self.enabled = enabled
        if !enabled { clicks.removeAll() }
        color = Self.colorComponents(for: theme)
    }

    func recordClick(at point: CGPoint) {
        guard enabled, let captureRect, captureRect.contains(point) else { return }
        clicks.append(Click(point: point, time: CACurrentMediaTime()))
    }

    func composite(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        guard enabled,
              captureRect != nil,
              let sourceBuffer = sampleBuffer.imageBuffer,
              let formatDescription = sampleBuffer.formatDescription
        else { return sampleBuffer }

        let now = CACurrentMediaTime()
        clicks.removeAll { now - $0.time >= Self.duration }
        guard !clicks.isEmpty else { return sampleBuffer }

        let width = CVPixelBufferGetWidth(sourceBuffer)
        let height = CVPixelBufferGetHeight(sourceBuffer)
        var renderedBuffer: CVPixelBuffer?
        let surfaceAttributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: String],
        ]
        var creationStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            CVPixelBufferGetPixelFormatType(sourceBuffer),
            surfaceAttributes as CFDictionary,
            &renderedBuffer
        )
        if creationStatus != kCVReturnSuccess {
            creationStatus = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                CVPixelBufferGetPixelFormatType(sourceBuffer),
                nil,
                &renderedBuffer
            )
        }
        guard creationStatus == kCVReturnSuccess, let renderedBuffer else { return sampleBuffer }

        CVBufferPropagateAttachments(sourceBuffer, renderedBuffer)
        if CVPixelBufferGetPixelFormatType(sourceBuffer) == kCVPixelFormatType_32BGRA {
            guard drawBGRA(source: sourceBuffer, destination: renderedBuffer, now: now) else {
                return sampleBuffer
            }
        } else if CVPixelBufferGetPixelFormatType(sourceBuffer)
            == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            guard draw420v(source: sourceBuffer, destination: renderedBuffer, now: now) else {
                return sampleBuffer
            }
        } else if CVPixelBufferGetPixelFormatType(sourceBuffer)
            == kCVPixelFormatType_ARGB2101010LEPacked {
            guard drawL10r(source: sourceBuffer, destination: renderedBuffer, now: now) else {
                return sampleBuffer
            }
        } else {
            return sampleBuffer
        }

        var timing = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(
            sampleBuffer,
            at: 0,
            timingInfoOut: &timing
        ) == noErr else { return sampleBuffer }
        var renderedSample: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: renderedBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &renderedSample
        )
        return status == noErr ? renderedSample ?? sampleBuffer : sampleBuffer
    }

    private func draw420v(
        source: CVPixelBuffer,
        destination: CVPixelBuffer,
        now: CFTimeInterval
    ) -> Bool {
        guard let captureRect,
              CVPixelBufferGetPlaneCount(source) == 2,
              CVPixelBufferGetPlaneCount(destination) == 2,
              CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess
        else { return false }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }
        for plane in 0..<2 {
            guard let sourceBase = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                  let destinationBase = CVPixelBufferGetBaseAddressOfPlane(destination, plane)
            else { return false }
            let sourceStride = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
            let destinationStride = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
            let rowBytes = CVPixelBufferGetWidthOfPlane(source, plane) * (plane == 0 ? 1 : 2)
            for row in 0..<CVPixelBufferGetHeightOfPlane(source, plane) {
                memcpy(
                    destinationBase.advanced(by: row * destinationStride),
                    sourceBase.advanced(by: row * sourceStride),
                    rowBytes
                )
            }
        }
        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(destination, 0),
              let uvBase = CVPixelBufferGetBaseAddressOfPlane(destination, 1)
        else { return false }
        let yBytes = yBase.assumingMemoryBound(to: UInt8.self)
        let uvBytes = uvBase.assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(destination, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(destination, 1)
        let imageSize = CGSize(width: width, height: height)
        let red = color.0
        let green = color.1
        let blue = color.2
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let targetY = 16 + 219 * luminance
        let targetCb = 128 + 112 * (blue - luminance) / (1 - 0.0722)
        let targetCr = 128 + 112 * (red - luminance) / (1 - 0.2126)
        for click in clicks {
            guard let center = Self.pixelCenter(
                for: click.point,
                captureRect: captureRect,
                imageSize: imageSize
            ) else { continue }
            let (scale, opacity) = animation(at: now - click.time)
            let radiusX = 19 * scale * CGFloat(width) / captureRect.width
            let radiusY = 19 * scale * CGFloat(height) / captureRect.height
            let inner = max(0, 1 - 1.5 / min(radiusX, radiusY))
            let outer = 1 + 1.5 / min(radiusX, radiusY)
            let minX = max(0, Int(floor(center.x - radiusX * outer)))
            let maxX = min(width - 1, Int(ceil(center.x + radiusX * outer)))
            let minY = max(0, Int(floor(center.y - radiusY * outer)))
            let maxY = min(height - 1, Int(ceil(center.y + radiusY * outer)))
            guard minX <= maxX, minY <= maxY else { continue }
            for y in minY...maxY {
                for x in minX...maxX {
                    let dx = (CGFloat(x) + 0.5 - center.x) / radiusX
                    let dy = (CGFloat(y) + 0.5 - center.y) / radiusY
                    let distance = sqrt(dx * dx + dy * dy)
                    let alpha: CGFloat
                    if distance >= inner && distance <= outer {
                        alpha = 0.95 * opacity
                    } else if distance < inner {
                        alpha = 0.14 * opacity
                    } else {
                        continue
                    }
                    let yIndex = (height - 1 - y) * yStride + x
                    yBytes[yIndex] = Self.blend(yBytes[yIndex], target: targetY, alpha: alpha)
                    if x.isMultiple(of: 2) && y.isMultiple(of: 2) {
                        let uvIndex = ((height - 1 - y) / 2) * uvStride + (x / 2) * 2
                        uvBytes[uvIndex] = Self.blend(uvBytes[uvIndex], target: targetCb, alpha: alpha)
                        uvBytes[uvIndex + 1] = Self.blend(uvBytes[uvIndex + 1], target: targetCr, alpha: alpha)
                    }
                }
            }
        }
        return true
    }

    private func drawL10r(
        source: CVPixelBuffer,
        destination: CVPixelBuffer,
        now: CFTimeInterval
    ) -> Bool {
        guard let captureRect,
              CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess
        else { return false }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }
        guard let sourceBase = CVPixelBufferGetBaseAddress(source),
              let destinationBase = CVPixelBufferGetBaseAddress(destination)
        else { return false }
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let sourceStride = CVPixelBufferGetBytesPerRow(source)
        let destinationStride = CVPixelBufferGetBytesPerRow(destination)
        for row in 0..<height {
            memcpy(
                destinationBase.advanced(by: row * destinationStride),
                sourceBase.advanced(by: row * sourceStride),
                width * 4
            )
        }
        let imageSize = CGSize(width: width, height: height)
        for click in clicks {
            guard let center = Self.pixelCenter(
                for: click.point,
                captureRect: captureRect,
                imageSize: imageSize
            ) else { continue }
            let (scale, opacity) = animation(at: now - click.time)
            let radiusX = 19 * scale * CGFloat(width) / captureRect.width
            let radiusY = 19 * scale * CGFloat(height) / captureRect.height
            let inner = max(0, 1 - 1.5 / min(radiusX, radiusY))
            let outer = 1 + 1.5 / min(radiusX, radiusY)
            let minX = max(0, Int(floor(center.x - radiusX * outer)))
            let maxX = min(width - 1, Int(ceil(center.x + radiusX * outer)))
            let minY = max(0, Int(floor(center.y - radiusY * outer)))
            let maxY = min(height - 1, Int(ceil(center.y + radiusY * outer)))
            guard minX <= maxX, minY <= maxY else { continue }
            for y in minY...maxY {
                let row = destinationBase.advanced(by: (height - 1 - y) * destinationStride)
                    .assumingMemoryBound(to: UInt32.self)
                for x in minX...maxX {
                    let dx = (CGFloat(x) + 0.5 - center.x) / radiusX
                    let dy = (CGFloat(y) + 0.5 - center.y) / radiusY
                    let distance = sqrt(dx * dx + dy * dy)
                    let alpha: CGFloat
                    if distance >= inner && distance <= outer {
                        alpha = 0.95 * opacity
                    } else if distance < inner {
                        alpha = 0.14 * opacity
                    } else {
                        continue
                    }
                    let pixel = row[x]
                    let blue = CGFloat(pixel & 0x3FF)
                    let green = CGFloat((pixel >> 10) & 0x3FF)
                    let red = CGFloat((pixel >> 20) & 0x3FF)
                    let newBlue = UInt32(clamping: Int((blue * (1 - alpha) + color.2 * 1023 * alpha).rounded()))
                    let newGreen = UInt32(clamping: Int((green * (1 - alpha) + color.1 * 1023 * alpha).rounded()))
                    let newRed = UInt32(clamping: Int((red * (1 - alpha) + color.0 * 1023 * alpha).rounded()))
                    row[x] = 0xC0000000
                        | (min(newRed, 1023) << 20)
                        | (min(newGreen, 1023) << 10)
                        | min(newBlue, 1023)
                }
            }
        }
        return true
    }

    private static func blend(_ original: UInt8, target: CGFloat, alpha: CGFloat) -> UInt8 {
        UInt8(clamping: Int((CGFloat(original) * (1 - alpha) + target * alpha).rounded()))
    }

    private func drawBGRA(
        source: CVPixelBuffer,
        destination: CVPixelBuffer,
        now: CFTimeInterval
    ) -> Bool {
        guard let captureRect,
              CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess
        else { return false }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }
        guard let sourceBase = CVPixelBufferGetBaseAddress(source),
              let destinationBase = CVPixelBufferGetBaseAddress(destination)
        else { return false }

        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let sourceStride = CVPixelBufferGetBytesPerRow(source)
        let destinationStride = CVPixelBufferGetBytesPerRow(destination)
        for row in 0..<height {
            memcpy(
                destinationBase.advanced(by: row * destinationStride),
                sourceBase.advanced(by: row * sourceStride),
                width * 4
            )
        }
        guard let graphics = CGContext(
            data: destinationBase,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: destinationStride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return false }
        let imageSize = CGSize(width: width, height: height)
        let xScale = CGFloat(width) / captureRect.width
        let yScale = CGFloat(height) / captureRect.height
        for click in clicks {
            guard let center = Self.pixelCenter(
                for: click.point,
                captureRect: captureRect,
                imageSize: imageSize
            ) else { continue }
            let (scale, opacity) = animation(at: now - click.time)
            let ringRect = CGRect(
                x: center.x - 19 * scale * xScale,
                y: center.y - 19 * scale * yScale,
                width: 38 * scale * xScale,
                height: 38 * scale * yScale
            )
            graphics.setFillColor(CGColor(
                red: color.0,
                green: color.1,
                blue: color.2,
                alpha: 0.14 * opacity
            ))
            graphics.fillEllipse(in: ringRect)
            graphics.setStrokeColor(CGColor(
                red: color.0,
                green: color.1,
                blue: color.2,
                alpha: 0.95 * opacity
            ))
            graphics.setLineWidth(3 * scale * min(xScale, yScale))
            graphics.strokeEllipse(in: ringRect)
        }
        graphics.flush()
        return true
    }

    private func animation(at age: CFTimeInterval) -> (CGFloat, CGFloat) {
        let progress = min(1, max(0, age / Self.duration))
        let eased = 1 - pow(1 - progress, 2)
        return (CGFloat(0.7 + 0.95 * eased), CGFloat(0.95 * (1 - eased)))
    }

    static func pixelCenter(
        for point: CGPoint,
        captureRect: CGRect,
        imageSize: CGSize
    ) -> CGPoint? {
        guard captureRect.width > 0,
              captureRect.height > 0,
              captureRect.contains(point)
        else { return nil }
        return CGPoint(
            x: (point.x - captureRect.minX) * imageSize.width / captureRect.width,
            y: (point.y - captureRect.minY) * imageSize.height / captureRect.height
        )
    }

    private static func colorComponents(for theme: AppTheme) -> (CGFloat, CGFloat, CGFloat) {
        switch theme {
        case .gingerCat: return (0.85, 0.47, 0.24)
        case .mistBlue: return (0.23, 0.31, 0.54)
        case .graphiteAmber: return (0.77, 0.54, 0.23)
        case .mossInk: return (0.29, 0.42, 0.34)
        }
    }
}
