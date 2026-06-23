import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

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
    #expect(settings.fileHosting == .default)
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
