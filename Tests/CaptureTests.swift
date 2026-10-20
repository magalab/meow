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
