import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@Test("TOTP generation matches RFC 6238 SHA-1 vector")
func totpRFC6238Vector() {
    let token = AuthenticatorToken(
        issuer: "RFC",
        account: "test",
        secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
        digits: 8,
        period: 30,
        algorithm: .sha1
    )

    #expect(
        AuthenticatorCodeGenerator.code(
            for: token,
            at: Date(timeIntervalSince1970: 59)
        ) == "94287082"
    )
}

@Test("otpauth URL parameters are parsed")
func otpAuthURLParsing() {
    let parsed = OTPAuthURL.parse(
        "otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA256&digits=8&period=45"
    )

    #expect(parsed?.issuer == "Example")
    #expect(parsed?.account == "alice@example.com")
    #expect(parsed?.secret == "JBSWY3DPEHPK3PXP")
    #expect(parsed?.algorithm == .sha256)
    #expect(parsed?.digits == 8)
    #expect(parsed?.period == 45)
}

@Test("otpauth URL rejects unsupported algorithms")
func otpAuthURLRejectsUnsupportedAlgorithm() {
    let parsed = OTPAuthURL.parse(
        "otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&algorithm=SHA3"
    )
    #expect(parsed == nil)
}

@Test("Sync merge keeps one token per secret")
func authenticatorSyncMerge() {
    let remote = AuthenticatorToken(
        issuer: "Remote",
        account: "alice",
        secret: "JBSWY3DPEHPK3PXP"
    )
    let duplicateLocal = AuthenticatorToken(
        issuer: "Local duplicate",
        account: "alice",
        secret: remote.secret
    )
    let localOnly = AuthenticatorToken(
        issuer: "Local",
        account: "bob",
        secret: "GEZDGNBVGY3TQOJQ"
    )

    let merged = AuthenticatorSyncMerge.uniqueTokens(
        local: [duplicateLocal, localOnly],
        remote: [remote]
    )

    #expect(merged.count == 2)
    #expect(merged.contains(where: { $0.id == remote.id }))
    #expect(merged.contains(where: { $0.id == localOnly.id }))
}

@Test("Sync merge excludes locally deleted remote tokens")
func authenticatorSyncMergeDeletionTombstone() {
    let deletedRemote = AuthenticatorToken(
        issuer: "Remote",
        account: "deleted",
        secret: "JBSWY3DPEHPK3PXP"
    )
    let localOnly = AuthenticatorToken(
        issuer: "Local",
        account: "active",
        secret: "GEZDGNBVGY3TQOJQ"
    )

    let merged = AuthenticatorSyncMerge.uniqueTokens(
        local: [localOnly],
        remote: [deletedRemote],
        deletedIDs: [deletedRemote.id]
    )

    #expect(merged == [localOnly])
}

@Test("Authenticator JSON backup round trips")
func authenticatorJSONRoundTrip() throws {
    let token = AuthenticatorToken(
        issuer: "Example",
        account: "alice@example.com",
        secret: "JBSWY3DPEHPK3PXP",
        algorithm: .sha256,
        createdAt: Date(timeIntervalSince1970: 2_000)
    )

    let data = try AuthenticatorJSONCodec.encode(
        tokens: [token],
        exportedAt: Date(timeIntervalSince1970: 1_000)
    )
    let decoded = try AuthenticatorJSONCodec.decode(data)

    #expect(decoded == [token])
}

@Test("Keyden vault JSON can be imported")
func keydenJSONImport() throws {
    let data = Data(
        """
        {
          "vaultVersion": 2,
          "tokens": [
            {
              "id": "0D46DC90-83BE-4A11-A5A4-83C6D29D167A",
              "issuer": "GitHub",
              "account": "alice",
              "label": "",
              "secret": "JBSWY3DPEHPK3PXP",
              "digits": 6,
              "period": 30,
              "algorithm": "SHA1",
              "sortOrder": 0,
              "isPinned": false,
              "updatedAt": "2026-06-10T00:00:00Z"
            }
          ]
        }
        """.utf8
    )

    let decoded = try AuthenticatorJSONCodec.decode(data)
    #expect(decoded.count == 1)
    #expect(decoded.first?.issuer == "GitHub")
    #expect(decoded.first?.account == "alice")
    #expect(decoded.first?.algorithm == .sha1)
}

@Test("Authenticator service loads, persists, and deletes tokens through its vault boundary")
@MainActor
func authenticatorServiceUsesInjectedVault() throws {
    let suiteName = "Meow-AuthenticatorServiceTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let token = AuthenticatorToken(
        issuer: "Existing",
        account: "alice",
        secret: "JBSWY3DPEHPK3PXP"
    )
    let vault = MemoryAuthenticatorVault(tokens: [token])
    let service = AuthenticatorService(
        syncProvider: NoopAuthenticatorSyncProvider(),
        vaultStore: vault,
        defaults: defaults
    )
    service.apply(enabled: true, iCloudSyncEnabled: false, theme: .gingerCat)
    defer { service.apply(enabled: false, iCloudSyncEnabled: false, theme: .gingerCat) }

    #expect(service.isEnabled)
    #expect(service.tokens == [token])

    try service.add(
        issuer: "GitHub",
        account: "bob",
        secret: "GEZDGNBVGY3TQOJQ",
        digits: 6,
        period: 30,
        algorithm: .sha1
    )
    #expect(service.tokens.count == 2)
    #expect(vault.tokens == service.tokens)

    do {
        try service.add(
            issuer: "Duplicate",
            account: "bob",
            secret: "GEZDGNBVGY3TQOJQ",
            digits: 6,
            period: 30,
            algorithm: .sha1
        )
        Issue.record("Expected duplicate token rejection")
    } catch AuthenticatorError.duplicate {
        // Expected.
    }

    let addedToken = try #require(service.tokens.first { $0.secret == "GEZDGNBVGY3TQOJQ" })
    try service.delete(addedToken)
    #expect(service.tokens == [token])
    #expect(vault.saveCount >= 2)
}

private final class MemoryAuthenticatorVault: AuthenticatorVaultStoring {
    var tokens: [AuthenticatorToken]
    var saveCount = 0

    init(tokens: [AuthenticatorToken] = []) {
        self.tokens = tokens
    }

    func load() throws -> [AuthenticatorToken] {
        tokens
    }

    func save(_ tokens: [AuthenticatorToken]) throws {
        self.tokens = tokens
        saveCount += 1
    }
}

private struct NoopAuthenticatorSyncProvider: AuthenticatorSyncProviding {
    func probe() throws {}
    func loadTokens() throws -> [AuthenticatorToken] { [] }
    func upsert(_: AuthenticatorToken) throws {}
    func delete(id _: UUID) throws {}
}
