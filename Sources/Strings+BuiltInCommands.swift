import Foundation

extension L10n {
    // MARK: - Built-in commands

    static var cmdPreferencesTitle: String {
        loc("cmd.preferences.title")
    }

    static var cmdPreferencesSubtitle: String {
        loc("cmd.preferences.subtitle")
    }

    static var cmdAIChatTitle: String {
        loc("cmd.ai.chat.title")
    }

    static var cmdAIChatSubtitle: String {
        loc("cmd.ai.chat.subtitle")
    }

    static var cmdHealthStartTitle: String {
        loc("cmd.health.start.title")
    }

    static var cmdHealthStartSubtitle: String {
        loc("cmd.health.start.subtitle")
    }

    static var cmdHealthPauseTitle: String {
        loc("cmd.health.pause.title")
    }

    static var cmdHealthPauseSubtitle: String {
        loc("cmd.health.pause.subtitle")
    }

    static var cmdHealthBreakTitle: String {
        loc("cmd.health.break.title")
    }

    static var cmdHealthBreakSubtitle: String {
        loc("cmd.health.break.subtitle")
    }

    static var cmdHealthSkipTitle: String {
        loc("cmd.health.skip.title")
    }

    static var cmdHealthSkipSubtitle: String {
        loc("cmd.health.skip.subtitle")
    }

    static var cmdKeepAwakeStartTitle: String { loc("cmd.keep.awake.start.title") }
    static func cmdKeepAwakeConfiguredSubtitle(mode: String, detail: String) -> String {
        String(format: loc("cmd.keep.awake.configured.subtitle"), mode, detail)
    }
    static var cmdKeepAwakeStopTitle: String { loc("cmd.keep.awake.stop.title") }
    static var cmdKeepAwakeStartingSubtitle: String { loc("cmd.keep.awake.starting.subtitle") }

    static func cmdKeepAwakeActiveSubtitle(mode: String, detail: String) -> String {
        String(format: loc("cmd.keep.awake.active.subtitle"), mode, detail)
    }

    static func cmdKeepAwakeUnavailableSubtitle(message: String) -> String {
        String(format: loc("cmd.keep.awake.unavailable.subtitle"), message)
    }

    static var cmdQuitTitle: String {
        loc("cmd.quit.title")
    }

    static var cmdQuitSubtitle: String {
        loc("cmd.quit.subtitle")
    }

}
