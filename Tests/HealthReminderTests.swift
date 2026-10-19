import Foundation
import Testing

#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
struct HealthReminderTests {
    @Test
    func recordsPersistAcrossStoreInstances() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HealthReminderStore(defaults: defaults)
        store.save(
            HealthReminderDayRecord(
                date: "2026-09-27",
                completedBreaks: 3,
                skippedBreaks: 1
            )
        )

        let restored = HealthReminderStore(defaults: defaults)
        let record = restored.record(for: "2026-09-27")

        #expect(record.completedBreaks == 3)
        #expect(record.skippedBreaks == 1)
    }

    @Test
    func recordsAreLimitedToTheMostRecentNinetyDays() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HealthReminderStore(defaults: defaults)
        let dates = (0..<91).map { index in
            HealthReminderStore.todayString(
                Date(timeIntervalSince1970: 1_704_067_200 + Double(index) * 86_400)
            )
        }

        for (index, date) in dates.enumerated() {
            store.save(
                HealthReminderDayRecord(
                    date: date,
                    completedBreaks: index,
                    skippedBreaks: 0
                )
            )
        }

        let restored = HealthReminderStore(defaults: defaults)
        #expect(restored.record(for: dates[0]).completedBreaks == 0)
        #expect(restored.record(for: dates[1]).completedBreaks == 1)
        #expect(restored.record(for: dates[90]).completedBreaks == 90)
    }

    @Test
    func unknownDateReturnsAnEmptyRecord() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let record = HealthReminderStore(defaults: defaults).record(for: "2099-01-01")

        #expect(record.date == "2099-01-01")
        #expect(record.completedBreaks == 0)
        #expect(record.skippedBreaks == 0)
    }

    @Test
    func repeatedApplyKeepsOneTimerAndDisableAllowsRestart() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var timers: [Timer] = []
        let store = HealthReminderStore(defaults: defaults)
        let service = HealthReminderService(store: store) { interval, repeats, block in
            let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
            timers.append(timer)
            return timer
        }
        var settings = AppSettings.default
        settings.healthReminder.enabled = true

        service.apply(settings: settings)
        service.apply(settings: settings)

        #expect(timers.count == 1)
        #expect(timers[0].isValid)

        settings.healthReminder.enabled = false
        service.apply(settings: settings)

        #expect(!timers[0].isValid)

        settings.healthReminder.enabled = true
        service.apply(settings: settings)

        #expect(timers.count == 2)
        #expect(timers[1].isValid)
        service.stop()
        #expect(!timers[1].isValid)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "Meow-HealthReminderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
