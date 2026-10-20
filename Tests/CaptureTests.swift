import MeowCapture
import AppKit
import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@Test("Only region and display capture modes can include application overlays")
func screenshotOverlayRouting() {
    #expect(ScreenshotCaptureMode.region.includesApplicationOverlays)
    #expect(ScreenshotCaptureMode.display.includesApplicationOverlays)
    #expect(!ScreenshotCaptureMode.window.includesApplicationOverlays)
}

@Test("Window picker uses frontmost window order and keeps unknown windows stable")
func captureWindowOrdering() {
    let ordered = CaptureWindowOrdering.order(
        [12, 10, 30, 20],
        frontToBack: [20, 10, 12]
    )
    #expect(ordered == [20, 10, 12, 30])
    #expect(CaptureWindowOrdering.order([12, 10], frontToBack: []) == [12, 10])
}

@Test("Screenshot file name template expands date tokens and sanitizes separators")
@MainActor
func screenshotFileNameTemplateExpansion() {
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
        CaptureStore.expandedFileName(
            template: "Meow/Shot yyyy-MM-dd HH:mm:ss",
            date: date
        ) == "Meow-Shot 2026-06-14 09-08-07"
    )
}

@Test("Capture store loads and rewrites legacy history metadata")
@MainActor
func captureStoreLegacyHistoryCompatibility() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("meow-capture-legacy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let id = UUID()
    let imageURL = directory.appendingPathComponent("legacy.png")
    let thumbnailURL = directory.appendingPathComponent("legacy-thumb.png")
    try Data([1, 2, 3]).write(to: imageURL)
    try Data([4, 5, 6]).write(to: thumbnailURL)
    let legacyMetadata = Data(
        """
        [{
          "id": "\(id.uuidString)",
          "kind": "region",
          "createdAt": 790000000,
          "imageURL": "\(imageURL.absoluteString)",
          "thumbnailURL": "\(thumbnailURL.absoluteString)",
          "width": 1280,
          "height": 720
        }]
        """.utf8
    )
    try legacyMetadata.write(to: directory.appendingPathComponent("index.json"))

    let store = CaptureStore(capturesDirectory: directory)
    let artifact = try #require(store.artifacts.first)
    #expect(store.artifacts.count == 1)
    #expect(artifact.id == id)
    #expect(artifact.kind == .region)
    #expect(artifact.width == 1280)
    #expect(artifact.height == 720)
    #expect(artifact.ocrText == nil)

    store.applyRetention(historyLimit: 100, retentionDays: 0, maxStorageMB: 0)
    let rewritten = try Data(contentsOf: directory.appendingPathComponent("index.json"))
    let records = try #require(JSONSerialization.jsonObject(with: rewritten) as? [[String: Any]])
    #expect(records.count == 1)
    #expect(Set(try #require(records.first).keys) == [
        "id", "kind", "createdAt", "imageURL", "thumbnailURL", "width", "height",
    ])
    #expect(try JSONDecoder().decode([CaptureArtifact].self, from: rewritten) == [artifact])
}

@Test("Region selection converts bottom-left points to top-left pixels")
@MainActor
func screenshotRegionPixelConversion() {
    let rect = ScreenCaptureService.pixelRect(
        for: CGRect(x: 10, y: 20, width: 100, height: 50),
        displayHeight: 500,
        scale: 2
    )

    #expect(rect == CGRect(x: 20, y: 860, width: 200, height: 100))
}

@Test("Scrolling capture settings decode missing fields with safe defaults")
func scrollingCaptureSettingsCompatibility() throws {
    let decoded = try JSONDecoder().decode(ScrollingCaptureSettings.self, from: Data("{}".utf8))
    #expect(decoded == .default)

    let screenshot = try JSONDecoder().decode(ScreenshotSettings.self, from: Data("{}".utf8))
    #expect(screenshot.scrollingCapture == .default)
    #expect(screenshot.scrollingHotkeyKeyCode == 23)
    #expect(screenshot.scrollingHotkeyModifiers == 2560)
}

@Test("Scrolling capture settings clamp unsafe persisted values")
func scrollingCaptureSettingsClampUnsafeValues() throws {
    let data = Data(
        """
        {
          "maximumHeightPixels": -1,
          "maximumTotalPixels": 0,
          "manualCaptureInterval": -4,
          "settlementDelay": 99
        }
        """.utf8
    )
    let decoded = try JSONDecoder().decode(ScrollingCaptureSettings.self, from: data)
    #expect(decoded.maximumHeightPixels == 1_000)
    #expect(decoded.maximumTotalPixels == 1_000_000)
    #expect(decoded.manualCaptureInterval == 0.05)
    #expect(decoded.settlementDelay == 2)
}

@Test("Scrolling capture recognizes identical settled frames")
func scrollingCaptureSettledFrames() {
    let image = makeScrollingSourceImage(width: 180, height: 220)
    #expect(ScrollingCaptureMatcher.framesAreStable(image, image))
}

@Test("Scrolling capture rejects featureless content")
func scrollingCaptureRejectsFeaturelessContent() {
    let first = makeTestImage(width: 180, height: 220)
    let second = makeTestImage(width: 180, height: 220)
    #expect(ScrollingCaptureMatcher.match(previous: first, current: second) == nil)
}

@Test("Scrolling capture matches a known downward content offset")
func scrollingCaptureKnownOffset() throws {
    let source = makeScrollingSourceImage(width: 220, height: 360)
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

@Test("Scrolling capture processor preserves every row at a matched seam")
func scrollingCaptureProcessorPreservesMatchedRows() async throws {
    let source = makeScrollingSourceImage(width: 220, height: 360)
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
    let processor = ScrollingCaptureProcessor(firstFrame: previous, settings: .default)

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

@Test("Scrolling capture detects a fixed top header")
func scrollingCaptureFrozenHeaderDetection() throws {
    let source = makeScrollingSourceImage(width: 220, height: 360)
    let previous = try #require(makeScrollingViewport(
        source: source,
        offset: 0,
        height: 180,
        frozenHeaderHeight: 24
    ))
    let current = try #require(makeScrollingViewport(
        source: source,
        offset: 48,
        height: 180,
        frozenHeaderHeight: 24
    ))

    let detected = ScrollingCaptureMatcher.frozenHeaderHeight(
        previous: previous,
        current: current
    )
    #expect((20...28).contains(detected))
    let match = try #require(ScrollingCaptureMatcher.match(
        previous: previous,
        current: current,
        frozenHeaderHeight: detected
    ))
    #expect(abs(match.verticalOffset - 48) <= 2)
}

@Test("Scrolling capture stitcher appends only new rows")
func scrollingCaptureStitcherDimensions() throws {
    let source = makeScrollingSourceImage(width: 160, height: 300)
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
func scrollingCaptureStitcherContentOrder() throws {
    let source = makeScrollingSourceImage(width: 160, height: 300)
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

@Test("Automatic scrolling completes after repeated stable frames")
func scrollingCaptureAutomaticBottomDetection() async {
    let frame = makeScrollingSourceImage(width: 160, height: 120)
    let processor = ScrollingCaptureProcessor(firstFrame: frame, settings: .default)

    _ = await processor.process(frame, isAutoScrolling: true)
    _ = await processor.process(frame, isAutoScrolling: true)
    let result = await processor.process(frame, isAutoScrolling: true)
    guard case let .reachedLimit(reason, _) = result else {
        Issue.record("Expected stable automatic capture to finish")
        return
    }
    #expect(reason == .completed)
}

@Test("Scrolling capture stitcher enforces height and pixel limits")
func scrollingCaptureStitcherLimits() throws {
    let frame = makeScrollingSourceImage(width: 100, height: 100)
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
func scrollingCaptureReducedResolutionComposition() throws {
    let source = makeScrollingSourceImage(width: 100, height: 240)
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

@Test("Scrolling capture proactively reduces an oversized final image")
func scrollingCaptureProactivelyReducesFinalImage() async throws {
    let frame = makeScrollingSourceImage(width: 100, height: 100)
    let processor = ScrollingCaptureProcessor(firstFrame: frame, settings: .default)

    let finalImage = try #require(await processor.makeFinalImage(maximumPixels: 5_000))
    #expect(finalImage.isReduced)
    #expect(finalImage.image.width * finalImage.image.height <= 5_100)
}

@Test("Manual scrolling is accepted only while the pointer is inside the capture region")
func scrollingCaptureManualScrollRegionFilter() {
    let screenFrame = CGRect(x: -1_920, y: 200, width: 1_920, height: 1_080)
    let captureRect = CGRect(x: 100, y: 80, width: 600, height: 700)

    #expect(ScrollingCaptureController.shouldHandleManualScroll(
        at: CGPoint(x: -1_500, y: 500),
        captureRectInDisplayPoints: captureRect,
        screenFrame: screenFrame
    ))
    #expect(!ScrollingCaptureController.shouldHandleManualScroll(
        at: CGPoint(x: 420, y: 500),
        captureRectInDisplayPoints: captureRect,
        screenFrame: screenFrame
    ))
}

@Test("Scrolling capture composes a thirty-thousand-pixel image")
func scrollingCaptureThirtyThousandPixelComposition() throws {
    let frame = makeScrollingSourceImage(width: 64, height: 1_000)
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

@Test("Large capture artifacts disable automatic OCR and full-resolution editing")
func scrollingCaptureResourceIntensiveActionLimits() {
    let small = captureArtifact(width: 2_000, height: 4_000)
    #expect(small.supportsAutomaticOCR)
    #expect(small.supportsFullResolutionEditing)

    let medium = captureArtifact(width: 4_000, height: 6_000)
    #expect(!medium.supportsAutomaticOCR)
    #expect(medium.supportsFullResolutionEditing)

    let large = captureArtifact(width: 4_000, height: 12_000)
    #expect(!large.supportsAutomaticOCR)
    #expect(!large.supportsFullResolutionEditing)
}

@Test("Pixel magnifier maps local points using each display scale")
func pixelMagnifierUsesDisplayScale() {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
    let standard = CapturePixelMagnifierGeometry.sampleRect(
        at: CGPoint(x: 50, y: 40), in: bounds,
        imageWidth: 100, imageHeight: 80, scale: 1
    )
    let retina = CapturePixelMagnifierGeometry.sampleRect(
        at: CGPoint(x: 50, y: 40), in: bounds,
        imageWidth: 200, imageHeight: 160, scale: 2
    )
    #expect(standard == CGRect(x: 44, y: 34, width: 13, height: 13))
    #expect(retina == CGRect(x: 94, y: 74, width: 13, height: 13))
}

@Test("Pixel magnifier remains within image and screen edges")
func pixelMagnifierClampsAtEdges() {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
    let sample = CapturePixelMagnifierGeometry.sampleRect(
        at: CGPoint(x: 100, y: 0), in: bounds,
        imageWidth: 200, imageHeight: 160, scale: 2
    )
    let frame = CapturePixelMagnifierGeometry.frame(
        near: CGPoint(x: 98, y: 2), in: CGRect(x: 0, y: 0, width: 300, height: 200)
    )
    #expect(sample == CGRect(x: 187, y: 147, width: 13, height: 13))
    #expect(frame.minX >= 0 && frame.maxX <= 300)
    #expect(frame.minY >= 0 && frame.maxY <= 200)
}

@Test("Capture editor command stack supports undo and redo")
@MainActor
func captureEditorUndoRedo() {
    let model = CaptureEditorModel(sourceSize: CGSize(width: 100, height: 80))
    let command = CaptureEditorCommand.rectangle(
        rect: CGRect(x: 10, y: 10, width: 30, height: 20),
        color: .red,
        width: 4
    )

    model.add(command)
    #expect(model.commands == [command])
    #expect(model.canUndo)

    model.undo()
    #expect(model.commands.isEmpty)
    #expect(model.canRedo)

    model.redo()
    #expect(model.commands == [command])
}

@Test("Capture editor crop and resize produce requested dimensions")
func captureEditorCropAndResize() throws {
    let source = makeTestImage(width: 100, height: 80)
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
func captureEditorFlattensAnnotations() throws {
    let source = makeTestImage(width: 80, height: 60)
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
func captureEditorMosaicIsDestructive() throws {
    let source = makeCheckerboardImage(width: 64, height: 64)
    let output = try CaptureEditorRenderer.render(
        source: source,
        commands: [
            .mosaic(rect: CGRect(x: 0, y: 0, width: 64, height: 64)),
        ],
        cropRect: nil
    )

    #expect(imageBytes(output) != imageBytes(source))
}

@Test("OCR search index removes OTPAuth payloads")
@MainActor
func captureSearchIndexExcludesOTPAuth() {
    let sanitized = CaptureStore.sanitizedOCRText(
        """
        ordinary searchable text
        otpauth://totp/Example?secret=JBSWY3DPEHPK3PXP
        another line
        """
    )
    #expect(sanitized == "ordinary searchable text\nanother line")
    #expect(!sanitized.lowercased().contains("otpauth"))
}

@Test("Sensitive content matcher detects common secret text")
func sensitiveContentMatching() {
    #expect(ImageRecognitionService.isSensitiveText("alice@example.com"))
    #expect(ImageRecognitionService.isSensitiveText("API_KEY=sk-example123456789"))
    #expect(ImageRecognitionService.isSensitiveText("+1 (415) 555-1234"))
    #expect(!ImageRecognitionService.isSensitiveText("Release notes for version 2"))
}

@Test("Capture retention applies count, age, and storage limits")
@MainActor
func captureRetentionPolicies() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let artifacts = (0..<12).map { index in
        CaptureArtifact(
            id: UUID(),
            kind: .region,
            createdAt: now.addingTimeInterval(TimeInterval(-index * 86_400)),
            imageURL: URL(fileURLWithPath: "/tmp/\(index).png"),
            thumbnailURL: URL(fileURLWithPath: "/tmp/\(index)-thumb.png"),
            width: 100,
            height: 80
        )
    }

    let countIDs = CaptureStore.retainedArtifactIDs(
        artifacts,
        historyLimit: 10,
        retentionDays: 0,
        maxStorageBytes: nil,
        now: now,
        diskUsage: { _ in 100 }
    )
    #expect(countIDs == Set(artifacts.prefix(10).map(\.id)))

    let ageIDs = CaptureStore.retainedArtifactIDs(
        artifacts,
        historyLimit: 100,
        retentionDays: 3,
        maxStorageBytes: nil,
        now: now,
        diskUsage: { _ in 100 }
    )
    #expect(ageIDs == Set(artifacts.prefix(4).map(\.id)))

    let storageIDs = CaptureStore.retainedArtifactIDs(
        artifacts,
        historyLimit: 100,
        retentionDays: 0,
        maxStorageBytes: 250,
        now: now,
        diskUsage: { _ in 100 }
    )
    #expect(storageIDs == Set(artifacts.prefix(2).map(\.id)))

    let oversizedLatestIDs = CaptureStore.retainedArtifactIDs(
        artifacts,
        historyLimit: 100,
        retentionDays: 0,
        maxStorageBytes: 50,
        now: now,
        diskUsage: { _ in 100 }
    )
    #expect(oversizedLatestIDs == Set([artifacts[0].id]))
}

private func makeTestImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func makeCheckerboardImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    for y in 0..<height {
        for x in 0..<width {
            let isWhite = ((x / 4) + (y / 4)).isMultiple(of: 2)
            context.setFillColor((isWhite ? NSColor.white : NSColor.black).cgColor)
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    return context.makeImage()!
}

private func makeScrollingSourceImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
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
    return context.makeImage()!
}

private func makeScrollingViewport(
    source: CGImage,
    offset: Int,
    height: Int,
    frozenHeaderHeight: Int
) -> CGImage? {
    guard let content = source.cropping(to: CGRect(
        x: 0,
        y: offset,
        width: source.width,
        height: height
    )),
        let context = CGContext(
            data: nil,
            width: source.width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }

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
    return context.makeImage()
}

private func imageBytes(_ image: CGImage) -> Data {
    guard let data = image.dataProvider?.data else { return Data() }
    return data as Data
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

private func captureArtifact(width: Int, height: Int) -> CaptureArtifact {
    CaptureArtifact(
        id: UUID(),
        kind: .scrolling,
        createdAt: .distantPast,
        imageURL: URL(fileURLWithPath: "/tmp/capture.png"),
        thumbnailURL: URL(fileURLWithPath: "/tmp/capture-thumb.png"),
        width: width,
        height: height
    )
}
