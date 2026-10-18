import Foundation
import AppKit
@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import CoreImage
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@Test("Recording settings decode missing fields with current defaults")
func recordingSettingsCompatibility() throws {
    let settings = try JSONDecoder().decode(
        RecordingSettings.self,
        from: Data(#"{"enabled":true,"frameRate":30}"#.utf8)
    )
    #expect(settings.enabled)
    #expect(settings.frameRate == 30)
    #expect(settings.videoFormat == .mp4)
    #expect(settings.videoCodec == .h264)
    #expect(settings.audioMode == .system)
    #expect(settings.showFloatingControls)
    #expect(settings.cameraOverlayShape == .rounded)
    #expect(settings.magnifierZoom == 2)
    #expect(settings.magnifierWindowWidth == 420)
    #expect(!settings.magnifierCircular)
}

@MainActor
@Test("Canceling a recording countdown releases its state for the next recording")
func recordingCountdownCancellationAllowsRestart() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("meow-recording-lifecycle-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let service = RecordingService(store: RecordingStore(storageDirectory: directory))
    service.apply(settings: .default)
    let startTask = Task { @MainActor in
        await service.start(source: .mobileDevice("lifecycle-test-device"))
    }

    try await Task.sleep(for: .milliseconds(50))
    guard case .countdown(3) = service.state else {
        Issue.record("Recording should be waiting in its countdown before cancellation")
        return
    }

    startTask.cancel()
    await startTask.value
    guard case .failed = service.state else {
        Issue.record("Cancelled startup should settle in a failed, inactive state")
        return
    }

    try service.prepare(source: .mobileDevice("lifecycle-test-device"))
    #expect(service.state == .preparing)
    await service.stop()
    #expect(service.state == .idle)
}

@Test("Trim export refuses the source file and aliases")
@MainActor
func recordingTrimPreservesSource() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("meow-trim-source-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("recording.mov")
    let symlink = directory.appendingPathComponent("alias.mov")
    let hardlink = directory.appendingPathComponent("hardlink.mov")
    let other = directory.appendingPathComponent("other.mov")
    try Data("source".utf8).write(to: source)
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
    try FileManager.default.linkItem(at: source, to: hardlink)
    try Data("other".utf8).write(to: other)

    #expect(RecordingTrimmerView.wouldOverwriteSource(sourceURL: source, outputURL: source))
    #expect(RecordingTrimmerView.wouldOverwriteSource(sourceURL: source, outputURL: symlink))
    #expect(RecordingTrimmerView.wouldOverwriteSource(sourceURL: source, outputURL: hardlink))
    #expect(!RecordingTrimmerView.wouldOverwriteSource(sourceURL: source, outputURL: other))
}

@Test("Recording region border positions on the selected display")
@MainActor
func recordingRegionBorderUsesDisplayOrigin() {
    let frame = RecordingRegionBorderController.globalFrame(
        for: CGRect(x: 24, y: 30, width: 300, height: 160),
        screenFrame: CGRect(x: -1440, y: 120, width: 1440, height: 900)
    )
    #expect(frame == CGRect(x: -1416, y: 150, width: 300, height: 160))
}

@Test("Recording magnifier placement remains continuous at screen edges")
@MainActor
func recordingMagnifierPlacement() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let size = CGSize(width: 300, height: 200)
    let middle = ScreenMagnifierController.panelFrame(
        near: CGPoint(x: 500, y: 350), visibleFrame: screen, preferredSize: size
    )
    #expect(middle.origin == CGPoint(x: 512, y: 138))
    let right = ScreenMagnifierController.panelFrame(
        near: CGPoint(x: 900, y: 350), visibleFrame: screen, preferredSize: size
    )
    #expect(right.origin == CGPoint(x: 692, y: 138))
    let bottom = ScreenMagnifierController.panelFrame(
        near: CGPoint(x: 500, y: 30), visibleFrame: screen, preferredSize: size
    )
    #expect(bottom.origin == CGPoint(x: 512, y: 8))
    let beforeEdge = ScreenMagnifierController.panelFrame(
        near: CGPoint(x: 679, y: 350), visibleFrame: screen, preferredSize: size
    )
    let afterEdge = ScreenMagnifierController.panelFrame(
        near: CGPoint(x: 681, y: 350), visibleFrame: screen, preferredSize: size
    )
    #expect(abs(beforeEdge.minX - afterEdge.minX) <= 2)
}

@Test("Recording magnifier crops the persistent stream around the pointer")
@MainActor
func recordingMagnifierStreamCrop() {
    let screen = CGRect(x: -1440, y: 100, width: 1440, height: 900)
    let image = CGSize(width: 2880, height: 1800)
    let capture = CGSize(width: 150, height: 100)
    let middle = ScreenMagnifierController.streamCropRect(
        centeredAt: CGPoint(x: -720, y: 550),
        in: screen, imageSize: image, captureSize: capture
    )
    #expect(middle == CGRect(x: 1290, y: 800, width: 300, height: 200))
    let edge = ScreenMagnifierController.streamCropRect(
        centeredAt: CGPoint(x: -1435, y: 995),
        in: screen, imageSize: image, captureSize: capture
    )
    #expect(edge == CGRect(x: 0, y: 1600, width: 300, height: 200))
    let smallDisplay = ScreenMagnifierController.streamCropRect(
        centeredAt: CGPoint(x: -290, y: 30),
        in: CGRect(x: -300, y: 20, width: 100, height: 70),
        imageSize: CGSize(width: 200, height: 140),
        captureSize: CGSize(width: 210, height: 140)
    )
    #expect(smallDisplay == CGRect(x: 0, y: 0, width: 200, height: 140))
}

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

@Test(
    "Recorded click ring is composited into a video sample",
    arguments: [
        kCVPixelFormatType_32BGRA,
        kCVPixelFormatType_ARGB2101010LEPacked,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ]
)
func recordedMouseClickRingIsInVideoSample(pixelFormat: OSType) throws {
    let captureRect = CGRect(x: 100, y: 200, width: 128, height: 128)
    #expect(RecordingMouseClickCompositor.pixelCenter(
        for: CGPoint(x: 164, y: 264),
        captureRect: captureRect,
        imageSize: CGSize(width: 128, height: 128)
    ) == CGPoint(x: 64, y: 64))

    var pixelBuffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(
        kCFAllocatorDefault,
        128,
        128,
        pixelFormat,
        nil,
        &pixelBuffer
    ) == kCVReturnSuccess)
    let sourceBuffer = try #require(pixelBuffer)
    CVPixelBufferLockBaseAddress(sourceBuffer, [])
    if CVPixelBufferGetPlaneCount(sourceBuffer) == 0 {
        memset(CVPixelBufferGetBaseAddress(sourceBuffer), 0, CVPixelBufferGetDataSize(sourceBuffer))
    } else {
        for plane in 0..<CVPixelBufferGetPlaneCount(sourceBuffer) {
            memset(
                CVPixelBufferGetBaseAddressOfPlane(sourceBuffer, plane),
                plane == 0 ? 0 : 128,
                CVPixelBufferGetBytesPerRowOfPlane(sourceBuffer, plane)
                    * CVPixelBufferGetHeightOfPlane(sourceBuffer, plane)
            )
        }
    }
    CVPixelBufferUnlockBaseAddress(sourceBuffer, [])

    var format: CMVideoFormatDescription?
    #expect(CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: sourceBuffer,
        formatDescriptionOut: &format
    ) == noErr)
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: CMTime(value: 1, timescale: 1),
        decodeTimeStamp: .invalid
    )
    var sample: CMSampleBuffer?
    #expect(CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: sourceBuffer,
        formatDescription: try #require(format),
        sampleTiming: &timing,
        sampleBufferOut: &sample
    ) == noErr)

    let compositor = RecordingMouseClickCompositor(
        captureRect: captureRect,
        enabled: true,
        theme: .gingerCat
    )
    compositor.recordClick(at: CGPoint(x: 164, y: 264))
    let output = compositor.composite(try #require(sample))
    let result = try #require(output.imageBuffer)
    #expect(result !== sourceBuffer)
    CVPixelBufferLockBaseAddress(result, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(result, .readOnly) }
    if CVPixelBufferGetPlaneCount(result) > 0 {
        let base = try #require(CVPixelBufferGetBaseAddressOfPlane(result, 0))
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let count = CVPixelBufferGetBytesPerRowOfPlane(result, 0)
            * CVPixelBufferGetHeightOfPlane(result, 0)
        #expect((0..<count).contains { bytes[$0] != 0 })
    } else {
        let base = try #require(CVPixelBufferGetBaseAddress(result))
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        #expect((0..<CVPixelBufferGetDataSize(result)).contains { bytes[$0] != 0 })
    }
    if pixelFormat == kCVPixelFormatType_32BGRA {
        let base = try #require(CVPixelBufferGetBaseAddress(result))
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let ringRow = 64 * CVPixelBufferGetBytesPerRow(result)
        #expect((75...80).contains { x in
            let pixel = ringRow + x * 4
            return bytes[pixel] != 0 || bytes[pixel + 1] != 0 || bytes[pixel + 2] != 0
        })
    }
    compositor.apply(enabled: false, theme: .gingerCat)
    #expect(compositor.composite(try #require(sample)) === sample)
}

@Test(
    "Magnifier appears in encoded video samples and clears when closed",
    arguments: [
        kCVPixelFormatType_32BGRA,
        kCVPixelFormatType_ARGB2101010LEPacked,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ]
)
func recordedMagnifierIsInVideoSample(pixelFormat: OSType) throws {
    var buffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, pixelFormat, nil, &buffer) == kCVReturnSuccess)
    let source = try #require(buffer)
    CVPixelBufferLockBaseAddress(source, [])
    if CVPixelBufferGetPlaneCount(source) == 0 {
        memset(CVPixelBufferGetBaseAddress(source), 0, CVPixelBufferGetDataSize(source))
        if pixelFormat == kCVPixelFormatType_ARGB2101010LEPacked {
            let row = try #require(CVPixelBufferGetBaseAddress(source))
                .advanced(by: 32 * CVPixelBufferGetBytesPerRow(source))
                .assumingMemoryBound(to: UInt32.self)
            row[32] = 0xFFFFFFFF
        }
    } else {
        for plane in 0..<CVPixelBufferGetPlaneCount(source) {
            memset(CVPixelBufferGetBaseAddressOfPlane(source, plane), plane == 0 ? 0 : 128,
                   CVPixelBufferGetBytesPerRowOfPlane(source, plane) * CVPixelBufferGetHeightOfPlane(source, plane))
        }
    }
    CVPixelBufferUnlockBaseAddress(source, [])
    var format: CMVideoFormatDescription?
    #expect(CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: source, formatDescriptionOut: &format
    ) == noErr)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                    presentationTimeStamp: CMTime(value: 1, timescale: 1),
                                    decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    #expect(CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: source,
        formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample
    ) == noErr)
    let context = try #require(CGContext(
        data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    ))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    let compositor = RecordingMagnifierCompositor(captureRect: CGRect(x: 0, y: 0, width: 64, height: 64))
    compositor.setImage(context.makeImage(), frame: CGRect(x: 20, y: 20, width: 16, height: 16))
    let output = compositor.composite(try #require(sample))
    let result = try #require(output.imageBuffer)
    #expect(result !== source)
    CVPixelBufferLockBaseAddress(result, .readOnly)
    if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
        let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(result, 0)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(result, 0)
        #expect(bytes[32 * stride + 28] > 0)
        #expect(bytes[8 * stride + 8] == 0)
    } else {
        let bytes = try #require(CVPixelBufferGetBaseAddress(result)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(result)
        #expect((0..<4).contains { bytes[32 * stride + 28 * 4 + $0] != 0 })
        #expect((0..<4).allSatisfy { bytes[8 * stride + 8 * 4 + $0] == 0 })
        if pixelFormat == kCVPixelFormatType_ARGB2101010LEPacked {
            let row = try #require(CVPixelBufferGetBaseAddress(result))
                .advanced(by: 32 * stride)
                .assumingMemoryBound(to: UInt32.self)
            // An opaque overlay must replace the old all-ones pixel rather
            // than OR its new channels into the old channel bits.
            #expect(row[32] != 0xFFFFFFFF)
            #expect(row[32] & 0x3FF == 0)
            #expect((row[32] >> 10) & 0x3FF < 512)
        }
    }
    CVPixelBufferUnlockBaseAddress(result, .readOnly)
    compositor.setFrame(CGRect(x: 40, y: 20, width: 16, height: 16))
    let movedSample = compositor.composite(try #require(sample))
    let moved = try #require(movedSample.imageBuffer)
    CVPixelBufferLockBaseAddress(moved, .readOnly)
    if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
        let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(moved, 0)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(moved, 0)
        #expect(bytes[32 * stride + 28] == 0)
        #expect(bytes[32 * stride + 48] > 0)
    } else {
        let bytes = try #require(CVPixelBufferGetBaseAddress(moved)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(moved)
        #expect((0..<4).allSatisfy { bytes[32 * stride + 28 * 4 + $0] == 0 })
        #expect((0..<4).contains { bytes[32 * stride + 48 * 4 + $0] != 0 })
    }
    CVPixelBufferUnlockBaseAddress(moved, .readOnly)
    compositor.setImage(nil, frame: .zero)
    #expect(compositor.composite(try #require(sample)) === sample)
    compositor.setSnapshot(
        context.makeImage(), frame: CGRect(x: 8, y: 8, width: 48, height: 48),
        marker: CGPoint(x: 0.5, y: 0.5), zoom: 2, circular: false
    )
    #expect(compositor.composite(try #require(sample)).imageBuffer !== source)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
    compositor.setImage(context.makeImage(), frame: CGRect(x: 20, y: 20, width: 16, height: 16))
    let orientedSample = compositor.composite(try #require(sample))
    let oriented = try #require(orientedSample.imageBuffer)
    CVPixelBufferLockBaseAddress(oriented, .readOnly)
    if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
        let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(oriented, 0))
            .assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(oriented, 0)
        #expect(bytes[42 * stride + 28] > bytes[30 * stride + 28])
    } else {
        let bytes = try #require(CVPixelBufferGetBaseAddress(oriented))
            .assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(oriented)
        #expect(bytes[42 * stride + 28 * 4] > bytes[30 * stride + 28 * 4])
    }
    CVPixelBufferUnlockBaseAddress(oriented, .readOnly)
}

@Test("Recording settings normalize HDR, alpha, and mobile output constraints")
func recordingSettingsNormalization() {
    var alpha = RecordingSettings.default
    alpha.videoFormat = .mp4
    alpha.videoCodec = .hevcWithAlpha
    alpha.recordHDR = true
    let normalizedAlpha = alpha.normalized()
    #expect(normalizedAlpha.videoFormat == .mov)
    #expect(normalizedAlpha.videoCodec == .hevcWithAlpha)
    #expect(!normalizedAlpha.recordHDR)

    var transparent = RecordingSettings.default
    transparent.backgroundStyle = .transparent
    let normalizedTransparent = transparent.normalized()
    #expect(normalizedTransparent.videoFormat == .mov)
    #expect(normalizedTransparent.videoCodec == .hevcWithAlpha)

    var hdr = RecordingSettings.default
    hdr.videoCodec = .h264
    hdr.videoFormat = .mp4
    hdr.recordHDR = true
    let normalizedHDR = hdr.normalized()
    #expect(normalizedHDR.videoFormat == .mov)
    #expect(normalizedHDR.videoCodec == .hevc)

    let mobile = hdr.normalized(for: .mobileDevice)
    #expect(mobile.videoFormat == .mov)
    #expect(mobile.videoCodec == .h264)
    #expect(mobile.audioMode == .none)
    #expect(!mobile.recordHDR)

    var exclusions = RecordingSettings.default
    exclusions.excludedApplicationBundleIDs = [
        " COM.EXAMPLE.Secret ",
        "com.example.secret",
        "",
    ]
    #expect(exclusions.normalized().excludedApplicationBundleIDs == ["com.example.secret"])
}

@Test("Mobile recordings always use a QuickTime movie extension")
@MainActor
func mobileRecordingOutputExtension() throws {
    var settings = RecordingSettings.default
    settings.saveDirectory = FileManager.default.temporaryDirectory.path
    settings.fileNameTemplate = "Meow Mobile \(UUID().uuidString)"
    settings.videoFormat = .mp4
    let url = try RecordingStore.outputURL(settings: settings, source: .mobileDevice)
    #expect(url.pathExtension == "mov")
}

@Test("Combined system and microphone recording uses a QuickTime movie container")
func combinedAudioVideoContainerNormalization() {
    var settings = RecordingSettings.default
    settings.videoFormat = .mp4
    settings.audioMode = .systemAndMicrophone

    let normalized = settings.normalized()
    #expect(normalized.videoFormat == .mov)
}

@Test("HDR and transparent recordings force compatible codecs and containers")
func advancedRecordingContainerNormalization() {
    var hdr = RecordingSettings.default
    hdr.videoFormat = .mp4
    hdr.videoCodec = .h264
    hdr.recordHDR = true
    hdr.backgroundStyle = .desktop

    let normalizedHDR = hdr.normalized()
    #expect(normalizedHDR.videoFormat == .mov)
    #expect(normalizedHDR.videoCodec == .hevc)
    #expect(normalizedHDR.recordHDR)

    var transparent = RecordingSettings.default
    transparent.videoFormat = .mp4
    transparent.videoCodec = .h264
    transparent.recordHDR = true
    transparent.backgroundStyle = .transparent

    let normalizedTransparent = transparent.normalized()
    #expect(normalizedTransparent.videoFormat == .mov)
    #expect(normalizedTransparent.videoCodec == .hevcWithAlpha)
    #expect(!normalizedTransparent.recordHDR)
}

@Test("System audio recordings use the selected audio-only extension")
@MainActor
func systemAudioRecordingOutputExtension() throws {
    var settings = RecordingSettings.default
    settings.saveDirectory = FileManager.default.temporaryDirectory.path
    settings.fileNameTemplate = "Meow Audio \(UUID().uuidString)"
    settings.videoFormat = .mov
    settings.audioFormat = .flac

    let url = try RecordingStore.outputURL(settings: settings, source: .systemAudio)
    #expect(url.pathExtension == "caf")
}

@Test("Recording file name expands tokens and removes path separators")
@MainActor
func recordingFileNameExpansion() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let date = calendar.date(from: DateComponents(
        year: 2026,
        month: 6,
        day: 14,
        hour: 9,
        minute: 8,
        second: 7
    ))!
    #expect(
        RecordingStore.expandedFileName(
            template: "Meow/Recording yyyy-MM-dd HH:mm:ss",
            date: date
        ) == "Meow-Recording 2026-06-14 09-08-07"
    )
}

@Test("Recording retention applies count, age, and storage limits")
@MainActor
func recordingRetentionPolicies() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let artifacts = (0..<8).map { index in
        RecordingArtifact(
            id: UUID(),
            source: .display,
            createdAt: now.addingTimeInterval(TimeInterval(-index * 86_400)),
            duration: 10,
            fileURL: URL(fileURLWithPath: "/tmp/\(index).mp4"),
            thumbnailURL: nil,
            width: 1920,
            height: 1080,
            fileSize: 100,
            videoCodec: .h264,
            hasSystemAudio: true,
            hasMicrophoneAudio: false
        )
    }
    let count = RecordingStore.retainedArtifactIDs(
        artifacts,
        historyLimit: 3,
        retentionDays: 0,
        maxStorageBytes: nil,
        now: now
    )
    #expect(count == Set(artifacts.prefix(3).map(\.id)))

    let age = RecordingStore.retainedArtifactIDs(
        artifacts,
        historyLimit: 100,
        retentionDays: 2,
        maxStorageBytes: nil,
        now: now
    )
    #expect(age == Set(artifacts.prefix(3).map(\.id)))

    let storage = RecordingStore.retainedArtifactIDs(
        artifacts,
        historyLimit: 100,
        retentionDays: 0,
        maxStorageBytes: 250,
        now: now
    )
    #expect(storage == Set(artifacts.prefix(2).map(\.id)))
}
