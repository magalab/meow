import Foundation
import Security

protocol AuthenticatorSyncProviding {
    func probe() throws
    func loadTokens() throws -> [AuthenticatorToken]
    func upsert(_ token: AuthenticatorToken) throws
    func delete(id: UUID) throws
}

struct ICloudKeychainAuthenticatorSyncProvider: AuthenticatorSyncProviding {
    private let probeAccount = "__meow_sync_probe__"

    private var service: String {
        "\(Bundle.main.bundleIdentifier ?? "tech.lury.meow").authenticator.sync.v1"
    }

    func probe() throws {
        try deleteItem(account: probeAccount, ignoreMissing: true)
        let status = SecItemAdd(addQuery(account: probeAccount, data: Data([0])), nil)
        guard status == errSecSuccess else {
            throw AuthenticatorSyncProviderError.keychain(status)
        }
        try deleteItem(account: probeAccount, ignoreMissing: true)
    }

    func loadTokens() throws -> [AuthenticatorToken] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: true,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw AuthenticatorSyncProviderError.keychain(status)
        }

        let items: [[String: Any]]
        if let array = result as? [[String: Any]] {
            items = array
        } else if let item = result as? [String: Any] {
            items = [item]
        } else {
            throw AuthenticatorSyncProviderError.invalidData
        }

        return try items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  account != probeAccount
            else {
                return nil
            }
            guard let data = item[kSecValueData as String] as? Data else {
                throw AuthenticatorSyncProviderError.invalidData
            }
            return try JSONDecoder().decode(AuthenticatorToken.self, from: data)
        }
    }

    func upsert(_ token: AuthenticatorToken) throws {
        let account = token.id.uuidString.lowercased()
        let data = try JSONEncoder().encode(token)
        let query = itemQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AuthenticatorSyncProviderError.keychain(updateStatus)
        }

        let addStatus = SecItemAdd(addQuery(account: account, data: data), nil)
        guard addStatus == errSecSuccess else {
            throw AuthenticatorSyncProviderError.keychain(addStatus)
        }
    }

    func delete(id: UUID) throws {
        try deleteItem(account: id.uuidString.lowercased(), ignoreMissing: true)
    }

    private func itemQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
        ]
    }

    private func addQuery(account: String, data: Data) -> CFDictionary {
        var query = itemQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return query as CFDictionary
    }

    private func deleteItem(account: String, ignoreMissing: Bool) throws {
        let status = SecItemDelete(itemQuery(account: account) as CFDictionary)
        if status == errSecSuccess || (ignoreMissing && status == errSecItemNotFound) {
            return
        }
        throw AuthenticatorSyncProviderError.keychain(status)
    }
}

enum AuthenticatorSyncProviderError: Error {
    case invalidData
    case keychain(OSStatus)
}
