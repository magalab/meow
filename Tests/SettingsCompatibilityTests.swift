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
    #expect(settings.whiteboard == .default)
    #expect(!settings.whiteboard.enabled)
    #expect(settings.tts == .default)
    #expect(!settings.screenshot.automaticallyIndexOCRText)
    #expect(settings.screenshot.postCaptureActionDuration == .tenSeconds)
    #expect(settings.ai.supportsVision)
    #expect(settings.ai.imageMaxDimension == 1600)
    #expect(settings.fileHosting == .default)
    #expect(settings.systemMonitor == .default)
}

@Test("Finder shortcut localization is complete")
func finderShortcutLocalizationIsComplete() throws {
    let resourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Resources", isDirectory: true)
    let keys = [
        "prefs.finder.hotkey.title",
        "prefs.finder.hotkey.subtitle",
        "prefs.finder.hotkey.error",
    ]

    for language in ["en", "zh-Hans"] {
        let url = resourceRoot
            .appendingPathComponent("\(language).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let localizable = try String(contentsOf: url, encoding: .utf8)
        for key in keys {
            #expect(localizable.contains("\"\(key)\" ="))
        }
    }
}

@Test("Empty settings default the Finder hotkey to Option-E")
func emptySettingsDefaultFinderHotkey() throws {
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

    #expect(settings.finderHotkeyKeyCode == 14)
    #expect(settings.finderHotkeyModifiers == 2048)
}

@Test("Finder hotkey settings round trip")
func finderHotkeySettingsRoundTrip() throws {
    var settings = AppSettings.default
    settings.finderHotkeyKeyCode = 0
    settings.finderHotkeyModifiers = 4096

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

    #expect(decoded.finderHotkeyKeyCode == 0)
    #expect(decoded.finderHotkeyModifiers == 4096)
}

@Test("System monitor settings clamp unsafe persisted values")
func systemMonitorSettingsCompatibility() throws {
    let data = Data(
        """
        {
          "systemMonitor": {
            "enabled": true,
            "updateInterval": 0.1,
            "enabledModules": []
          }
        }
        """.utf8
    )

    let settings = try JSONDecoder().decode(AppSettings.self, from: data)
    #expect(settings.systemMonitor.enabled)
    #expect(settings.systemMonitor.updateInterval == 1)
    #expect(!settings.systemMonitor.enabledModules.isEmpty)
}

@Test("Partial whiteboard settings use safe opt-in defaults")
func partialWhiteboardSettingsCompatibility() throws {
    let data = Data(
        """
        {
          "whiteboard": {
            "enabled": true,
            "backgroundStyle": "invalid-future-value"
          }
        }
        """.utf8
    )

    let settings = try JSONDecoder().decode(AppSettings.self, from: data)

    #expect(settings.whiteboard.enabled)
    #expect(settings.whiteboard.surfaceStyle == .paper)
    #expect(settings.whiteboard.guideStyle == .dots)
    #expect(settings.whiteboard.outputBackgroundStyle == .transparent)
    #expect(settings.whiteboard.idleVisibility == .hidden)
    #expect(settings.whiteboard.includeInCaptures)
    #expect(settings.whiteboard.hotkeyKeyCode == WhiteboardSettings.default.hotkeyKeyCode)
}

@Test("Legacy whiteboard background settings migrate to independent guides")
func legacyWhiteboardBackgroundMigration() throws {
    let data = Data(
        """
        {
          "whiteboard": {
            "enabled": true,
            "backgroundStyle": "grid"
          }
        }
        """.utf8
    )

    let settings = try JSONDecoder().decode(AppSettings.self, from: data)
    let encoded = try JSONEncoder().encode(settings.whiteboard)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    #expect(settings.whiteboard.surfaceStyle == .paper)
    #expect(settings.whiteboard.guideStyle == .grid)
    #expect(settings.whiteboard.outputBackgroundStyle == .transparent)
    #expect(object["backgroundStyle"] == nil)
    #expect(object["surfaceStyle"] as? String == "paper")
    #expect(object["guideStyle"] as? String == "grid")
}

@Test("Legacy default whiteboard shortcut migrates to Option-Shift-W")
func legacyWhiteboardShortcutMigration() throws {
    let settings = try JSONDecoder().decode(
        WhiteboardSettings.self,
        from: Data(
            """
            {
              "enabled": true,
              "hotkeyKeyCode": 13,
              "hotkeyModifiers": 2304
            }
            """.utf8
        )
    )

    #expect(WhiteboardSettings.default.hotkeyKeyCode == 13)
    #expect(WhiteboardSettings.default.hotkeyModifiers == 2560)
    #expect(settings.hotkeyKeyCode == 13)
    #expect(settings.hotkeyModifiers == 2560)
}

@Test("Whiteboard host localization is complete in English and Simplified Chinese")
func whiteboardHostLocalizationIsComplete() throws {
    let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Resources", isDirectory: true)
    let keys = [
        "prefs.section.whiteboard",
        "whiteboard.enabled.title",
        "whiteboard.enabled.subtitle",
        "whiteboard.hotkey.title",
        "whiteboard.hotkey.subtitle",
        "whiteboard.hotkey.error",
        "whiteboard.idle.title",
        "whiteboard.idle.subtitle",
        "whiteboard.idle.hidden",
        "whiteboard.idle.visible",
        "whiteboard.surface.title",
        "whiteboard.surface.subtitle",
        "whiteboard.surface.transparent",
        "whiteboard.surface.paper",
        "whiteboard.guide.title",
        "whiteboard.guide.subtitle",
        "whiteboard.guide.none",
        "whiteboard.guide.dots",
        "whiteboard.guide.grid",
        "whiteboard.output.background.title",
        "whiteboard.output.background.subtitle",
        "whiteboard.output.background.transparent",
        "whiteboard.output.background.paper",
        "whiteboard.capture.title",
        "whiteboard.capture.subtitle",
        "whiteboard.opacity.title",
        "whiteboard.opacity.subtitle",
        "whiteboard.scope.title",
        "whiteboard.scope.subtitle",
        "whiteboard.menu.toggle",
        "whiteboard.send.image",
        "whiteboard.error.title",
        "whiteboard.no.recent.screenshot",
        "cmd.whiteboard.open.title",
        "cmd.whiteboard.open.subtitle",
        "cmd.whiteboard.toggle.title",
        "cmd.whiteboard.toggle.subtitle",
        "cmd.whiteboard.latest.title",
        "cmd.whiteboard.latest.subtitle",
    ]

    for language in ["en", "zh-Hans"] {
        let url = sourceRoot
            .appendingPathComponent("\(language).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let contents = try String(contentsOf: url, encoding: .utf8)
        for key in keys {
            #expect(contents.contains("\"\(key)\" ="))
        }
    }
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
