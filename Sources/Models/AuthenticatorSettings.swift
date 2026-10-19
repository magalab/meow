import Foundation

struct AuthenticatorSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var iCloudSyncEnabled: Bool

    static let `default` = AuthenticatorSettings(
        enabled: false,
        iCloudSyncEnabled: false
    )
}
