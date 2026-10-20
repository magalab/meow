import AppKit
import CoreGraphics
@testable import MeowCapture
import Testing

struct ScrollingCaptureMatcherTests {
    @Test("Scrolling capture recognizes identical settled frames")
    func recognizesIdenticalSettledFrames() throws {
        let image = try makeScrollingSourceImage(width: 180, height: 220)
        #expect(ScrollingCaptureMatcher.framesAreStable(image, image))
    }

    @Test("Scrolling capture rejects featureless content")
    func rejectsFeaturelessContent() throws {
        let first = try makeSolidImage(width: 180, height: 220)
        let second = try makeSolidImage(width: 180, height: 220)
        #expect(ScrollingCaptureMatcher.match(previous: first, current: second) == nil)
    }

    @Test("Scrolling capture matches a known downward content offset")
    func matchesKnownDownwardOffset() throws {
        let source = try makeScrollingSourceImage(width: 220, height: 360)
        let viewportHeight = 180
        let expectedOffset = 48
        let previous = try #require(source.cropping(to: CGRect(
            x: 0,
            y: 0,
            width: source.width,
            height: viewportHeight
        )))
        let current = try #require(source.cropping(to: CGRect(
            x: 0,
            y: expectedOffset,
            width: source.width,
            height: viewportHeight
        )))

        let match = try #require(ScrollingCaptureMatcher.match(previous: previous, current: current))
        #expect(abs(match.verticalOffset - expectedOffset) <= 2)
        #expect(match.confidence > 0.5)
    }

    @Test("Pixel fallback matches a known downward content offset")
    func pixelFallbackMatchesKnownDownwardOffset() throws {
        let source = try makeScrollingSourceImage(width: 220, height: 360)
        let previous = try #require(source.cropping(to: CGRect(
            x: 0,
            y: 0,
            width: source.width,
            height: 180
        )))
        let current = try #require(source.cropping(to: CGRect(
            x: 0,
            y: 48,
            width: source.width,
            height: 180
        )))

        let match = try #require(ScrollingCaptureMatcher.matchUsingPixelFallback(
            previous: previous,
            current: current
        ))
        #expect(abs(match.verticalOffset - 48) <= 2)
        #expect(match.confidence > 0.5)
    }

    @Test("Scrolling capture detects a fixed top header")
    func detectsFixedTopHeader() throws {
        let source = try makeScrollingSourceImage(width: 220, height: 360)
        let previous = try makeScrollingViewport(
            source: source,
            offset: 0,
            height: 180,
            frozenHeaderHeight: 24
        )
        let current = try makeScrollingViewport(
            source: source,
            offset: 48,
            height: 180,
            frozenHeaderHeight: 24
        )

        let detected = ScrollingCaptureMatcher.frozenHeaderHeight(
            previous: previous,
            current: current
        )
        #expect((20 ... 28).contains(detected))
        let match = try #require(ScrollingCaptureMatcher.match(
            previous: previous,
            current: current,
            frozenHeaderHeight: detected
        ))
        #expect(abs(match.verticalOffset - 48) <= 2)
    }
}

private func makeSolidImage(width: Int, height: Int) throws -> CGImage {
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
    return try #require(context.makeImage())
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

private func makeScrollingViewport(
    source: CGImage,
    offset: Int,
    height: Int,
    frozenHeaderHeight: Int
) throws -> CGImage {
    let content = try #require(source.cropping(to: CGRect(
        x: 0,
        y: offset,
        width: source.width,
        height: height
    )))
    let context = try #require(CGContext(
        data: nil,
        width: source.width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))

    context.draw(content, in: CGRect(x: 0, y: 0, width: source.width, height: height))
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(
        x: 0,
        y: height - frozenHeaderHeight,
        width: source.width,
        height: frozenHeaderHeight
    ))
    for x in stride(from: 0, to: source.width, by: 17) {
        context.setFillColor(NSColor.systemYellow.cgColor)
        context.fill(CGRect(
            x: x,
            y: height - frozenHeaderHeight + 5,
            width: 8,
            height: 9
        ))
    }
    return try #require(context.makeImage())
}
