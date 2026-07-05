import AppKit
import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
@Test("Text service reads and dispatches selected text once")
func textServiceDispatchesSelectedText() {
    let pasteboard = NSPasteboard(name: .init("meow.tests.text-service.valid"))
    pasteboard.clearContents()
    pasteboard.setString("  selected text\n", forType: .string)

    let provider = TextServiceProvider()
    var received: [String] = []
    provider.onProcessText = { received.append($0) }
    var serviceError: NSString?
    provider.processSelectedText(pasteboard, userData: nil, error: &serviceError)

    #expect(received == ["selected text"])
    #expect(serviceError == nil)
}

@MainActor
@Test("Text service rejects empty and non-text pasteboards")
func textServiceRejectsUnavailableText() {
    let pasteboard = NSPasteboard(name: .init("meow.tests.text-service.empty"))
    let provider = TextServiceProvider()
    var callbackCount = 0
    provider.onProcessText = { _ in callbackCount += 1 }

    pasteboard.clearContents()
    pasteboard.setString(" \n ", forType: .string)
    var emptyError: NSString?
    provider.processSelectedText(pasteboard, userData: nil, error: &emptyError)

    pasteboard.clearContents()
    pasteboard.setData(Data([0x01]), forType: .png)
    var nonTextError: NSString?
    provider.processSelectedText(pasteboard, userData: nil, error: &nonTextError)

    #expect(callbackCount == 0)
    #expect(emptyError != nil)
    #expect(nonTextError != nil)
}

@Test("Older settings default selected-text actions to Option-X")
func textActionsHotkeySettingsCompatibility() throws {
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

    #expect(settings.textActionsHotkeyKeyCode == 7)
    #expect(settings.textActionsHotkeyModifiers == 2048)
}

@Test("Selected-text action hotkey settings round trip")
func textActionsHotkeySettingsRoundTrip() throws {
    var settings = AppSettings.default
    settings.textActionsHotkeyKeyCode = 8
    settings.textActionsHotkeyModifiers = 4096

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

    #expect(decoded.textActionsHotkeyKeyCode == 8)
    #expect(decoded.textActionsHotkeyModifiers == 4096)
}

@Test("Text actions expose speech only in an enabled voice build")
func textActionsAvailability() {
    #expect(TextAction.available(canSpeak: false) == [.translate, .askAI])
    #if MEOW_VOICE
    #expect(TextAction.available(canSpeak: true) == [.translate, .askAI, .speak])
    #else
    #expect(TextAction.available(canSpeak: true) == [.translate, .askAI])
    #endif
}

@MainActor
@Test("Selected-text actions use an available system symbol")
func textActionsSystemSymbolAvailability() {
    #expect(NSImage(systemSymbolName: TextActionsVisuals.symbol, accessibilityDescription: nil) != nil)
}

@Test("Text service localization resources contain every new key")
func textServiceLocalizationResources() throws {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let resourceRoot = repository.appendingPathComponent("Sources/Resources", isDirectory: true)
    let localizableKeys = [
        "prefs.text.actions.hotkey.title",
        "prefs.text.actions.hotkey.subtitle",
        "text.actions.title",
        "text.actions.selection",
        "text.actions.translate",
        "text.actions.ask.ai",
        "text.actions.speak",
        "text.actions.unavailable.title",
        "text.actions.accessibility.message",
        "text.actions.no.selection",
        "text.actions.hotkey.conflict.title",
        "text.actions.hotkey.conflict.message",
    ]

    for language in ["en", "zh-Hans"] {
        let localizableURL = resourceRoot
            .appendingPathComponent("\(language).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let localizable = try String(contentsOf: localizableURL, encoding: .utf8)
        for key in localizableKeys {
            #expect(localizable.contains("\"\(key)\" ="))
        }

        let servicesURL = localizableURL.deletingLastPathComponent()
            .appendingPathComponent("ServicesMenu.strings")
        let services = try String(contentsOf: servicesURL, encoding: .utf8)
        #expect(services.contains("\"Process with Meow\" ="))
        #expect(services.contains("\"Process with Miao\" ="))
    }
}
