import Foundation

enum AuthenticatorVisuals {
    static let symbol = "number.square.fill"
    static let emptySymbol = "number.square"
}

enum AuthenticatorSyncState: Equatable {
    case disabled
    case checking
    case ready
    case unavailable(String)
}

enum AuthenticatorSyncMerge {
    static func uniqueTokens(
        local: [AuthenticatorToken],
        remote: [AuthenticatorToken],
        deletedIDs: Set<UUID> = []
    ) -> [AuthenticatorToken] {
        var tokensBySecret: [String: AuthenticatorToken] = [:]
        for token in (remote + local) where !deletedIDs.contains(token.id) {
            if tokensBySecret[token.secret] == nil {
                tokensBySecret[token.secret] = token
            }
        }
        return tokensBySecret.values.sorted {
            let left = "\($0.issuer) \($0.account)"
            let right = "\($1.issuer) \($1.account)"
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }
}

enum AuthenticatorAlgorithm: String, Codable, CaseIterable, Identifiable, Sendable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"

    var id: String {
        rawValue
    }
}

struct AuthenticatorToken: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var issuer: String
    var account: String
    var secret: String
    var digits: Int
    var period: Int
    var algorithm: AuthenticatorAlgorithm
    var createdAt: Date

    init(
        id: UUID = UUID(),
        issuer: String,
        account: String,
        secret: String,
        digits: Int = 6,
        period: Int = 30,
        algorithm: AuthenticatorAlgorithm = .sha1,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.issuer = Self.clean(issuer)
        self.account = Self.clean(account)
        self.secret = Self.normalizeSecret(secret)
        self.digits = digits
        self.period = period
        self.algorithm = algorithm
        self.createdAt = createdAt
    }

    var displayName: String {
        if !issuer.isEmpty {
            return issuer
        }
        if !account.isEmpty {
            return account
        }
        return L10n.authenticatorUnknownAccount
    }

    static func normalizeSecret(_ value: String) -> String {
        value
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "-" && $0 != "=" }
    }

    private static func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .controlCharacters)
            .joined()
    }
}

struct AuthenticatorBackup: Codable, Equatable, Sendable {
    static let format = "meow-authenticator"
    static let currentVersion = 1

    let format: String
    let version: Int
    let exportedAt: Date
    let tokens: [AuthenticatorToken]

    init(tokens: [AuthenticatorToken], exportedAt: Date = Date()) {
        format = Self.format
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.tokens = tokens
    }
}

enum AuthenticatorJSONCodec {
    static func encode(tokens: [AuthenticatorToken], exportedAt: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(AuthenticatorBackup(tokens: tokens, exportedAt: exportedAt))
    }

    static func decode(_ data: Data) throws -> [AuthenticatorToken] {
        let object = try JSONSerialization.jsonObject(with: data)
        let rawTokens: [Any]

        if let array = object as? [Any] {
            rawTokens = array
        } else if let dictionary = object as? [String: Any],
                  let array = dictionary["tokens"] as? [Any]
        {
            rawTokens = array
        } else {
            throw AuthenticatorJSONError.invalidRoot
        }

        return try rawTokens.map(decodeToken)
    }

    private static func decodeToken(_ object: Any) throws -> AuthenticatorToken {
        guard let dictionary = object as? [String: Any],
              let rawSecret = dictionary["secret"] as? String
        else {
            throw AuthenticatorJSONError.invalidToken
        }

        let secret = AuthenticatorToken.normalizeSecret(rawSecret)
        let digits = integer(dictionary["digits"]) ?? 6
        let period = integer(dictionary["period"]) ?? 30
        let algorithmName = (dictionary["algorithm"] as? String)?.uppercased() ?? "SHA1"
        guard AuthenticatorCodeGenerator.isValidBase32(secret),
              [6, 8].contains(digits),
              period > 0,
              let algorithm = AuthenticatorAlgorithm(rawValue: algorithmName)
        else {
            throw AuthenticatorJSONError.invalidToken
        }

        let issuer = dictionary["issuer"] as? String ?? ""
        let account = dictionary["account"] as? String ?? ""
        let label = dictionary["label"] as? String ?? ""
        let resolvedIssuer = issuer.isEmpty && account.isEmpty ? label : issuer
        let id = (dictionary["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()

        return AuthenticatorToken(
            id: id,
            issuer: resolvedIssuer,
            account: account,
            secret: secret,
            digits: digits,
            period: period,
            algorithm: algorithm,
            createdAt: date(dictionary["createdAt"]) ?? date(dictionary["updatedAt"]) ?? Date()
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        guard let string = value as? String else { return nil }
        if let date = ISO8601DateFormatter().date(from: string) {
            return date
        }
        return nil
    }
}

enum AuthenticatorJSONError: Error {
    case invalidRoot
    case invalidToken
}

struct OTPAuthURL {
    let issuer: String
    let account: String
    let secret: String
    let digits: Int
    let period: Int
    let algorithm: AuthenticatorAlgorithm

    static func parse(_ value: String) -> OTPAuthURL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "otpauth",
              components.host?.lowercased() == "totp"
        else {
            return nil
        }

        let rawLabel = components.percentEncodedPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .removingPercentEncoding ?? ""
        let labelParts = rawLabel.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        var issuer = labelParts.count > 1 ? String(labelParts[0]) : ""
        let account = labelParts.count > 1 ? String(labelParts[1]) : rawLabel
        var secret = ""
        var digits = 6
        var period = 30
        var algorithm = AuthenticatorAlgorithm.sha1

        for item in components.queryItems ?? [] {
            switch item.name.lowercased() {
            case "secret":
                secret = AuthenticatorToken.normalizeSecret(item.value ?? "")
            case "issuer":
                if let value = item.value, !value.isEmpty {
                    issuer = value
                }
            case "digits":
                digits = Int(item.value ?? "") ?? digits
            case "period":
                period = Int(item.value ?? "") ?? period
            case "algorithm":
                guard let parsedAlgorithm = AuthenticatorAlgorithm(
                    rawValue: (item.value ?? "").uppercased()
                ) else {
                    return nil
                }
                algorithm = parsedAlgorithm
            default:
                break
            }
        }

        guard !secret.isEmpty, [6, 8].contains(digits), period > 0 else {
            return nil
        }

        return OTPAuthURL(
            issuer: issuer,
            account: account,
            secret: secret,
            digits: digits,
            period: period,
            algorithm: algorithm
        )
    }

    func token() -> AuthenticatorToken {
        AuthenticatorToken(
            issuer: issuer,
            account: account,
            secret: secret,
            digits: digits,
            period: period,
            algorithm: algorithm
        )
    }
}
