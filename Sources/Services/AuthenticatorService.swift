import AppKit
import CryptoKit
import Security
import SwiftUI

enum AuthenticatorCodeGenerator {
    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func code(for token: AuthenticatorToken, at date: Date = Date()) -> String? {
        guard token.period > 0,
              [6, 8].contains(token.digits),
              let secretData = decodeBase32(token.secret)
        else {
            return nil
        }

        var counter = (UInt64(date.timeIntervalSince1970) / UInt64(token.period)).bigEndian
        let counterData = withUnsafeBytes(of: &counter) { Data($0) }
        let key = SymmetricKey(data: secretData)
        let digest: Data

        switch token.algorithm {
        case .sha1:
            digest = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key))
        case .sha256:
            digest = Data(HMAC<SHA256>.authenticationCode(for: counterData, using: key))
        case .sha512:
            digest = Data(HMAC<SHA512>.authenticationCode(for: counterData, using: key))
        }

        let offset = Int(digest[digest.count - 1] & 0x0f)
        guard offset + 3 < digest.count else { return nil }
        let value =
            (UInt32(digest[offset]) & 0x7f) << 24 |
            UInt32(digest[offset + 1]) << 16 |
            UInt32(digest[offset + 2]) << 8 |
            UInt32(digest[offset + 3])
        let divisor = token.digits == 8 ? UInt32(100_000_000) : UInt32(1_000_000)
        return String(format: "%0\(token.digits)u", value % divisor)
    }

    static func remainingSeconds(for token: AuthenticatorToken, at date: Date = Date()) -> Int {
        guard token.period > 0 else { return 0 }
        let elapsed = Int(date.timeIntervalSince1970) % token.period
        return token.period - elapsed
    }

    static func isValidBase32(_ value: String) -> Bool {
        decodeBase32(value) != nil
    }

    private static func decodeBase32(_ value: String) -> Data? {
        let normalized = AuthenticatorToken.normalizeSecret(value)
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        guard !normalized.isEmpty else { return nil }

        var output = Data()
        var buffer: UInt64 = 0
        var bitCount = 0

        for character in normalized {
            guard let index = base32Alphabet.firstIndex(of: character) else {
                return nil
            }
            buffer = (buffer << 5) | UInt64(index)
            bitCount += 5

            if bitCount >= 8 {
                bitCount -= 8
                output.append(UInt8((buffer >> bitCount) & 0xff))
            }
        }

        return output.isEmpty ? nil : output
    }
}

private struct AuthenticatorVaultStore {
    private let account = "tokens"

    private var service: String {
        "\(Bundle.main.bundleIdentifier ?? "tech.lury.meow").authenticator"
    }

    func load() throws -> [AuthenticatorToken] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AuthenticatorError.keychain(status)
        }
        return try JSONDecoder().decode([AuthenticatorToken].self, from: data)
    }

    func save(_ tokens: [AuthenticatorToken]) throws {
        let data = try JSONEncoder().encode(tokens)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AuthenticatorError.keychain(updateStatus)
        }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AuthenticatorError.keychain(addStatus)
        }
    }
}

enum AuthenticatorError: LocalizedError {
    case disabled
    case invalidSecret
    case invalidURL
    case invalidJSON
    case duplicate
    case syncUnavailable(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return L10n.authenticatorErrorDisabled
        case .invalidSecret:
            return L10n.authenticatorErrorInvalidSecret
        case .invalidURL:
            return L10n.authenticatorErrorInvalidURL
        case .invalidJSON:
            return L10n.authenticatorErrorInvalidJSON
        case .duplicate:
            return L10n.authenticatorErrorDuplicate
        case let .syncUnavailable(message):
            return String(format: L10n.authenticatorErrorSyncUnavailable, message)
        case let .keychain(status):
            let systemMessage = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return String(format: L10n.authenticatorErrorKeychain, systemMessage)
        }
    }
}

@MainActor
final class AuthenticatorService: NSObject, ObservableObject {
    @Published private(set) var tokens: [AuthenticatorToken] = []
    @Published private(set) var isEnabled = false
    @Published private(set) var copiedTokenID: UUID?
    @Published private(set) var theme: AppTheme = .gingerCat
    @Published private(set) var isICloudSyncEnabled = false
    @Published private(set) var syncState: AuthenticatorSyncState = .disabled
    @Published private(set) var lastSyncAt: Date?

    var onCopyCode: ((String) -> Void)?
    var onSensitiveTextUsed: ((String) -> Void)?
    var onICloudSyncPreferenceRejected: (() -> Void)?

    private let vaultStore = AuthenticatorVaultStore()
    private let syncProvider: AuthenticatorSyncProviding
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var copyResetWorkItem: DispatchWorkItem?

    private var syncDeletionTombstonesKey: String {
        "meow.authenticator.icloud.deleted-token-ids"
    }

    override convenience init() {
        self.init(syncProvider: ICloudKeychainAuthenticatorSyncProvider())
    }

    init(syncProvider: AuthenticatorSyncProviding) {
        self.syncProvider = syncProvider
        super.init()
    }

    func apply(enabled: Bool, iCloudSyncEnabled: Bool, theme: AppTheme) {
        self.theme = theme
        if enabled {
            start()
            if iCloudSyncEnabled, !isICloudSyncEnabled {
                if !requestICloudSyncEnabled(true) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onICloudSyncPreferenceRejected?()
                    }
                }
            } else if !iCloudSyncEnabled, isICloudSyncEnabled {
                setICloudSyncDisabled()
            }
        } else {
            stop()
        }
    }

    func showPanel() {
        guard isEnabled else { return }
        if isICloudSyncEnabled {
            try? refreshFromICloud()
        }
        if statusItem == nil {
            setupStatusItem()
        }
        guard let button = statusItem?.button else { return }
        setupPopoverIfNeeded()
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func add(
        issuer: String,
        account: String,
        secret: String,
        digits: Int,
        period: Int,
        algorithm: AuthenticatorAlgorithm
    ) throws {
        guard isEnabled else { throw AuthenticatorError.disabled }
        let normalizedSecret = AuthenticatorToken.normalizeSecret(secret)
        guard AuthenticatorCodeGenerator.isValidBase32(normalizedSecret),
              [6, 8].contains(digits),
              period > 0
        else {
            throw AuthenticatorError.invalidSecret
        }
        try append(
            AuthenticatorToken(
                issuer: issuer,
                account: account,
                secret: normalizedSecret,
                digits: digits,
                period: period,
                algorithm: algorithm
            )
        )
        onSensitiveTextUsed?(secret)
    }

    func importOTPAuth(_ value: String) throws {
        guard isEnabled else { throw AuthenticatorError.disabled }
        guard let parsed = OTPAuthURL.parse(value),
              AuthenticatorCodeGenerator.isValidBase32(parsed.secret)
        else {
            throw AuthenticatorError.invalidURL
        }
        try append(parsed.token())
        onSensitiveTextUsed?(value)
    }

    func exportJSON() throws -> Data {
        guard isEnabled else { throw AuthenticatorError.disabled }
        return try AuthenticatorJSONCodec.encode(tokens: tokens)
    }

    func importJSON(_ data: Data) throws -> (imported: Int, duplicates: Int) {
        guard isEnabled else { throw AuthenticatorError.disabled }

        let importedTokens: [AuthenticatorToken]
        do {
            importedTokens = try AuthenticatorJSONCodec.decode(data)
        } catch {
            throw AuthenticatorError.invalidJSON
        }

        guard !importedTokens.isEmpty else {
            throw AuthenticatorError.invalidJSON
        }

        var knownSecrets = Set(tokens.map(\.secret))
        var uniqueImports: [AuthenticatorToken] = []
        var duplicateCount = 0
        for token in importedTokens {
            if knownSecrets.insert(token.secret).inserted {
                uniqueImports.append(token)
            } else {
                duplicateCount += 1
            }
        }

        guard !uniqueImports.isEmpty else {
            return (0, duplicateCount)
        }

        let previous = tokens
        tokens.append(contentsOf: uniqueImports)
        sortTokens()
        do {
            try persistImportedTokens(uniqueImports)
        } catch {
            tokens = previous
            throw normalizedPersistenceError(error)
        }
        return (uniqueImports.count, duplicateCount)
    }

    func delete(_ token: AuthenticatorToken) throws {
        guard isEnabled else { throw AuthenticatorError.disabled }
        let previous = tokens
        tokens.removeAll { $0.id == token.id }
        do {
            if isICloudSyncEnabled {
                try syncProvider.delete(id: token.id)
            }
            try vaultStore.save(tokens)
            if !isICloudSyncEnabled {
                addSyncDeletionTombstone(token.id)
            }
            markSyncWriteSucceeded()
        } catch {
            tokens = previous
            throw normalizedPersistenceError(error)
        }
    }

    func copyCode(for token: AuthenticatorToken, at date: Date = Date()) {
        guard let code = AuthenticatorCodeGenerator.code(for: token, at: date) else { return }
        if let onCopyCode {
            onCopyCode(code)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
        }
        copiedTokenID = token.id
        copyResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.copiedTokenID = nil
        }
        copyResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    @discardableResult
    func requestICloudSyncEnabled(_ enabled: Bool) -> Bool {
        guard isEnabled else {
            syncState = .unavailable(L10n.authenticatorErrorDisabled)
            return false
        }
        if !enabled {
            setICloudSyncDisabled()
            return true
        }
        guard !isICloudSyncEnabled else { return true }

        syncState = .checking
        do {
            try syncProvider.probe()
            let remoteTokens = try syncProvider.loadTokens()
            let deletedIDs = syncDeletionTombstones
            for id in deletedIDs {
                try syncProvider.delete(id: id)
            }
            let resolvedTokens = AuthenticatorSyncMerge.uniqueTokens(
                local: tokens,
                remote: remoteTokens,
                deletedIDs: deletedIDs
            )
            for token in resolvedTokens {
                try syncProvider.upsert(token)
            }

            tokens = resolvedTokens
            try vaultStore.save(tokens)
            clearSyncDeletionTombstones()
            isICloudSyncEnabled = true
            syncState = .ready
            lastSyncAt = Date()
            return true
        } catch {
            isICloudSyncEnabled = false
            syncState = .unavailable(syncErrorMessage(error))
            return false
        }
    }

    func refreshFromICloud() throws {
        guard isICloudSyncEnabled else {
            throw AuthenticatorError.syncUnavailable(L10n.prefsAuthenticatorSyncDisabledStatus)
        }
        syncState = .checking
        do {
            tokens = AuthenticatorSyncMerge.uniqueTokens(
                local: [],
                remote: try syncProvider.loadTokens()
            )
            try vaultStore.save(tokens)
            syncState = .ready
            lastSyncAt = Date()
        } catch {
            syncState = .unavailable(syncErrorMessage(error))
            throw AuthenticatorError.syncUnavailable(syncErrorMessage(error))
        }
    }

    private func start() {
        guard !isEnabled else { return }
        do {
            tokens = try vaultStore.load()
            isEnabled = true
            setupStatusItem()
        } catch {
            tokens = []
            isEnabled = false
            present(error)
        }
    }

    private func stop() {
        copyResetWorkItem?.cancel()
        copyResetWorkItem = nil
        copiedTokenID = nil
        popover?.close()
        popover = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        tokens.removeAll()
        isEnabled = false
        isICloudSyncEnabled = false
        syncState = .disabled
    }

    private func append(_ token: AuthenticatorToken) throws {
        guard !tokens.contains(where: { $0.secret == token.secret }) else {
            throw AuthenticatorError.duplicate
        }
        let previous = tokens
        tokens.append(token)
        sortTokens()
        do {
            if isICloudSyncEnabled {
                try syncProvider.upsert(token)
            }
            try vaultStore.save(tokens)
            markSyncWriteSucceeded()
        } catch {
            tokens = previous
            throw normalizedPersistenceError(error)
        }
    }

    private func sortTokens() {
        tokens.sort {
            let left = "\($0.issuer) \($0.account)".localizedCaseInsensitiveCompare("\($1.issuer) \($1.account)")
            return left == .orderedAscending
        }
    }

    private func persistImportedTokens(_ importedTokens: [AuthenticatorToken]) throws {
        if isICloudSyncEnabled {
            for token in importedTokens {
                try syncProvider.upsert(token)
            }
        }
        try vaultStore.save(tokens)
        markSyncWriteSucceeded()
    }

    private func setICloudSyncDisabled() {
        isICloudSyncEnabled = false
        syncState = .disabled
    }

    private var syncDeletionTombstones: Set<UUID> {
        let values = defaults.stringArray(forKey: syncDeletionTombstonesKey) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    private func addSyncDeletionTombstone(_ id: UUID) {
        var tombstones = syncDeletionTombstones
        tombstones.insert(id)
        defaults.set(tombstones.map(\.uuidString).sorted(), forKey: syncDeletionTombstonesKey)
    }

    private func clearSyncDeletionTombstones() {
        defaults.removeObject(forKey: syncDeletionTombstonesKey)
    }

    private func syncErrorMessage(_ error: Error) -> String {
        guard let providerError = error as? AuthenticatorSyncProviderError else {
            return error.localizedDescription
        }
        switch providerError {
        case .invalidData:
            return L10n.prefsAuthenticatorSyncInvalidData
        case let .keychain(status):
            if status == errSecMissingEntitlement {
                return L10n.prefsAuthenticatorSyncNeedsSigning
            }
            if status == errSecNotAvailable {
                return L10n.prefsAuthenticatorSyncICloudUnavailable
            }
            return SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
        }
    }

    private func markSyncWriteSucceeded() {
        guard isICloudSyncEnabled else { return }
        syncState = .ready
        lastSyncAt = Date()
    }

    private func normalizedPersistenceError(_ error: Error) -> Error {
        guard error is AuthenticatorSyncProviderError else {
            return error
        }
        let message = syncErrorMessage(error)
        syncState = .unavailable(message)
        return AuthenticatorError.syncUnavailable(message)
    }

    private func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: AuthenticatorVisuals.symbol,
            accessibilityDescription: L10n.authenticatorTitle
        )
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item
    }

    private func setupPopoverIfNeeded() {
        guard popover == nil else { return }
        let controller = NSHostingController(rootView: AuthenticatorPanelView(service: self))
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 370, height: 500)
        popover.contentViewController = controller
        self.popover = popover
    }

    @objc private func togglePanel() {
        if popover?.isShown == true {
            popover?.close()
        } else {
            showPanel()
        }
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.authenticatorTitle
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
