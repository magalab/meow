import CoreGraphics
import Foundation

enum ScrollingCaptureAppendResult: Equatable {
    case appended
    case maximumHeight
    case maximumPixels
    case invalidFrame
}

final class ScrollingCaptureStitcher {
    private let maximumHeight: Int
    private let maximumPixels: Int
    private let batchSize: Int
    private(set) var width: Int
    private(set) var totalHeight: Int
    private var chunks: [CGImage]
    private var pendingStrips: [CGImage] = []

    init(
        firstFrame: CGImage,
        maximumHeight: Int,
        maximumPixels: Int,
        batchSize: Int = 12
    ) {
        self.maximumHeight = maximumHeight
        self.maximumPixels = maximumPixels
        self.batchSize = max(2, batchSize)
        width = firstFrame.width
        totalHeight = firstFrame.height
        chunks = [firstFrame]
    }

    var pixelSize: CGSize {
        CGSize(width: width, height: totalHeight)
    }

    var stripCount: Int {
        chunks.count + pendingStrips.count
    }

    func appendBottomRows(from frame: CGImage, count: Int) -> ScrollingCaptureAppendResult {
        guard frame.width == width, count > 0, count <= frame.height else {
            return .invalidFrame
        }
        let proposedHeight = totalHeight + count
        if maximumHeight > 0, proposedHeight > maximumHeight {
            return .maximumHeight
        }
        if maximumPixels > 0,
           Int64(width) * Int64(proposedHeight) > Int64(maximumPixels)
        {
            return .maximumPixels
        }
        let cropRect = CGRect(x: 0, y: frame.height - count, width: frame.width, height: count)
        guard let strip = frame.cropping(to: cropRect) else { return .invalidFrame }
        pendingStrips.append(strip)
        totalHeight = proposedHeight
        if pendingStrips.count >= batchSize {
            flushPendingStrips()
        }
        return .appended
    }

    func makeImage() -> CGImage? {
        flushPendingStrips()
        return Self.composeVertically(chunks)
    }

    func makeReducedImage(maximumPixels: Int = 20_000_000) -> CGImage? {
        flushPendingStrips()
        guard maximumPixels > 0, totalHeight > 0, width > 0 else { return nil }
        let currentPixels = Double(width) * Double(totalHeight)
        let scale = min(1, sqrt(Double(maximumPixels) / currentPixels))
        guard scale.isFinite, scale > 0 else { return nil }
        let outputWidth = max(1, Int((Double(width) * scale).rounded()))
        let outputHeight = max(1, Int((Double(totalHeight) * scale).rounded()))
        return Self.composeVertically(
            chunks,
            outputWidth: outputWidth,
            outputHeight: outputHeight
        )
    }

    func makePreview(maximumSize: CGSize = CGSize(width: 260, height: 420)) -> CGImage? {
        let allChunks = chunks + pendingStrips
        guard !allChunks.isEmpty, totalHeight > 0 else { return nil }
        let scale = min(
            maximumSize.width / CGFloat(width),
            maximumSize.height / CGFloat(totalHeight),
            1
        )
        let previewWidth = max(1, Int((CGFloat(width) * scale).rounded()))
        let previewHeight = max(1, Int((CGFloat(totalHeight) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: previewWidth,
            height: previewHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        var consumedHeight = 0
        for chunk in allChunks {
            let scaledHeight = CGFloat(chunk.height) * scale
            let y = CGFloat(previewHeight) - CGFloat(consumedHeight) * scale - scaledHeight
            context.draw(
                chunk,
                in: CGRect(x: 0, y: y, width: CGFloat(previewWidth), height: scaledHeight)
            )
            consumedHeight += chunk.height
        }
        return context.makeImage()
    }

    private func flushPendingStrips() {
        guard !pendingStrips.isEmpty else { return }
        if let combined = Self.composeVertically(pendingStrips) {
            chunks.append(combined)
        } else {
            chunks.append(contentsOf: pendingStrips)
        }
        pendingStrips.removeAll(keepingCapacity: true)
    }

    private static func composeVertically(_ images: [CGImage]) -> CGImage? {
        guard let first = images.first else { return nil }
        let width = first.width
        guard images.allSatisfy({ $0.width == width }) else { return nil }
        let height = images.reduce(0) { $0 + $1.height }
        return composeVertically(images, outputWidth: width, outputHeight: height)
    }

    private static func composeVertically(
        _ images: [CGImage],
        outputWidth: Int,
        outputHeight: Int
    ) -> CGImage? {
        guard let first = images.first else { return nil }
        let sourceWidth = first.width
        guard images.allSatisfy({ $0.width == sourceWidth }) else { return nil }
        let sourceHeight = images.reduce(0) { $0 + $1.height }
        guard sourceHeight > 0, outputWidth > 0, outputHeight > 0 else { return nil }
        guard let context = CGContext(
                  data: nil,
                  width: outputWidth,
                  height: outputHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: first.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        var consumedHeight = 0
        for image in images {
            let scaledStart = Int(
                (Double(consumedHeight) * Double(outputHeight) / Double(sourceHeight)).rounded()
            )
            let scaledEnd = Int(
                (Double(consumedHeight + image.height) * Double(outputHeight) / Double(sourceHeight)).rounded()
            )
            let scaledHeight = scaledEnd - scaledStart
            let y = outputHeight - scaledEnd
            if scaledHeight > 0 {
                context.draw(
                    image,
                    in: CGRect(x: 0, y: y, width: outputWidth, height: scaledHeight)
                )
            }
            consumedHeight += image.height
        }
        return context.makeImage()
    }
}
