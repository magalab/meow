import AppKit
import CoreGraphics
import MeowCapture
import Testing

struct CaptureEditorRendererTests {
    @Test("Capture editor crop and resize produce requested dimensions")
    func cropAndResizeProduceRequestedDimensions() throws {
        let source = try makeWhiteImage(width: 100, height: 80)
        let output = try CaptureEditorRenderer.render(
            source: source,
            commands: [],
            cropRect: CGRect(x: 10, y: 10, width: 50, height: 40),
            outputSize: CGSize(width: 200, height: 160)
        )

        #expect(output.width == 200)
        #expect(output.height == 160)
    }

    @Test("Capture editor annotations are flattened into exported pixels")
    func flattensAnnotations() throws {
        let source = try makeWhiteImage(width: 80, height: 60)
        let output = try CaptureEditorRenderer.render(
            source: source,
            commands: [
                .rectangle(
                    rect: CGRect(x: 10, y: 10, width: 40, height: 30),
                    color: .red,
                    width: 6
                ),
            ],
            cropRect: nil
        )

        #expect(imageBytes(output) != imageBytes(source))
    }

    @Test("Capture editor mosaic destructively changes exported pixels")
    func mosaicChangesExportedPixels() throws {
        let source = try makeCheckerboardImage(width: 64, height: 64)
        let output = try CaptureEditorRenderer.render(
            source: source,
            commands: [.mosaic(rect: CGRect(x: 0, y: 0, width: 64, height: 64))],
            cropRect: nil
        )

        #expect(imageBytes(output) != imageBytes(source))
    }
}

private func makeWhiteImage(width: Int, height: Int) throws -> CGImage {
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

private func makeCheckerboardImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    for y in 0..<height {
        for x in 0..<width {
            let isWhite = ((x / 4) + (y / 4)).isMultiple(of: 2)
            context.setFillColor((isWhite ? NSColor.white : NSColor.black).cgColor)
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    return try #require(context.makeImage())
}

private func imageBytes(_ image: CGImage) -> Data {
    guard let data = image.dataProvider?.data else { return Data() }
    return data as Data
}
