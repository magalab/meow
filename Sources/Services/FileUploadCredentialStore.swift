import Foundation
import Security

protocol FileUploadCredentialStoring: Sendable {
    func secret(for configID: UUID) throws -> String?
    func save(secret: String, for configID: UUID) throws
    func deleteSecret(for configID: UUID) throws
}

protocol FileUploadSecurityClient: Sendable {
    func read(service: String, account: String) throws -> Data?
    func save(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct SystemFileUploadSecurityClient: FileUploadSecurityClient {
    func read(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw UploadError.credentialUnavailable }
        return result as? Data
    }

    func save(_ data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw UploadError.credentialUnavailable
            }
        } else if status != errSecSuccess {
            throw UploadError.credentialUnavailable
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UploadError.credentialUnavailable
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}

struct FileUploadCredentialStore: FileUploadCredentialStoring {
    private let service: String
    private let client: any FileUploadSecurityClient

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "tech.lury.meow",
        client: any FileUploadSecurityClient = SystemFileUploadSecurityClient()
    ) {
        service = "\(bundleIdentifier).file-upload"
        self.client = client
    }

    func secret(for configID: UUID) throws -> String? {
        guard let data = try client.read(service: service, account: configID.uuidString) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else {
            throw UploadError.credentialUnavailable
        }
        return value
    }

    func save(secret: String, for configID: UUID) throws {
        try client.save(Data(secret.utf8), service: service, account: configID.uuidString)
    }

    func deleteSecret(for configID: UUID) throws {
        try client.delete(service: service, account: configID.uuidString)
    }
}
