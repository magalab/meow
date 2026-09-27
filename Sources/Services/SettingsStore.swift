import Foundation

enum SettingsSaveResult: Equatable {
    case saved
    case savedWithoutAPIKey
    case failed
}

final class SettingsStore {
    private enum Key {
        static let settings = "meow.settings"
    }

    private let defaults: UserDefaults
    private let aiKeychain: any AIKeychainStoring

    init(
        defaults: UserDefaults = .standard,
        aiKeychain: any AIKeychainStoring = AIKeychainStore()
    ) {
        self.defaults = defaults
        self.aiKeychain = aiKeychain
    }

    func load() -> AppSettings {
        let persistedData = defaults.data(forKey: Key.settings)
        var settings: AppSettings
        var shouldPersistSanitizedSettings = false
        if let data = persistedData,
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = .default
            // Rewrite a corrupt blob once so every subsequent launch starts from
            // the recovered defaults instead of retrying the same bad payload.
            shouldPersistSanitizedSettings = persistedData != nil
        }

        let legacyAPIKey = settings.ai.apiKey
        settings.ai.apiKey = ""
        shouldPersistSanitizedSettings = shouldPersistSanitizedSettings || !legacyAPIKey.isEmpty

        do {
            if let storedAPIKey = try aiKeychain.read() {
                settings.ai.apiKey = storedAPIKey
            } else if !legacyAPIKey.isEmpty {
                try aiKeychain.save(legacyAPIKey)
                settings.ai.apiKey = legacyAPIKey
            }
        } catch {
            MeowLog.settings.error("Unable to load AI API key from Keychain: \(error.localizedDescription, privacy: .public)")
            // Keep the legacy value in memory and leave the old blob untouched so a
            // transiently unavailable Keychain does not silently discard the key.
            settings.ai.apiKey = legacyAPIKey
            shouldPersistSanitizedSettings = false
        }

        if shouldPersistSanitizedSettings {
            persist(settings)
        }
        return settings
    }

    @discardableResult
    func save(_ settings: AppSettings) -> SettingsSaveResult {
        var sanitized = settings
        let apiKey = settings.ai.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var apiKeySaveFailed = false
        do {
            if apiKey.isEmpty {
                try aiKeychain.delete()
            } else {
                try aiKeychain.save(apiKey)
            }
        } catch {
            MeowLog.settings.error("Unable to save AI API key to Keychain: \(error.localizedDescription, privacy: .public)")
            apiKeySaveFailed = true
        }
        sanitized.ai.apiKey = ""
        guard persist(sanitized) else { return .failed }
        return apiKeySaveFailed ? .savedWithoutAPIKey : .saved
    }

    @discardableResult
    private func persist(_ settings: AppSettings) -> Bool {
        guard let encoded = try? JSONEncoder().encode(settings) else { return false }
        defaults.set(encoded, forKey: Key.settings)
        return true
    }
}
