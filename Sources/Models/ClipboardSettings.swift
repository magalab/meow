import Foundation

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
