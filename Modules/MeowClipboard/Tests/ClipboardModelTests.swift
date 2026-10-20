import MeowClipboard
import Testing

@Test("Clipboard text previews and search text preserve the copied value")
func clipboardTextModel() {
    let content = ClipboardContent.text("  copied text\nwith a second line  ")

    #expect(content.preview == "copied text with a second line")
    #expect(content.searchText == "  copied text\nwith a second line  ")
    #expect(content.symbolName == "doc.text")
}

@Test("Clipboard image storage settings keep existing defaults")
func clipboardSettingsDefaults() {
    #expect(ClipboardSettings.default.historyEnabled)
    #expect(ClipboardSettings.default.showImagePreviews)
    #expect(ClipboardSettings.default.retention == .threeMonths)
    #expect(ClipboardSettings.default.disabledAppBundleIDs == [
        "com.apple.keychainaccess", "com.apple.Passwords",
    ])
    #expect(ClipboardSettings.default.imageStorageLimitMB == 512)
}

@Test("Clipboard settings enforce the existing minimum image cache limit")
func clipboardSettingsMinimumImageCacheLimit() {
    let settings = ClipboardSettings(
        historyEnabled: true,
        showImagePreviews: true,
        retention: .forever,
        disabledAppBundleIDs: [],
        imageStorageLimitMB: 10
    )

    #expect(settings.imageStorageLimitMB == 128)
}

@Test("Clipboard retention raw values remain stable for persisted settings")
func clipboardRetentionRawValues() {
    #expect(ClipboardRetention.day.rawValue == 1)
    #expect(ClipboardRetention.week.rawValue == 7)
    #expect(ClipboardRetention.month.rawValue == 30)
    #expect(ClipboardRetention.threeMonths.rawValue == 90)
    #expect(ClipboardRetention.sixMonths.rawValue == 180)
    #expect(ClipboardRetention.year.rawValue == 365)
    #expect(ClipboardRetention.forever.rawValue == -1)
}
