import Foundation

enum ClipboardRetention: Int, Codable, CaseIterable, Identifiable, Sendable {
    case day = 1
    case week = 7
    case month = 30
    case threeMonths = 90
    case sixMonths = 180
    case year = 365
    case forever = -1

    var id: Int { rawValue }

    var cutoffDate: Date? {
        guard self != .forever else { return nil }
        return Date().addingTimeInterval(-TimeInterval(rawValue) * 86_400)
    }
}

struct ClipboardSettings: Codable, Equatable, Sendable {
    var historyEnabled: Bool
    var showImagePreviews: Bool
    var retention: ClipboardRetention
    var disabledAppBundleIDs: [String]
    var imageStorageLimitMB: Int

    static let `default` = ClipboardSettings(
        historyEnabled: true,
        showImagePreviews: true,
        retention: .threeMonths,
        disabledAppBundleIDs: ["com.apple.keychainaccess", "com.apple.Passwords"],
        imageStorageLimitMB: 512
    )

    init(
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
