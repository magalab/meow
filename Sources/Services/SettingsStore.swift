import Foundation

final class SettingsStore {
    private enum Key {
        static let settings = "meow.settings"
    }

    private let defaults = UserDefaults.standard

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: Key.settings),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    func save(_ settings: AppSettings) {
        guard let encoded = try? JSONEncoder().encode(settings) else { return }
        defaults.set(encoded, forKey: Key.settings)
    }
}
