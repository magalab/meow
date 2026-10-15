import Testing

#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
struct LocalizationTests {
    @Test("Language manager resolves the selected localization bundle")
    func selectedLanguageIsAppliedAtRuntime() {
        let languageManager = LanguageManager.shared
        let originalLanguage: AppLanguage = languageManager.isChinese ? .chinese : .english
        defer { languageManager.apply(originalLanguage) }

        languageManager.apply(.english)
        #expect(L10n.prefsLanguageTitle == "Language")
        #expect(L10n.prefsSectionGeneral == "General")

        languageManager.apply(.chinese)
        #expect(L10n.prefsLanguageTitle == "语言")
        #expect(L10n.prefsSectionGeneral == "通用")
    }
}
