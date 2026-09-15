import Foundation

extension L10n {
    // MARK: - Preferences

    static var prefsTitle: String {
        loc("prefs.title")
    }

    static var prefsSubtitle: String {
        loc("prefs.subtitle")
    }

    static var prefsSectionGeneral: String {
        loc("prefs.section.general")
    }

    static var prefsGeneralPageBasics: String {
        loc("prefs.general.page.basics")
    }

    static var prefsGeneralPageDock: String {
        loc("prefs.general.page.dock")
    }

    static var prefsGeneralPageAppearance: String {
        loc("prefs.general.page.appearance")
    }

    static var prefsGeneralPageShortcuts: String {
        loc("prefs.general.page.shortcuts")
    }

    static var keepAwakeEnabledTitle: String { loc("keep.awake.enabled.title") }
    static var keepAwakeEnabledSubtitle: String { loc("keep.awake.enabled.subtitle") }
    static var keepAwakeModeTitle: String { loc("keep.awake.mode.title") }
    static var keepAwakeModeSystem: String { loc("keep.awake.mode.system") }
    static var keepAwakeModeDisplay: String { loc("keep.awake.mode.display") }
    static var keepAwakeDurationTitle: String { loc("keep.awake.duration.title") }
    static var keepAwakeDurationFiveMinutes: String { loc("keep.awake.duration.five.minutes") }
    static var keepAwakeDurationFifteenMinutes: String { loc("keep.awake.duration.fifteen.minutes") }
    static var keepAwakeDurationThirtyMinutes: String { loc("keep.awake.duration.thirty.minutes") }
    static var keepAwakeDurationSixtyMinutes: String { loc("keep.awake.duration.sixty.minutes") }
    static var keepAwakeDurationOneHundredTwentyMinutes: String {
        loc("keep.awake.duration.one.hundred.twenty.minutes")
    }
    static var keepAwakeDurationIndefinite: String { loc("keep.awake.duration.indefinite") }
    static var keepAwakeStatusTitle: String { loc("keep.awake.status.title") }
    static var keepAwakeStatusIdle: String { loc("keep.awake.status.idle") }
    static var keepAwakeStatusStarting: String { loc("keep.awake.status.starting") }
    static var keepAwakeStatusUnavailable: String { loc("keep.awake.status.unavailable") }
    static var keepAwakeStop: String { loc("keep.awake.stop") }
    static var keepAwakeBatteryWarningTitle: String { loc("keep.awake.battery.warning.title") }
    static var keepAwakeBatteryWarning: String { loc("keep.awake.battery.warning") }
    static var keepAwakeRecordingOverlapTitle: String { loc("keep.awake.recording.overlap.title") }
    static var keepAwakeRecordingOverlap: String { loc("keep.awake.recording.overlap") }
    static var keepAwakeErrorTitle: String { loc("keep.awake.error.title") }
    static var keepAwakeUnavailableMessage: String { loc("keep.awake.unavailable.message") }
    static var keepAwakeRemainingMinutes: String { loc("keep.awake.remaining.minutes") }
    static var keepAwakeErrorDisabled: String { loc("keep.awake.error.disabled") }
    static var keepAwakeErrorCleanupPending: String { loc("keep.awake.error.cleanup.pending") }

    static func keepAwakeErrorInvalidAssertionID(mode: String) -> String {
        String(format: loc("keep.awake.error.invalid.assertion.id"), mode)
    }

    static func keepAwakeErrorAssertionCreateFailed(mode: String, status: String) -> String {
        String(format: loc("keep.awake.error.assertion.create.failed"), mode, status)
    }

    static func keepAwakeErrorAssertionReleaseFailed(
        assertionID: String,
        mode: String?,
        status: String
    ) -> String {
        let modeDescription = mode.map {
            String(format: loc("keep.awake.error.assertion.mode"), $0)
        } ?? ""
        return String(
            format: loc("keep.awake.error.assertion.release.failed"),
            assertionID,
            modeDescription,
            status
        )
    }

    static func keepAwakeErrorAssertionRollbackFailed(assertionID: String, status: String) -> String {
        String(format: loc("keep.awake.error.assertion.rollback.failed"), assertionID, status)
    }

    static var prefsSectionKeyboard: String {
        loc("prefs.section.keyboard")
    }

    static var prefsSectionScreenshot: String {
        loc("prefs.section.screenshot")
    }

    static var prefsSectionRecording: String {
        loc("prefs.section.recording")
    }

    static var prefsSectionHistory: String {
        loc("prefs.section.history")
    }

    static var prefsSectionSpeech: String {
        loc("prefs.section.speech")
    }

    static var prefsSectionHealth: String {
        loc("prefs.section.health")
    }

    static var prefsSectionAI: String {
        loc("prefs.section.ai")
    }

    static var prefsSectionClipboard: String { loc("prefs.section.clipboard") }

    static var prefsSectionSystemMonitor: String { loc("prefs.section.system.monitor") }

    static var prefsSystemMonitorEnabledTitle: String { loc("prefs.system.monitor.enabled.title") }
    static var prefsSystemMonitorEnabledSubtitle: String { loc("prefs.system.monitor.enabled.subtitle") }
    static var prefsSystemMonitorStatusStyle: String { loc("prefs.system.monitor.status.style") }
    static var prefsSystemMonitorStatusIcon: String { loc("prefs.system.monitor.status.icon") }
    static var prefsSystemMonitorStatusCPU: String { loc("prefs.system.monitor.status.cpu") }
    static var prefsSystemMonitorStatusMemory: String { loc("prefs.system.monitor.status.memory") }
    static var prefsSystemMonitorStatusCPUAndMemory: String { loc("prefs.system.monitor.status.cpu.memory") }
    static var prefsSystemMonitorInterval: String { loc("prefs.system.monitor.interval") }
    static var prefsSystemMonitorHistory: String { loc("prefs.system.monitor.history") }
    static var prefsSystemMonitorHistoryFiveMinutes: String {
        loc("prefs.system.monitor.history.five.minutes")
    }
    static var prefsSystemMonitorHistoryTenMinutes: String {
        loc("prefs.system.monitor.history.ten.minutes")
    }
    static var prefsSystemMonitorModules: String { loc("prefs.system.monitor.modules") }
    static var prefsSystemMonitorCPU: String { loc("prefs.system.monitor.module.cpu") }
    static var prefsSystemMonitorMemory: String { loc("prefs.system.monitor.module.memory") }
    static var prefsSystemMonitorGPU: String { loc("prefs.system.monitor.module.gpu") }
    static var prefsSystemMonitorNetwork: String { loc("prefs.system.monitor.module.network") }
    static var prefsSystemMonitorDisk: String { loc("prefs.system.monitor.module.disk") }
    static var prefsSystemMonitorPower: String { loc("prefs.system.monitor.module.power") }
    static var prefsSystemMonitorThermal: String { loc("prefs.system.monitor.module.thermal") }

    static var systemMonitorTitle: String { loc("system.monitor.title") }
    static var systemMonitorRefresh: String { loc("system.monitor.refresh") }
    static var systemMonitorWaiting: String { loc("system.monitor.waiting") }
    static var systemMonitorUpdated: String { loc("system.monitor.updated") }
    static var systemMonitorUnavailable: String { loc("system.monitor.unavailable") }
    static var systemMonitorUsage: String { loc("system.monitor.usage") }
    static var systemMonitorPressure: String { loc("system.monitor.pressure") }
    static var systemMonitorNetwork: String { loc("system.monitor.network") }
    static var systemMonitorDisk: String { loc("system.monitor.disk") }
    static var systemMonitorDiskUsage: String { loc("system.monitor.disk.usage") }
    static var systemMonitorGPU: String { loc("system.monitor.gpu") }
    static var systemMonitorMemory: String { loc("system.monitor.memory") }
    static var systemMonitorCPU: String { loc("system.monitor.cpu") }
    static var systemMonitorPower: String { loc("system.monitor.power") }
    static var systemMonitorThermal: String { loc("system.monitor.thermal") }
    static var systemMonitorThermalNominal: String { loc("system.monitor.thermal.nominal") }
    static var systemMonitorThermalFair: String { loc("system.monitor.thermal.fair") }
    static var systemMonitorThermalSerious: String { loc("system.monitor.thermal.serious") }
    static var systemMonitorThermalCritical: String { loc("system.monitor.thermal.critical") }
    static var systemMonitorHistory: String { loc("system.monitor.history") }
    static var systemMonitorNoBattery: String { loc("system.monitor.no.battery") }
    static var systemMonitorCharging: String { loc("system.monitor.charging") }
    static var systemMonitorDischarging: String { loc("system.monitor.discharging") }
    static var systemMonitorAddress: String { loc("system.monitor.address") }
    static var systemMonitorLocalIP: String { loc("system.monitor.local.ip") }
    static var systemMonitorPublicIP: String { loc("system.monitor.public.ip") }
    static var systemMonitorAveragePeak: String { loc("system.monitor.average.peak") }
    static var systemMonitorCopyIP: String { loc("system.monitor.copy.ip") }
    static var systemMonitorCopied: String { loc("system.monitor.copied") }

    static var prefsSectionAbout: String {
        loc("prefs.section.about")
    }

    static var prefsAutoLaunchTitle: String {
        loc("prefs.autolaunch.title")
    }

    static var prefsAutoLaunchSubtitle: String {
        loc("prefs.autolaunch.subtitle")
    }

    static var prefsClipboardTitle: String {
        loc("prefs.clipboard.title")
    }

    static var prefsClipboardSubtitle: String {
        loc("prefs.clipboard.subtitle")
    }
    static var prefsClipboardImagePreviewTitle: String {
        loc("prefs.clipboard.image.preview.title")
    }
    static var prefsClipboardImagePreviewSubtitle: String {
        loc("prefs.clipboard.image.preview.subtitle")
    }
    static var prefsClipboardRetentionTitle: String { loc("prefs.clipboard.retention.title") }
    static var prefsClipboardRetentionSubtitle: String { loc("prefs.clipboard.retention.subtitle") }
    static var clipboardRetentionDay: String { loc("clipboard.retention.day") }
    static var clipboardRetentionWeek: String { loc("clipboard.retention.week") }
    static var clipboardRetentionMonth: String { loc("clipboard.retention.month") }
    static var clipboardRetentionThreeMonths: String { loc("clipboard.retention.three.months") }
    static var clipboardRetentionSixMonths: String { loc("clipboard.retention.six.months") }
    static var clipboardRetentionYear: String { loc("clipboard.retention.year") }
    static var clipboardRetentionForever: String { loc("clipboard.retention.forever") }
    static var prefsClipboardStorageLimitTitle: String { loc("prefs.clipboard.storage.limit.title") }
    static var prefsClipboardStorageLimitSubtitle: String { loc("prefs.clipboard.storage.limit.subtitle") }
    static var prefsClipboardStorageTitle: String { loc("prefs.clipboard.storage.title") }
    static var prefsClipboardStorageSubtitle: String { loc("prefs.clipboard.storage.subtitle") }
    static var prefsClipboardOpenFolder: String { loc("prefs.clipboard.open.folder") }
    static var prefsClipboardExcludedAppsTitle: String { loc("prefs.clipboard.excluded.apps.title") }
    static var prefsClipboardExcludedAppsSubtitle: String { loc("prefs.clipboard.excluded.apps.subtitle") }
    static var prefsClipboardExcludedAppsAdd: String { loc("prefs.clipboard.excluded.apps.add") }
    static var prefsClipboardExcludedAppsRemove: String { loc("prefs.clipboard.excluded.apps.remove") }
    static var prefsClipboardExcludedAppsPickerTitle: String { loc("prefs.clipboard.excluded.apps.picker.title") }
    static var prefsClipboardExcludedAppErrorTitle: String { loc("prefs.clipboard.excluded.apps.error.title") }
    static var prefsClipboardExcludedAppDuplicate: String { loc("prefs.clipboard.excluded.apps.duplicate") }

    static var prefsHotkeyTitle: String {
        loc("prefs.hotkey.title")
    }

    static var prefsHotkeySubtitle: String {
        loc("prefs.hotkey.subtitle")
    }

    static var prefsHotkeyRecording: String {
        loc("prefs.hotkey.recording")
    }

    static var prefsHotkeyRecordingHint: String {
        loc("prefs.hotkey.recording.hint")
    }

    static var prefsFinderHotkeyTitle: String {
        loc("prefs.finder.hotkey.title")
    }

    static var prefsFinderHotkeySubtitle: String {
        loc("prefs.finder.hotkey.subtitle")
    }

    static var prefsFinderHotkeyError: String {
        loc("prefs.finder.hotkey.error")
    }

}
