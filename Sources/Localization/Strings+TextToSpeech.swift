import Foundation

extension L10n {
    // MARK: - Text to Speech

    static var ttsEnabledTitle: String { loc("tts.enabled.title") }
    static var ttsEnabledSubtitle: String { loc("tts.enabled.subtitle") }
    static var ttsDisabled: String { loc("tts.disabled") }
    static var ttsInputTitle: String { loc("tts.input.title") }
    static var ttsInputPlaceholder: String { loc("tts.input.placeholder") }
    static var ttsVoiceSystem: String { loc("tts.voice.system") }
    static var ttsVoiceMoss: String { loc("tts.voice.moss") }
    static var ttsGenerate: String { loc("tts.generate") }
    static var ttsPlay: String { loc("tts.play") }
    static var ttsPause: String { loc("tts.pause") }
    static var ttsResume: String { loc("tts.resume") }
    static var ttsStop: String { loc("tts.stop") }
    static var ttsExport: String { loc("tts.export") }
    static var ttsExportErrorTitle: String { loc("tts.export.error.title") }
    static var ttsStatusIdle: String { loc("tts.status.idle") }
    static var ttsStatusNeedsModel: String { loc("tts.status.needs.model") }
    static var ttsStatusLoading: String { loc("tts.status.loading") }
    static var ttsStatusSynthesizing: String { loc("tts.status.synthesizing") }
    static var ttsStatusReady: String { loc("tts.status.ready") }
    static var ttsStatusReadyDuration: String { loc("tts.status.ready.duration") }
    static var ttsStatusPlaying: String { loc("tts.status.playing") }
    static var ttsStatusPaused: String { loc("tts.status.paused") }
    static var ttsModelSystemTitle: String { loc("tts.model.system.title") }
    static var ttsModelSystemSubtitle: String { loc("tts.model.system.subtitle") }
    static var ttsModelMossTitle: String { loc("tts.model.moss.title") }
    static var ttsModelMossSubtitle: String { loc("tts.model.moss.subtitle") }
    static var ttsModelMossLicense: String { loc("tts.model.moss.license") }
    static var ttsModelLicense: String { loc("tts.model.license") }
    static var ttsModelNotInstalled: String { loc("tts.model.not.installed") }
    static var ttsModelInstalled: String { loc("tts.model.installed") }
    static var ttsModelDownloading: String { loc("tts.model.downloading") }
    static var ttsErrorIncompleteModel: String { loc("tts.error.incomplete.model") }
    static var ttsErrorModelChecksum: String { loc("tts.error.model.checksum") }
    static var ttsErrorLoadModel: String { loc("tts.error.load.model") }
    static var ttsErrorGenerationFailed: String { loc("tts.error.generation.failed") }
    static var ttsErrorEmptyAudio: String { loc("tts.error.empty.audio") }
    static var ttsSelectionUnavailableTitle: String { loc("tts.selection.unavailable.title") }
    static var ttsSelectionPermissionMessage: String { loc("tts.selection.permission.message") }
    static var ttsSelectionEmptyMessage: String { loc("tts.selection.empty.message") }
    static var ttsErrorEmptyText: String { loc("tts.error.empty.text") }
    static var ttsErrorPlaybackFailed: String { loc("tts.error.playback.failed") }
    static var ttsErrorNoAudio: String { loc("tts.error.no.audio") }
    static var ttsErrorExportFailed: String { loc("tts.error.export.failed") }
    static var cmdTtsClipboardTitle: String { loc("cmd.tts.clipboard.title") }
    static var cmdTtsClipboardSubtitle: String { loc("cmd.tts.clipboard.subtitle") }
    static var cmdTtsSelectionTitle: String { loc("cmd.tts.selection.title") }
    static var cmdTtsSelectionSubtitle: String { loc("cmd.tts.selection.subtitle") }

    static var prefsDockTitle: String {
        loc("prefs.dock.title")
    }

    static var prefsDockSubtitle: String {
        loc("prefs.dock.subtitle")
    }

    static var prefsMenuBarTitle: String {
        loc("prefs.menubar.title")
    }

    static var prefsMenuBarSubtitle: String {
        loc("prefs.menubar.subtitle")
    }

    static var prefsDateIconTitle: String {
        loc("prefs.dateicon.title")
    }

    static var prefsDateIconSubtitle: String {
        loc("prefs.dateicon.subtitle")
    }

    static var dateIconOutlinedDay: String {
        loc("dateicon.outlinedday")
    }

    static var dateIconRoundedOutlineDay: String {
        loc("dateicon.roundedoutlineday")
    }

    static var dateIconPawPrint: String {
        loc("dateicon.pawprint")
    }

    static var dateIconDayOnly: String {
        loc("dateicon.dayonly")
    }

    static var dateIconMonthDay: String {
        loc("dateicon.monthday")
    }

    static var dateIconWeekdayDay: String {
        loc("dateicon.weekdayday")
    }

    static var dateIconLunarDate: String {
        loc("dateicon.lunardate")
    }

    static var prefsDockIconTitle: String {
        loc("prefs.dockicon.title")
    }

    static var prefsDockIconSubtitle: String {
        loc("prefs.dockicon.subtitle")
    }

    static var dockIconDefault: String {
        loc("dockicon.default")
    }

    static var dockIconCalendar: String {
        loc("dockicon.calendar")
    }

    static var dockIconFlat: String {
        loc("dockicon.flat")
    }

    static var prefsThemeTitle: String {
        loc("prefs.theme.title")
    }

    static var prefsThemeSubtitle: String {
        loc("prefs.theme.subtitle")
    }

    static var prefsHealthEnabledTitle: String {
        loc("prefs.health.enabled.title")
    }

    static var prefsHealthEnabledSubtitle: String {
        loc("prefs.health.enabled.subtitle")
    }

    static var prefsHealthTodayTitle: String {
        loc("prefs.health.today.title")
    }

    static var prefsHealthDurationTitle: String {
        loc("prefs.health.duration.title")
    }

    static var prefsHealthDurationSubtitle: String {
        loc("prefs.health.duration.subtitle")
    }

    static var prefsHealthGoalTitle: String {
        loc("prefs.health.goal.title")
    }

    static var prefsHealthGoalSubtitle: String {
        loc("prefs.health.goal.subtitle")
    }

    static var prefsHealthModeTitle: String {
        loc("prefs.health.mode.title")
    }

    static var prefsHealthModeSubtitle: String {
        loc("prefs.health.mode.subtitle")
    }

    static var prefsHealthActivityTitle: String {
        loc("prefs.health.activity.title")
    }

    static var prefsHealthActivitySubtitle: String {
        loc("prefs.health.activity.subtitle")
    }

    static var prefsHealthSoundTitle: String {
        loc("prefs.health.sound.title")
    }

    static var prefsHealthSoundSubtitle: String {
        loc("prefs.health.sound.subtitle")
    }

    static var healthBreakModeGentle: String {
        loc("health.break.mode.gentle")
    }

    static var healthBreakModeStrict: String {
        loc("health.break.mode.strict")
    }

    static var healthWorkMinutesValue: String {
        loc("health.work.minutes.value")
    }

    static var healthBreakSecondsValue: String {
        loc("health.break.seconds.value")
    }

    static var healthGoalValue: String {
        loc("health.goal.value")
    }

    static var prefsKeystrokeEnabledTitle: String {
        loc("prefs.keystroke.enabled.title")
    }

    static var prefsKeystrokeEnabledSubtitle: String {
        loc("prefs.keystroke.enabled.subtitle")
    }

    static var prefsKeystrokePageOverview: String {
        loc("prefs.keystroke.page.overview")
    }

    static var prefsKeystrokePageDisplay: String {
        loc("prefs.keystroke.page.display")
    }

    static var prefsKeystrokePagePosition: String {
        loc("prefs.keystroke.page.position")
    }

    static var prefsKeystrokeModifierTitle: String {
        loc("prefs.keystroke.modifier.title")
    }

    static var prefsKeystrokeModifierSubtitle: String {
        loc("prefs.keystroke.modifier.subtitle")
    }

    static var prefsKeystrokeDisplayModeTitle: String {
        loc("prefs.keystroke.display.mode.title")
    }

    static var prefsKeystrokeDisplayModeSubtitle: String {
        loc("prefs.keystroke.display.mode.subtitle")
    }

    static var prefsKeystrokePermissionTitle: String {
        loc("prefs.keystroke.permission.title")
    }

    static var prefsKeystrokePermissionSubtitle: String {
        loc("prefs.keystroke.permission.subtitle")
    }

    static var prefsKeystrokePermissionOpen: String {
        loc("prefs.keystroke.permission.open")
    }

    static var prefsKeystrokeStyleTitle: String {
        loc("prefs.keystroke.style.title")
    }

    static var prefsKeystrokeStyleSubtitle: String {
        loc("prefs.keystroke.style.subtitle")
    }

    static var prefsKeystrokePositionTitle: String {
        loc("prefs.keystroke.position.title")
    }

    static var prefsKeystrokeDurationTitle: String {
        loc("prefs.keystroke.duration.title")
    }

    static var prefsKeystrokeDurationSubtitle: String {
        loc("prefs.keystroke.duration.subtitle")
    }

    static var prefsKeystrokePositionSubtitle: String {
        loc("prefs.keystroke.position.subtitle")
    }

    static var prefsKeystrokePositionReset: String {
        loc("prefs.keystroke.position.reset")
    }

    static var prefsKeystrokeOpacityTitle: String {
        loc("prefs.keystroke.opacity.title")
    }

    static var prefsKeystrokeOpacitySubtitle: String {
        loc("prefs.keystroke.opacity.subtitle")
    }

    static var prefsKeystrokeHistoryCountTitle: String {
        loc("prefs.keystroke.history.count.title")
    }

    static var prefsKeystrokeHistoryCountSubtitle: String {
        loc("prefs.keystroke.history.count.subtitle")
    }

    static var keystrokeStyleCompact: String {
        loc("keystroke.style.compact")
    }

    static var keystrokeStyleProminent: String {
        loc("keystroke.style.prominent")
    }

    static var keystrokeDurationShort: String {
        loc("keystroke.duration.short")
    }

    static var keystrokeDurationNormal: String {
        loc("keystroke.duration.normal")
    }

    static var keystrokeDurationLong: String {
        loc("keystroke.duration.long")
    }

    static var keystrokeDurationPersistent: String {
        loc("keystroke.duration.persistent")
    }

    static var keystrokeDurationCustom: String {
        loc("keystroke.duration.custom")
    }

    static var keystrokePositionBottomCenter: String {
        loc("keystroke.position.bottom-center")
    }

    static var keystrokePositionTopCenter: String {
        loc("keystroke.position.top-center")
    }

    static var keystrokePositionBottomLeft: String {
        loc("keystroke.position.bottom-left")
    }

    static var keystrokePositionBottomRight: String {
        loc("keystroke.position.bottom-right")
    }

    static var keystrokePositionTopLeft: String {
        loc("keystroke.position.top-left")
    }

    static var keystrokePositionTopRight: String {
        loc("keystroke.position.top-right")
    }

    static var keystrokePositionCustom: String {
        loc("keystroke.position.custom")
    }

    static var keystrokeHistoryCountOne: String {
        loc("keystroke.history.count.one")
    }

    static var keystrokeHistoryCountTwo: String {
        loc("keystroke.history.count.two")
    }

    static var keystrokeHistoryCountThree: String {
        loc("keystroke.history.count.three")
    }

    static var keystrokeDisplayModeShortcutsAndSpecial: String {
        loc("keystroke.display.mode.shortcuts-special")
    }

    static var keystrokeDisplayModeShortcutsOnly: String {
        loc("keystroke.display.mode.shortcuts-only")
    }

    static var keystrokeDisplayModeAllKeys: String {
        loc("keystroke.display.mode.all-keys")
    }

    static var prefsLanguageTitle: String {
        loc("prefs.language.title")
    }

    static var prefsLanguageSubtitle: String {
        loc("prefs.language.subtitle")
    }

    static var prefsAIEndpointTitle: String {
        loc("prefs.ai.endpoint.title")
    }

    static var prefsAIEndpointSubtitle: String {
        loc("prefs.ai.endpoint.subtitle")
    }

    static var prefsAIKeyTitle: String {
        loc("prefs.ai.key.title")
    }

    static var prefsAIKeySubtitle: String {
        loc("prefs.ai.key.subtitle")
    }

    static var prefsAIKeyCopy: String {
        loc("prefs.ai.key.copy")
    }

    static var prefsAIKeyReveal: String {
        loc("prefs.ai.key.reveal")
    }

    static var prefsAIKeyHide: String {
        loc("prefs.ai.key.hide")
    }

    static var prefsAIModelTitle: String {
        loc("prefs.ai.model.title")
    }

    static var prefsAIModelSubtitle: String {
        loc("prefs.ai.model.subtitle")
    }

    static var prefsAIModelChoose: String {
        loc("prefs.ai.model.choose")
    }

    static var prefsAIModelsRefresh: String {
        loc("prefs.ai.models.refresh")
    }

    static var prefsAIModelsEmpty: String {
        loc("prefs.ai.models.empty")
    }

    static var prefsAIModelsLoaded: String {
        loc("prefs.ai.models.loaded")
    }

    static var prefsAIHistoryTitle: String {
        loc("prefs.ai.history.title")
    }

    static var prefsAIHistorySubtitle: String {
        loc("prefs.ai.history.subtitle")
    }

    static var prefsAIHistoryClear: String {
        loc("prefs.ai.history.clear")
    }

    static var prefsAIHistoryClearTitle: String {
        loc("prefs.ai.history.clear.title")
    }

    static var prefsAIHistoryClearMessage: String {
        loc("prefs.ai.history.clear.message")
    }

    static var prefsAIHistoryOpenFolder: String {
        loc("prefs.ai.history.open.folder")
    }

    static var prefsAboutVersion: String {
        loc("prefs.about.version")
    }

    static var prefsAboutBuild: String {
        loc("prefs.about.build")
    }

    static var prefsAboutPrivacy: String {
        loc("prefs.about.privacy")
    }

    static var prefsAboutPrivacySubtitle: String {
        loc("prefs.about.privacy.subtitle")
    }

    static var prefsAboutRepo: String {
        loc("prefs.about.repo")
    }

    static var prefsAboutOpenRepo: String {
        loc("prefs.about.open.repo")
    }

    static var quitMeow: String {
        loc("quit.meow")
    }

    static var langSystem: String {
        loc("lang.system")
    }

    static var themeGingerCat: String {
        loc("theme.ginger-cat")
    }

    static var themeMistBlue: String {
        loc("theme.mist-blue")
    }

    static var themeGraphiteAmber: String {
        loc("theme.graphite-amber")
    }

    static var themeMossInk: String {
        loc("theme.moss-ink")
    }

}
