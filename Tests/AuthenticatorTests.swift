import AppKit
import AVFoundation
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
    #expect(settings.recording == .default)
    #expect(settings.tts == .default)
    #expect(!settings.screenshot.automaticallyIndexOCRText)
    #expect(settings.screenshot.postCaptureActionDuration == .tenSeconds)
    #expect(settings.ai.supportsVision)
    #expect(settings.ai.imageMaxDimension == 1600)
}

@Test("TTS settings decode missing fields and normalize invalid values")
func ttsSettingsCompatibility() throws {
    let decoded = try JSONDecoder().decode(
        TtsSettings.self,
        from: Data(#"{"enabled":true,"speed":9,"voiceID":999}"#.utf8)
    )
    let normalized = decoded.normalized()

    #expect(decoded.enabled)
    #expect(decoded.model == .matchaChineseEnglish)
    #expect(normalized.speed == 1)
    #expect(normalized.voiceID == 0)
    #expect(decoded.autoPlay)

    let migrated = try JSONDecoder().decode(
        TtsSettings.self,
        from: Data(#"{"enabled":true,"model":"legacyUnsupportedModel","voiceID":57}"#.utf8)
    )
    #expect(migrated.model == .matchaChineseEnglish)
    #expect(migrated.voiceID == 0)
}

@Test("TTS model manifest identifies a complete installation")
@MainActor
func ttsModelManifestValidation() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-TTS-Test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let model = TtsModelKind.matchaChineseEnglish
    let modelDirectory = root.appendingPathComponent(model.storageDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
    let store = TtsModelStore(modelsRootDirectory: root)
    #expect(!store.isInstalled)

    for relativePath in model.requiredRelativePaths {
        let url = modelDirectory.appendingPathComponent(relativePath)
        if url.pathExtension.isEmpty {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try Data().write(to: url)
        }
    }
    store.refreshState()

    #expect(store.isInstalled)
    #expect(store.state == .installed)
    #expect(model.archive.fileName == "matcha-icefall-zh-en.tar.bz2")
    #expect(model.additionalFiles.map(\.relativePath) == ["vocos-16khz-univ.onnx"])
}

@Test("TTS text normalization and chunking preserve mixed-language content")
func ttsTextChunking() {
    let normalized = SpeechSynthesisService.normalizedText("  Hello   世界。\n下一句  ")
    #expect(normalized == "Hello 世界。下一句")
    #expect(SpeechSynthesisService.normalizedText("你好，") == "你好")
    #expect(
        SpeechSynthesisService.normalizedText("你好， 我是你的好朋友，小汪.")
            == "你好，我是你的好朋友，小汪。"
    )
    #expect(
        SpeechSynthesisService.normalizedText("按 ⌘S 保存，或用 ⌥D 翻译。")
            == "按 Command plus essay 保存，或用 Option plus deep 翻译。"
    )

    let longText = Array(repeating: "中文 and English sentence。", count: 40).joined(separator: " ")
    let chunks = SpeechSynthesisService.chunks(from: longText, maximumLength: 120)
    #expect(chunks.count > 1)
    #expect(chunks.allSatisfy { !$0.isEmpty })
    #expect(chunks.joined(separator: " ").contains("中文"))
    #expect(chunks.joined(separator: " ").contains("English"))

    let chineseChunks = SpeechSynthesisService.chunks(from: "你好，我是你的好朋友，小汪。", maximumLength: 120)
    #expect(chineseChunks == ["你好，我是你的好朋友，小汪。"])
}

@Test("TTS WAV export preserves sample rate and duration")
func ttsWAVExport() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-TTS-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let result = TtsAudioResult(
        samples: Array(repeating: 0.1, count: 2_400),
        sampleRate: 24_000,
        text: "test",
        voiceID: 0
    )

    try SpeechSynthesisService.writeWAV(result, to: url)
    let audioFile = try AVAudioFile(forReading: url)
    #expect(Int(audioFile.fileFormat.sampleRate) == 24_000)
    #expect(audioFile.length == 2_400)
    #expect(abs(result.duration - 0.1) < 0.0001)
}

@Test("Installed Matcha model synthesizes Chinese and English")
func installedMatchaModelSmokeTest() async throws {
    guard let modelPath = ProcessInfo.processInfo.environment["MEOW_TTS_MODEL_DIR"] else {
        return
    }
    let synthesizer = try SherpaOnnxSynthesizer(
        model: .matchaChineseEnglish,
        modelDirectory: URL(fileURLWithPath: modelPath)
    )
    let result = try await synthesizer.synthesize(
        text: "Hello from Meow. 你好，欢迎使用离线语音合成。",
        voiceID: 0,
        speed: 1,
        progress: { _ in }
    )
    #expect(result.sampleRate == 16_000)
    #expect(result.samples.count > 16_000)
}

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
