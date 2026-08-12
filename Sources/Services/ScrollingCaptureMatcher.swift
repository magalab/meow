@preconcurrency import CoreGraphics
import Foundation
@preconcurrency import Vision

struct ScrollingCaptureMatch: Equatable, Sendable {
    let verticalOffset: Int
    let confidence: Double
    let rightMargin: Int
}

enum ScrollingCaptureMatcher {
    private struct PixelBuffer {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init?(_ image: CGImage) {
            let width = image.width
            let height = image.height
            guard width > 0, height > 0 else { return nil }

            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let rendered = bytes.withUnsafeMutableBytes { storage -> Bool in
                guard let baseAddress = storage.baseAddress,
                      let context = CGContext(
                          data: baseAddress,
                          width: width,
                          height: height,
                          bitsPerComponent: 8,
                          bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      )
                else { return false }
                context.interpolationQuality = .none
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard rendered else { return nil }
            self.width = width
            self.height = height
            self.bytes = bytes
        }

        func difference(at firstIndex: Int, versus other: PixelBuffer, at secondIndex: Int) -> Int {
            abs(Int(bytes[firstIndex]) - Int(other.bytes[secondIndex]))
                + abs(Int(bytes[firstIndex + 1]) - Int(other.bytes[secondIndex + 1]))
                + abs(Int(bytes[firstIndex + 2]) - Int(other.bytes[secondIndex + 2]))
        }

        func luminance(x: Int, y: Int) -> Int {
            let index = (y * width + x) * 4
            return (Int(bytes[index]) * 54
                + Int(bytes[index + 1]) * 183
                + Int(bytes[index + 2]) * 19) >> 8
        }
    }

    static func match(
        previous: CGImage,
        current: CGImage,
        frozenHeaderHeight: Int = 0
    ) -> ScrollingCaptureMatch? {
        guard previous.width == current.width,
              previous.height == current.height,
              previous.width >= 40,
              previous.height >= 40,
              let previousPixels = PixelBuffer(previous),
              let currentPixels = PixelBuffer(current)
        else { return nil }

        let rightMargin = detectRightMargin(previousPixels, currentPixels)
        let cropTop = min(max(0, frozenHeaderHeight), previous.height / 3)
        let cropWidth = previous.width - rightMargin
        let cropHeight = previous.height - cropTop
        guard cropWidth >= 32, cropHeight >= 32,
              hasEnoughVisualDetail(previousPixels, cropTop: cropTop, cropWidth: cropWidth)
        else { return nil }

        let previousForVision: CGImage
        let currentForVision: CGImage
        if cropTop > 0 || rightMargin > 0 {
            let cropRect = CGRect(x: 0, y: cropTop, width: cropWidth, height: cropHeight)
            guard let previousCrop = previous.cropping(to: cropRect),
                  let currentCrop = current.cropping(to: cropRect)
            else { return nil }
            previousForVision = previousCrop
            currentForVision = currentCrop
        } else {
            previousForVision = previous
            currentForVision = current
        }

        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: previousForVision)
        let handler = VNImageRequestHandler(cgImage: currentForVision)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first as? VNImageTranslationAlignmentObservation
        else { return nil }

        let coarseOffset = Int(abs(observation.alignmentTransform.ty).rounded())
        let maximumOffset = max(1, Int(Double(previous.height) * 0.82))
        guard coarseOffset <= maximumOffset else { return nil }

        let searchCenter = max(1, coarseOffset)
        let lowerBound = max(1, searchCenter - 10)
        let upperBound = min(maximumOffset, searchCenter + 10)
        guard lowerBound <= upperBound else { return nil }

        var bestOffset = 0
        var bestError = Double.greatestFiniteMagnitude
        for candidate in lowerBound...upperBound {
            let error = alignmentError(
                previousPixels,
                currentPixels,
                offset: candidate,
                cropTop: cropTop,
                rightMargin: rightMargin
            )
            if error < bestError {
                bestError = error
                bestOffset = candidate
            }
        }

        guard bestOffset > 0, bestError.isFinite, bestError <= 0.22 else { return nil }
        return ScrollingCaptureMatch(
            verticalOffset: bestOffset,
            confidence: max(0, min(1, 1 - bestError / 0.22)),
            rightMargin: rightMargin
        )
    }

    static func framesAreStable(_ first: CGImage, _ second: CGImage) -> Bool {
        guard first.width == second.width,
              first.height == second.height,
              let firstPixels = PixelBuffer(first),
              let secondPixels = PixelBuffer(second)
        else { return false }

        let xStep = max(1, first.width / 96)
        let yStep = max(1, first.height / 64)
        var totalDifference: UInt64 = 0
        var samples = 0
        for y in stride(from: 2, to: max(3, first.height - 2), by: yStep) {
            for x in stride(from: 2, to: max(3, first.width - 2), by: xStep) {
                let index = (y * first.width + x) * 4
                totalDifference += UInt64(firstPixels.difference(
                    at: index,
                    versus: secondPixels,
                    at: index
                ))
                samples += 1
            }
        }
        guard samples > 0 else { return false }
        let normalized = Double(totalDifference) / Double(samples * 3 * 255)
        return normalized < 0.0025
    }

    static func frozenHeaderHeight(previous: CGImage, current: CGImage) -> Int {
        guard previous.width == current.width,
              previous.height == current.height,
              let previousPixels = PixelBuffer(previous),
              let currentPixels = PixelBuffer(current)
        else { return 0 }

        let maximumHeight = previous.height * 2 / 5
        let xStep = max(2, previous.width / 160)
        var stableRows = 0
        for y in 0..<maximumHeight {
            var rowDifference = 0
            var samples = 0
            for x in stride(from: 4, to: max(5, previous.width - 20), by: xStep) {
                let index = (y * previous.width + x) * 4
                rowDifference += previousPixels.difference(
                    at: index,
                    versus: currentPixels,
                    at: index
                )
                samples += 1
            }
            let normalized = samples > 0
                ? Double(rowDifference) / Double(samples * 3 * 255)
                : 1
            if normalized > 0.025 {
                break
            }
            stableRows += 1
        }
        return stableRows >= 10 ? stableRows : 0
    }

    private static func detectRightMargin(_ previous: PixelBuffer, _ current: PixelBuffer) -> Int {
        let maximumWidth = min(24, previous.width / 10)
        guard maximumWidth >= 3 else { return 0 }
        let yStart = previous.height / 5
        let yEnd = previous.height * 4 / 5
        let yStep = max(2, (yEnd - yStart) / 48)
        var stableColumns = 0

        for distance in 0..<maximumWidth {
            let x = previous.width - 1 - distance
            var totalDifference = 0
            var samples = 0
            for y in stride(from: yStart, to: yEnd, by: yStep) {
                let index = (y * previous.width + x) * 4
                totalDifference += previous.difference(at: index, versus: current, at: index)
                samples += 1
            }
            let normalized = samples > 0
                ? Double(totalDifference) / Double(samples * 3 * 255)
                : 1
            if normalized < 0.035 {
                stableColumns += 1
            } else if stableColumns >= 3 {
                break
            } else {
                stableColumns = 0
            }
        }
        return stableColumns >= 3 ? min(maximumWidth, stableColumns + 4) : 0
    }

    private static func hasEnoughVisualDetail(
        _ pixels: PixelBuffer,
        cropTop: Int,
        cropWidth: Int
    ) -> Bool {
        let xStep = max(2, cropWidth / 64)
        let yStep = max(2, (pixels.height - cropTop) / 48)
        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0.0
        for y in stride(from: cropTop, to: pixels.height, by: yStep) {
            for x in stride(from: 0, to: cropWidth, by: xStep) {
                let value = Double(pixels.luminance(x: x, y: y))
                sum += value
                sumOfSquares += value * value
                count += 1
            }
        }
        guard count > 0 else { return false }
        let variance = sumOfSquares / count - pow(sum / count, 2)
        return variance > 16
    }

    private static func alignmentError(
        _ previous: PixelBuffer,
        _ current: PixelBuffer,
        offset: Int,
        cropTop: Int,
        rightMargin: Int
    ) -> Double {
        let overlapHeight = previous.height - offset - cropTop
        let usableWidth = previous.width - rightMargin
        guard overlapHeight > previous.height / 6, usableWidth > 20 else {
            return .greatestFiniteMagnitude
        }

        let xStep = max(2, usableWidth / 180)
        let yStep = max(2, overlapHeight / 120)
        var totalDifference: UInt64 = 0
        var samples = 0
        for currentY in stride(from: cropTop, to: cropTop + overlapHeight, by: yStep) {
            let previousY = currentY + offset
            for x in stride(from: 2, to: max(3, usableWidth - 2), by: xStep) {
                let previousIndex = (previousY * previous.width + x) * 4
                let currentIndex = (currentY * current.width + x) * 4
                totalDifference += UInt64(previous.difference(
                    at: previousIndex,
                    versus: current,
                    at: currentIndex
                ))
                samples += 1
            }
        }
        guard samples > 0 else { return .greatestFiniteMagnitude }
        return Double(totalDifference) / Double(samples * 3 * 255)
    }
}
