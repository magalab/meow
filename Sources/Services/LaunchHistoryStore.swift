import Foundation

private struct LaunchStat: Codable {
    var launches: Int
    var lastLaunchedAt: TimeInterval
}

final class LaunchHistoryStore {
    private enum Key {
        static let launchHistory = "meow.launch-history"
    }

    /// Maximum number of launch history entries to keep in memory
    private static let maxHistoryEntries = 500

    private let defaults = UserDefaults.standard
    private var cachedMap: [String: LaunchStat]?

    func recordLaunch(id: String) {
        var map = loadMap()
        var stat = map[id] ?? LaunchStat(launches: 0, lastLaunchedAt: 0)
        stat.launches += 1
        stat.lastLaunchedAt = Date().timeIntervalSince1970
        map[id] = stat
        saveMap(map)
    }

    func score(for id: String) -> Int {
        let map = loadMap()
        guard let stat = map[id] else { return 0 }

        let now = Date().timeIntervalSince1970
        let age = max(0, now - stat.lastLaunchedAt)

        let recencyBoost: Int
        if age < 24 * 3600 {
            recencyBoost = 12
        } else if age < 7 * 24 * 3600 {
            recencyBoost = 8
        } else if age < 30 * 24 * 3600 {
            recencyBoost = 4
        } else {
            recencyBoost = 1
        }

        let frequencyBoost = min(stat.launches, 20)
        return recencyBoost + frequencyBoost
    }

    private func loadMap() -> [String: LaunchStat] {
        if let cachedMap {
            return cachedMap
        }

        guard let data = defaults.data(forKey: Key.launchHistory),
              let decoded = try? JSONDecoder().decode([String: LaunchStat].self, from: data)
        else {
            cachedMap = [:]
            return [:]
        }
        cachedMap = decoded
        return decoded
    }

    private func saveMap(_ map: [String: LaunchStat]) {
        // Prune oldest entries if over limit to prevent unbounded growth
        var prunedMap = map
        if prunedMap.count > Self.maxHistoryEntries {
            let sortedByRecency = prunedMap.sorted {
                ($0.value.lastLaunchedAt, $0.value.launches) >
                ($1.value.lastLaunchedAt, $1.value.launches)
            }
            let kept = Array(sortedByRecency.prefix(Self.maxHistoryEntries))
            prunedMap = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }

        guard let data = try? JSONEncoder().encode(prunedMap) else { return }
        defaults.set(data, forKey: Key.launchHistory)
        cachedMap = prunedMap
    }
}
