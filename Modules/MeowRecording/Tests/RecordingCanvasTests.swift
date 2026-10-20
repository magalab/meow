import AppKit
@preconcurrency import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import Testing
import MeowRecording

@Test("Recording canvas keeps the source inside the selected aspect ratio")
func recordingCanvasLayout() {
    var settings = RecordingCanvasSettings()
    settings.aspect = .square
    settings.margin = 0.1
    settings.cornerRadius = 0.05
    let layout = RecordingCanvasLayout(
        sourceSize: CGSize(width: 1920, height: 1080),
        settings: settings
    )
    #expect(layout.renderSize == CGSize(width: 1920, height: 1920))
    #expect(layout.contentRect == CGRect(x: 192, y: 528, width: 1536, height: 864))
    #expect(abs(layout.cornerRadius - 43.2) < 0.001)

    settings.aspect = .portrait
    settings.margin = 0
    let portrait = RecordingCanvasLayout(
        sourceSize: CGSize(width: 1920, height: 1080),
        settings: settings
    )
    #expect(portrait.renderSize.width == 1920)
    #expect(portrait.renderSize.height == 3414)
    #expect(portrait.contentRect.width == 1920)
    #expect(portrait.contentRect.height == 1080)
}

@Test("Recording canvas backgrounds render distinct styles")
func recordingCanvasBackgroundStyles() throws {
    let rect = CGRect(x: 0, y: 0, width: 128, height: 128)
    let context = CIContext(options: [.useSoftwareRenderer: true])
    var settings = RecordingCanvasSettings()
    settings.red = 0.2
    settings.green = 0.25
    settings.blue = 0.3
    for style in RecordingCanvasBackgroundStyle.allCases {
        settings.backgroundStyle = style
        let image = RecordingCanvasComposition.backgroundImage(in: rect, settings: settings)
        let cgImage = try #require(context.createCGImage(image, from: rect))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let samples = stride(from: 0, to: 128, by: 4).flatMap { y in
            stride(from: 0, to: 128, by: 4).compactMap { x in
                bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.redComponent
            }
        }
        let spread = (samples.max() ?? 0) - (samples.min() ?? 0)
        if style == .solid {
            #expect(spread < 0.01)
        } else {
            #expect(spread > 0.015, "\(style) should be visible in the rendered canvas")
        }
    }
}

@Test("Recording canvas theme accent changes decorative backgrounds")
func recordingCanvasBackgroundAccent() throws {
    let rect = CGRect(x: 0, y: 0, width: 128, height: 128)
    let context = CIContext(options: [.useSoftwareRenderer: true])
    var settings = RecordingCanvasSettings()
    settings.accentColor = RecordingCanvasRGB(red: 0.9, green: 0.2, blue: 0.1)
    for style in [
        RecordingCanvasBackgroundStyle.gradient, .stripes, .dots, .glow
    ] {
        settings.backgroundStyle = style
        let accented = try #require(context.createCGImage(
            RecordingCanvasComposition.backgroundImage(in: rect, settings: settings), from: rect
        ))
        settings.accentColor = nil
        let plain = try #require(context.createCGImage(
            RecordingCanvasComposition.backgroundImage(in: rect, settings: settings), from: rect
        ))
        settings.accentColor = RecordingCanvasRGB(red: 0.9, green: 0.2, blue: 0.1)
        let accentedBitmap = NSBitmapImageRep(cgImage: accented)
        let plainBitmap = NSBitmapImageRep(cgImage: plain)
        let largestDifference = stride(from: 0, to: 128, by: 4).flatMap { y in
            stride(from: 0, to: 128, by: 4).compactMap { x -> CGFloat? in
                guard let a = accentedBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let b = plainBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return nil }
                return abs(a.redComponent - b.redComponent)
            }
        }.max() ?? 0
        #expect(largestDifference > 0.015, "\(style) should use the theme accent")
    }
}

@Test("Recording canvas exports the selected video with its background", arguments: [
    RecordingCanvasAspect.original, .square, .portrait
], RecordingCanvasBackgroundStyle.allCases)
func recordingCanvasExport(aspect: RecordingCanvasAspect, style: RecordingCanvasBackgroundStyle) async throws {
    guard let samplePath = ProcessInfo.processInfo.environment["MEOW_RECORDING_CANVAS_SAMPLE"] else {
        return
    }
    let sourceURL = URL(fileURLWithPath: samplePath)
    let asset = AVURLAsset(url: sourceURL)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let size = try await track.load(.naturalSize)
    var settings = RecordingCanvasSettings()
    settings.aspect = aspect
    settings.backgroundStyle = style
    settings.margin = 0.1
    settings.red = 0
    settings.green = 1
    settings.blue = 0
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("meow-canvas-\(UUID().uuidString).mov")
    defer { try? FileManager.default.removeItem(at: outputURL) }
    let session = try #require(AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality))
    session.videoComposition = try await RecordingCanvasComposition.make(
        asset: asset, sourceSize: size, settings: settings
    )
    session.timeRange = CMTimeRange(
        start: .zero,
        duration: CMTime(seconds: 1, preferredTimescale: 600)
    )
    try await session.export(to: outputURL, as: .mov)

    let result = AVURLAsset(url: outputURL)
    let video = try #require(try await result.loadTracks(withMediaType: .video).first)
    #expect(!(try await result.loadTracks(withMediaType: .audio)).isEmpty)
    let outputSize = try await video.load(.naturalSize)
    #expect(abs(outputSize.width / outputSize.height - (aspect.ratio ?? size.width / size.height)) < 0.01)
    let generator = AVAssetImageGenerator(asset: result)
    let image = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
    let bitmap = NSBitmapImageRep(cgImage: image)
    let corner = try #require(bitmap.colorAt(x: 4, y: 4)?.usingColorSpace(.deviceRGB))
    let edgePoints = [
        (bitmap.pixelsWide / 2, 4),
        (bitmap.pixelsWide / 2, bitmap.pixelsHigh - 5),
        (4, bitmap.pixelsHigh / 2),
        (bitmap.pixelsWide - 5, bitmap.pixelsHigh / 2)
    ]
    for (x, y) in edgePoints {
        let edge = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        #expect(edge.greenComponent > 0.6)
        #expect(edge.redComponent < 0.3)
    }
    let layout = RecordingCanvasLayout(sourceSize: size, settings: settings)
    let roundedCorner = try #require(bitmap.colorAt(
        x: Int(layout.contentRect.minX) + 1,
        y: Int(layout.contentRect.minY) + 1
    )?.usingColorSpace(.deviceRGB))
    let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
        .usingColorSpace(.deviceRGB))
    #expect(corner.greenComponent > 0.6)
    #expect(corner.redComponent < 0.3)
    #expect(roundedCorner.greenComponent > 0.6)
    #expect(center.greenComponent < 0.6 || center.redComponent > 0.3)
}
