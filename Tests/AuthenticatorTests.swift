import AppKit
import Foundation
import Testing
@testable import Meow

@Test("TOTP generation matches RFC 6238 SHA-1 vector")
func totpRFC6238Vector() {
    let token = AuthenticatorToken(
        issuer: "RFC",
        account: "test",
        secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
        digits: 8,
        period: 30,
        algorithm: .sha1
    )

    #expect(
        AuthenticatorCodeGenerator.code(
            for: token,
            at: Date(timeIntervalSince1970: 59)
        ) == "94287082"
    )
}

@Test("otpauth URL parameters are parsed")
func otpAuthURLParsing() {
    let parsed = OTPAuthURL.parse(
        "otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA256&digits=8&period=45"
    )

    #expect(parsed?.issuer == "Example")
    #expect(parsed?.account == "alice@example.com")
    #expect(parsed?.secret == "JBSWY3DPEHPK3PXP")
    #expect(parsed?.algorithm == .sha256)
    #expect(parsed?.digits == 8)
    #expect(parsed?.period == 45)
}

@Test("otpauth URL rejects unsupported algorithms")
func otpAuthURLRejectsUnsupportedAlgorithm() {
    let parsed = OTPAuthURL.parse(
        "otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&algorithm=SHA3"
    )
    #expect(parsed == nil)
}

@Test("Older settings default the authenticator to disabled")
func olderSettingsCompatibility() throws {
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(settings.authenticatorEnabled == false)
    #expect(settings.authenticatorICloudSyncEnabled == false)
    #expect(settings.screenshot == .default)
    #expect(!settings.screenshot.automaticallyIndexOCRText)
    #expect(settings.screenshot.postCaptureActionDuration == .tenSeconds)
    #expect(settings.ai.supportsVision)
    #expect(settings.ai.imageMaxDimension == 1600)
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

@Test("Older AI chat messages decode without an image attachment")
func olderAIChatMessageCompatibility() throws {
    let data = Data(
        """
        {
          "id": "0D46DC90-83BE-4A11-A5A4-83C6D29D167A",
          "role": "user",
          "content": "hello"
        }
        """.utf8
    )
    let message = try JSONDecoder().decode(AIChatMessage.self, from: data)
    #expect(message.content == "hello")
    #expect(message.imagePath == nil)
}

@Test("Vision AI request includes an image data URL")
func visionAIRequestIncludesImageData() throws {
    let imageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: imageURL) }

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 2,
        pixelsHigh: 2,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let red = NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1)
    bitmap.setColor(red, atX: 0, y: 0)
    bitmap.setColor(red, atX: 1, y: 0)
    bitmap.setColor(red, atX: 0, y: 1)
    bitmap.setColor(red, atX: 1, y: 1)
    try bitmap.representation(using: .png, properties: [:])!.write(to: imageURL)

    let body = try AIChatService().requestBody(
        messages: [
            AIChatMessage(role: .user, content: "Analyze", imagePath: imageURL.path),
        ],
        settings: .default
    )
    let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let messages = try #require(root["messages"] as? [[String: Any]])
    let userMessage = try #require(messages.last)
    let parts = try #require(userMessage["content"] as? [[String: Any]])
    let imagePart = try #require(parts.first { $0["type"] as? String == "image_url" })
    let imageURLPayload = try #require(imagePart["image_url"] as? [String: Any])
    let encodedURL = try #require(imageURLPayload["url"] as? String)
    #expect(encodedURL.hasPrefix("data:image/jpeg;base64,"))
}

@Test("Vision AI rejects image messages when capability is disabled")
func visionAIRejectsDisabledImageInput() throws {
    var settings = AISettings.default
    settings.supportsVision = false

    do {
        _ = try AIChatService().requestBody(
            messages: [
                AIChatMessage(role: .user, content: "Analyze", imagePath: "/tmp/image.png"),
            ],
            settings: settings
        )
        Issue.record("Expected image input to be rejected")
    } catch AIChatError.visionUnsupported {
        return
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
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

@Test("Older capture metadata decodes without OCR text")
func olderCaptureMetadataCompatibility() throws {
    let data = Data(
        """
        {
          "id": "0D46DC90-83BE-4A11-A5A4-83C6D29D167A",
          "kind": "region",
          "createdAt": 0,
          "imageURL": "file:///tmp/capture.png",
          "thumbnailURL": "file:///tmp/capture-thumb.png",
          "width": 100,
          "height": 80
        }
        """.utf8
    )
    let artifact = try JSONDecoder().decode(CaptureArtifact.self, from: data)
    #expect(artifact.ocrText == nil)
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

@Test("Sync merge keeps one token per secret")
func authenticatorSyncMerge() {
    let remote = AuthenticatorToken(
        issuer: "Remote",
        account: "alice",
        secret: "JBSWY3DPEHPK3PXP"
    )
    let duplicateLocal = AuthenticatorToken(
        issuer: "Local duplicate",
        account: "alice",
        secret: remote.secret
    )
    let localOnly = AuthenticatorToken(
        issuer: "Local",
        account: "bob",
        secret: "GEZDGNBVGY3TQOJQ"
    )

    let merged = AuthenticatorSyncMerge.uniqueTokens(
        local: [duplicateLocal, localOnly],
        remote: [remote]
    )

    #expect(merged.count == 2)
    #expect(merged.contains(where: { $0.id == remote.id }))
    #expect(merged.contains(where: { $0.id == localOnly.id }))
}

@Test("Sync merge excludes locally deleted remote tokens")
func authenticatorSyncMergeDeletionTombstone() {
    let deletedRemote = AuthenticatorToken(
        issuer: "Remote",
        account: "deleted",
        secret: "JBSWY3DPEHPK3PXP"
    )
    let localOnly = AuthenticatorToken(
        issuer: "Local",
        account: "active",
        secret: "GEZDGNBVGY3TQOJQ"
    )

    let merged = AuthenticatorSyncMerge.uniqueTokens(
        local: [localOnly],
        remote: [deletedRemote],
        deletedIDs: [deletedRemote.id]
    )

    #expect(merged == [localOnly])
}

@Test("Authenticator JSON backup round trips")
func authenticatorJSONRoundTrip() throws {
    let token = AuthenticatorToken(
        issuer: "Example",
        account: "alice@example.com",
        secret: "JBSWY3DPEHPK3PXP",
        algorithm: .sha256,
        createdAt: Date(timeIntervalSince1970: 2_000)
    )

    let data = try AuthenticatorJSONCodec.encode(
        tokens: [token],
        exportedAt: Date(timeIntervalSince1970: 1_000)
    )
    let decoded = try AuthenticatorJSONCodec.decode(data)

    #expect(decoded == [token])
}

@Test("Keyden vault JSON can be imported")
func keydenJSONImport() throws {
    let data = Data(
        """
        {
          "vaultVersion": 2,
          "tokens": [
            {
              "id": "0D46DC90-83BE-4A11-A5A4-83C6D29D167A",
              "issuer": "GitHub",
              "account": "alice",
              "label": "",
              "secret": "JBSWY3DPEHPK3PXP",
              "digits": 6,
              "period": 30,
              "algorithm": "SHA1",
              "sortOrder": 0,
              "isPinned": false,
              "updatedAt": "2026-06-10T00:00:00Z"
            }
          ]
        }
        """.utf8
    )

    let decoded = try AuthenticatorJSONCodec.decode(data)
    #expect(decoded.count == 1)
    #expect(decoded.first?.issuer == "GitHub")
    #expect(decoded.first?.account == "alice")
    #expect(decoded.first?.algorithm == .sha1)
}
