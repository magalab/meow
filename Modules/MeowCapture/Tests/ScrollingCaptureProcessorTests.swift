import AppKit
import CoreGraphics
import MeowCapture
import Testing

struct ScrollingCaptureProcessorTests {
    @Test("Scrolling capture processor preserves every row at a matched seam")
    func preservesRowsAtMatchedSeam() async throws {
        let source = try makeScrollingSourceImage(width: 220, height: 360)
        let viewportHeight = 180
        let offset = 48
        let previous = try #require(source.cropping(to: CGRect(
            x: 0,
            y: 0,
            width: source.width,
            height: viewportHeight
        )))
        let current = try #require(source.cropping(to: CGRect(
            x: 0,
            y: offset,
            width: source.width,
            height: viewportHeight
        )))
        let expected = try #require(source.cropping(to: CGRect(
            x: 0,
            y: 0,
            width: source.width,
            height: viewportHeight + offset
        )))
        let processor = ScrollingCaptureProcessor(
            firstFrame: previous,
            configuration: makeDefaultProcessorConfiguration()
        )

        let outcome = await processor.process(current, isAutoScrolling: false)
        guard case .appended = outcome else {
            Issue.record("Expected the known-offset frame to be appended")
            return
        }
        let finalImage = try #require(await processor.makeFinalImage())
        #expect(!finalImage.isReduced)
        #expect(finalImage.image.height == viewportHeight + offset)
        #expect(normalizedImageBytes(finalImage.image) == normalizedImageBytes(expected))
    }

    @Test("Automatic scrolling completes after repeated stable frames")
    func completesAfterRepeatedStableFrames() async throws {
        let frame = try makeScrollingSourceImage(width: 160, height: 120)
        let processor = ScrollingCaptureProcessor(
            firstFrame: frame,
            configuration: makeDefaultProcessorConfiguration()
        )

        _ = await processor.process(frame, isAutoScrolling: true)
        _ = await processor.process(frame, isAutoScrolling: true)
        let result = await processor.process(frame, isAutoScrolling: true)
        guard case let .reachedLimit(reason, _) = result else {
            Issue.record("Expected stable automatic capture to finish")
            return
        }
        #expect(reason == .completed)
    }

    @Test("Scrolling capture proactively reduces an oversized final image")
    func reducesOversizedFinalImage() async throws {
        let frame = try makeScrollingSourceImage(width: 100, height: 100)
        let processor = ScrollingCaptureProcessor(
            firstFrame: frame,
            configuration: makeDefaultProcessorConfiguration()
        )

        let finalImage = try #require(await processor.makeFinalImage(maximumPixels: 5_000))
        #expect(finalImage.isReduced)
        #expect(finalImage.image.width * finalImage.image.height <= 5_100)
    }
}

private func makeDefaultProcessorConfiguration() -> ScrollingCaptureProcessorConfiguration {
    ScrollingCaptureProcessorConfiguration(
        maximumHeightPixels: 30_000,
        maximumTotalPixels: 80_000_000,
        automaticallyDetectFrozenHeader: true
    )
}

private func makeScrollingSourceImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for y in stride(from: 0, to: height, by: 12) {
        let hue = CGFloat((y / 12) % 11) / 11
        context.setFillColor(NSColor(calibratedHue: hue, saturation: 0.75, brightness: 0.8, alpha: 1).cgColor)
        context.fill(CGRect(
            x: (y * 7) % max(1, width / 3),
            y: y,
            width: max(20, width * 2 / 3),
            height: 5 + (y / 12) % 5
        ))
    }
    return try #require(context.makeImage())
}

private func normalizedImageBytes(_ image: CGImage) -> Data {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { storage in
        let context = CGContext(
            data: storage.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return Data(bytes)
}
