import Foundation

public enum ClipboardRetention: Int, Codable, CaseIterable, Identifiable, Sendable {
    case day = 1
    case week = 7
    case month = 30
    case threeMonths = 90
    case sixMonths = 180
    case year = 365
    case forever = -1

    public var id: Int { rawValue }

    public var cutoffDate: Date? {
        guard self != .forever else { return nil }
        return Date().addingTimeInterval(-TimeInterval(rawValue) * 86_400)
    }
}

public struct ClipboardSettings: Codable, Equatable, Sendable {
    public var historyEnabled: Bool
    public var showImagePreviews: Bool
    public var retention: ClipboardRetention
    public var disabledAppBundleIDs: [String]
    public var imageStorageLimitMB: Int

    public static let `default` = ClipboardSettings(
        historyEnabled: true,
        showImagePreviews: true,
        retention: .threeMonths,
        disabledAppBundleIDs: ["com.apple.keychainaccess", "com.apple.Passwords"],
        imageStorageLimitMB: 512
    )

    public init(
        historyEnabled: Bool,
        showImagePreviews: Bool,
        retention: ClipboardRetention,
        disabledAppBundleIDs: [String],
        imageStorageLimitMB: Int
    ) {
        self.historyEnabled = historyEnabled
        self.showImagePreviews = showImagePreviews
        self.retention = retention
        self.disabledAppBundleIDs = disabledAppBundleIDs
        self.imageStorageLimitMB = max(128, imageStorageLimitMB)
    }
}
