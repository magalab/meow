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

@Test("AI API keys are excluded from the settings payload")
func aiAPIKeysAreNotEncodedInSettings() throws {
    var settings = AppSettings.default
    settings.ai.apiKey = "test-secret"

    let root = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
    )
    let ai = try #require(root["ai"] as? [String: Any])
    #expect(ai["apiKey"] == nil)
}

@Test("Settings store migrates legacy AI API keys to Keychain")
func settingsStoreMigratesLegacyAIAPIKey() throws {
    let suiteName = "Meow-SettingsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.default)) as? [String: Any]
    )
    var ai = try #require(object["ai"] as? [String: Any])
    ai["apiKey"] = "legacy-secret"
    object["ai"] = ai
    defaults.set(
        try JSONSerialization.data(withJSONObject: object),
        forKey: "meow.settings"
    )

    let keychain = MemoryAIKeychain()
    let store = SettingsStore(defaults: defaults, aiKeychain: keychain)
    let loaded = store.load()

    #expect(loaded.ai.apiKey == "legacy-secret")
    #expect(keychain.value == "legacy-secret")

    let sanitizedData = try #require(defaults.data(forKey: "meow.settings"))
    let sanitized = try #require(
        JSONSerialization.jsonObject(with: sanitizedData) as? [String: Any]
    )
    let sanitizedAI = try #require(sanitized["ai"] as? [String: Any])
    #expect(sanitizedAI["apiKey"] == nil)
}

@Test("Settings store round trips UserDefaults settings and Keychain API keys")
func settingsStoreRoundTrip() throws {
    let suiteName = "Meow-SettingsRoundTripTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    var settings = AppSettings.default
    settings.finderHotkeyKeyCode = 12
    settings.ai.endpoint = "https://example.com/v1"
    settings.ai.apiKey = "round-trip-secret"

    let keychain = MemoryAIKeychain()
    let store = SettingsStore(defaults: defaults, aiKeychain: keychain)
    store.save(settings)
    let loaded = store.load()

    #expect(loaded.finderHotkeyKeyCode == 12)
    #expect(loaded.ai.endpoint == "https://example.com/v1")
    #expect(loaded.ai.apiKey == "round-trip-secret")
    #expect(keychain.value == "round-trip-secret")
}

@Test("Settings store replaces a corrupt persisted blob with defaults")
func settingsStoreRecoversFromCorruptData() throws {
    let suiteName = "Meow-SettingsCorruptTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(Data("not-json".utf8), forKey: "meow.settings")

    let store = SettingsStore(defaults: defaults, aiKeychain: MemoryAIKeychain())
    let loaded = store.load()

    #expect(loaded.finderHotkeyKeyCode == AppSettings.default.finderHotkeyKeyCode)
    #expect(loaded.finderHotkeyModifiers == AppSettings.default.finderHotkeyModifiers)
    #expect(loaded.ai.endpoint == AppSettings.default.ai.endpoint)
    let recoveredData = try #require(defaults.data(forKey: "meow.settings"))
    let recovered = try JSONDecoder().decode(AppSettings.self, from: recoveredData)
    #expect(recovered.finderHotkeyKeyCode == AppSettings.default.finderHotkeyKeyCode)
    #expect(recovered.finderHotkeyModifiers == AppSettings.default.finderHotkeyModifiers)
    #expect(recovered.ai.endpoint == AppSettings.default.ai.endpoint)
}

@Test("Settings store keeps a legacy API key when Keychain is unavailable")
func settingsStoreKeepsLegacyAPIKeyOnKeychainFailure() throws {
    let suiteName = "Meow-SettingsKeychainFailureTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.default)) as? [String: Any]
    )
    var ai = try #require(object["ai"] as? [String: Any])
    ai["apiKey"] = "legacy-secret"
    object["ai"] = ai
    defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "meow.settings")

    let store = SettingsStore(
        defaults: defaults,
        aiKeychain: UnavailableAIKeychain()
    )
    let loaded = store.load()

    #expect(loaded.ai.apiKey == "legacy-secret")
    let persistedData = try #require(defaults.data(forKey: "meow.settings"))
    let persisted = try #require(JSONSerialization.jsonObject(with: persistedData) as? [String: Any])
    let persistedAI = try #require(persisted["ai"] as? [String: Any])
    #expect(persistedAI["apiKey"] as? String == "legacy-secret")
}

@Test("Settings store persists ordinary changes when Keychain deletion fails")
func settingsStorePersistsOrdinaryChangesAfterKeychainDeleteFailure() throws {
    let suiteName = "Meow-SettingsDeleteFailureTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    var original = AppSettings.default
    original.finderHotkeyKeyCode = 12
    defaults.set(try JSONEncoder().encode(original), forKey: "meow.settings")

    var changed = original
    changed.finderHotkeyKeyCode = 13
    changed.ai.apiKey = ""
    let store = SettingsStore(defaults: defaults, aiKeychain: DeleteFailingAIKeychain())

    #expect(store.save(changed) == .savedWithoutAPIKey)
    let persistedData = try #require(defaults.data(forKey: "meow.settings"))
    let persisted = try JSONDecoder().decode(AppSettings.self, from: persistedData)
    #expect(persisted.finderHotkeyKeyCode == changed.finderHotkeyKeyCode)
}

@Test("Empty settings default the Finder hotkey to Option-E")
func emptySettingsDefaultFinderHotkey() throws {
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

    #expect(settings.finderHotkeyKeyCode == 14)
    #expect(settings.finderHotkeyModifiers == 2048)
}

private final class MemoryAIKeychain: AIKeychainStoring {
    var value: String?

    func read() throws -> String? { value }

    func save(_ value: String) throws {
        self.value = value
    }

    func delete() throws {
        value = nil
    }
}

private final class UnavailableAIKeychain: AIKeychainStoring {
    func read() throws -> String? { throw SettingsTestKeychainError.unavailable }
    func save(_: String) throws { throw SettingsTestKeychainError.unavailable }
    func delete() throws { throw SettingsTestKeychainError.unavailable }
}

private final class DeleteFailingAIKeychain: AIKeychainStoring {
    func read() throws -> String? { "existing-secret" }
    func save(_: String) throws {}
    func delete() throws { throw SettingsTestKeychainError.unavailable }
}

private enum SettingsTestKeychainError: Error {
    case unavailable
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
