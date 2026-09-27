import Foundation
import Testing

#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

struct LaunchHistoryTests {
    @Test
    func missingEntryHasNoScore() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LaunchHistoryStore(defaults: defaults)

        #expect(store.score(for: "missing") == 0)
    }

    @Test
    func launchFrequencyAndRecencyContributeToScore() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LaunchHistoryStore(defaults: defaults)
        store.recordLaunch(id: "translate")
        store.recordLaunch(id: "translate")

        // Two launches within the last day: recency 12 + frequency 2.
        #expect(store.score(for: "translate") == 14)
    }

    @Test
    func oldEntriesArePrunedWhenHistoryExceedsLimit() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var entries: [String: [String: Any]] = [:]
        for index in 0..<500 {
            entries["entry-\(index)"] = [
                "launches": 1,
                "lastLaunchedAt": TimeInterval(index)
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: entries)
        defaults.set(data, forKey: "meow.launch-history")

        let store = LaunchHistoryStore(defaults: defaults)
        store.recordLaunch(id: "new-entry")

        let savedData = try #require(defaults.data(forKey: "meow.launch-history"))
        let saved = try #require(
            JSONSerialization.jsonObject(with: savedData) as? [String: Any]
        )

        #expect(saved.count == 500)
        #expect(saved["entry-0"] == nil)
        #expect(saved["entry-1"] != nil)
        #expect(saved["new-entry"] != nil)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "Meow-LaunchHistoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
