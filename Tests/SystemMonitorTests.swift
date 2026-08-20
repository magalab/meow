import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@Test("System monitor configuration clamps sampling and history values")
func systemMonitorConfigurationClamping() {
    let configuration = SystemMonitorConfiguration(
        updateInterval: 0.1,
        historyDuration: 9_999,
        enabledModules: [.cpu]
    )

    #expect(configuration.updateInterval == 1)
    #expect(configuration.historyDuration == 1_800)
    #expect(configuration.historyCapacity == 1_800)
}

@Test("System monitor history remains bounded")
func systemMonitorHistoryRemainsBounded() {
    var history = SystemMetricsHistory(capacity: 30)
    for index in 0..<80 {
        var sample = SystemMetricsSnapshot(capturedAt: Date(timeIntervalSince1970: TimeInterval(index)))
        sample.cpuUsage = Double(index) / 100
        history.append(sample)
    }

    #expect(history.samples.count == 30)
    #expect(history.samples.first?.capturedAt == Date(timeIntervalSince1970: 50))
    #expect(history.samples.last?.capturedAt == Date(timeIntervalSince1970: 79))
}

@Test("System monitor snapshot preserves unavailable metrics")
func systemMonitorSnapshotPreservesUnavailableMetrics() {
    let snapshot = SystemMetricsSnapshot(capturedAt: Date(timeIntervalSince1970: 100))

    #expect(snapshot.cpuUsage == nil)
    #expect(snapshot.gpuMemoryUsedBytes == nil)
    #expect(snapshot.batteryFraction == nil)
}

@Test("System monitor localization resources contain the same keys")
func systemMonitorLocalizationIsComplete() throws {
    let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Resources", isDirectory: true)
    let keys = [
        "prefs.section.system.monitor",
        "prefs.system.monitor.enabled.title",
        "prefs.system.monitor.enabled.subtitle",
        "prefs.system.monitor.status.style",
        "prefs.system.monitor.status.icon",
        "prefs.system.monitor.status.cpu",
        "prefs.system.monitor.status.memory",
        "prefs.system.monitor.status.cpu.memory",
        "prefs.system.monitor.interval",
        "prefs.system.monitor.history",
        "prefs.system.monitor.history.five.minutes",
        "prefs.system.monitor.history.ten.minutes",
        "prefs.system.monitor.modules",
        "prefs.system.monitor.module.cpu",
        "prefs.system.monitor.module.memory",
        "prefs.system.monitor.module.gpu",
        "prefs.system.monitor.module.network",
        "prefs.system.monitor.module.disk",
        "prefs.system.monitor.module.power",
        "prefs.system.monitor.module.thermal",
        "system.monitor.title",
        "system.monitor.refresh",
        "system.monitor.waiting",
        "system.monitor.updated",
        "system.monitor.unavailable",
        "system.monitor.usage",
        "system.monitor.pressure",
        "system.monitor.network",
        "system.monitor.disk",
        "system.monitor.disk.usage",
        "system.monitor.gpu",
        "system.monitor.memory",
        "system.monitor.cpu",
        "system.monitor.power",
        "system.monitor.thermal",
        "system.monitor.thermal.nominal",
        "system.monitor.thermal.fair",
        "system.monitor.thermal.serious",
        "system.monitor.thermal.critical",
        "system.monitor.history",
        "system.monitor.no.battery",
        "system.monitor.charging",
        "system.monitor.discharging",
        "system.monitor.address",
        "system.monitor.local.ip",
        "system.monitor.public.ip",
        "system.monitor.average.peak",
        "system.monitor.copy.ip",
        "system.monitor.copied",
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
