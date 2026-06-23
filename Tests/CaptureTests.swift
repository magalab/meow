import AppKit
import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

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

private func imageBytes(_ image: CGImage) -> Data {
    guard let data = image.dataProvider?.data else { return Data() }
    return data as Data
}
