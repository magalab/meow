import AppKit
import CoreGraphics
import MeowCapture
import Testing

struct ScrollingCaptureStitcherTests {
    @Test("Scrolling capture stitcher appends only new rows")
    func appendsOnlyNewRows() throws {
        let source = try makeScrollingSourceImage(width: 160, height: 300)
        let first = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 120)))
        let next = try #require(source.cropping(to: CGRect(x: 0, y: 40, width: 160, height: 120)))
        let stitcher = ScrollingCaptureStitcher(
            firstFrame: first,
            maximumHeight: 1_000,
            maximumPixels: 1_000_000,
            batchSize: 2
        )

        #expect(stitcher.appendBottomRows(from: next, count: 40) == .appended)
        let output = try #require(stitcher.makeImage())
        #expect(output.width == 160)
        #expect(output.height == 160)
    }

    @Test("Scrolling capture stitcher preserves exact vertical content order")
    func preservesExactVerticalContentOrder() throws {
        let source = try makeScrollingSourceImage(width: 160, height: 300)
        let first = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 120)))
        let next = try #require(source.cropping(to: CGRect(x: 0, y: 40, width: 160, height: 120)))
        let expected = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 160)))
        let stitcher = ScrollingCaptureStitcher(
            firstFrame: first,
            maximumHeight: 1_000,
            maximumPixels: 1_000_000
        )

        #expect(stitcher.appendBottomRows(from: next, count: 40) == .appended)
        let output = try #require(stitcher.makeImage())
        #expect(normalizedImageBytes(output) == normalizedImageBytes(expected))
    }

    @Test("Scrolling capture stitcher enforces height and pixel limits")
    func enforcesHeightAndPixelLimits() throws {
        let frame = try makeScrollingSourceImage(width: 100, height: 100)
        let heightLimited = ScrollingCaptureStitcher(
            firstFrame: frame,
            maximumHeight: 120,
            maximumPixels: 1_000_000
        )
        #expect(heightLimited.appendBottomRows(from: frame, count: 30) == .maximumHeight)

        let pixelLimited = ScrollingCaptureStitcher(
            firstFrame: frame,
            maximumHeight: 1_000,
            maximumPixels: 12_000
        )
        #expect(pixelLimited.appendBottomRows(from: frame, count: 30) == .maximumPixels)
    }

    @Test("Scrolling capture can compose a complete reduced-resolution fallback")
    func composesReducedResolutionFallback() throws {
        let source = try makeScrollingSourceImage(width: 100, height: 240)
        let first = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 100, height: 120)))
        let second = try #require(source.cropping(to: CGRect(x: 0, y: 120, width: 100, height: 120)))
        let stitcher = ScrollingCaptureStitcher(
            firstFrame: first,
            maximumHeight: 1_000,
            maximumPixels: 1_000_000
        )
        #expect(stitcher.appendBottomRows(from: second, count: 120) == .appended)

        let reduced = try #require(stitcher.makeReducedImage(maximumPixels: 6_000))
        #expect(reduced.width * reduced.height <= 6_100)
        #expect(abs(Double(reduced.width) / Double(reduced.height) - 100.0 / 240.0) < 0.02)
    }

    @Test("Scrolling capture composes a thirty-thousand-pixel image")
    func composesThirtyThousandPixelImage() throws {
        let frame = try makeScrollingSourceImage(width: 64, height: 1_000)
        let stitcher = ScrollingCaptureStitcher(
            firstFrame: frame,
            maximumHeight: 30_000,
            maximumPixels: 2_000_000
        )
        for _ in 0..<29 {
            #expect(stitcher.appendBottomRows(from: frame, count: 1_000) == .appended)
        }

        let output = try #require(stitcher.makeImage())
        #expect(output.width == 64)
        #expect(output.height == 30_000)
    }
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
