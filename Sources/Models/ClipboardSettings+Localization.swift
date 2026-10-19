extension ClipboardRetention {
    var displayName: String {
        switch self {
        case .day: L10n.clipboardRetentionDay
        case .week: L10n.clipboardRetentionWeek
        case .month: L10n.clipboardRetentionMonth
        case .threeMonths: L10n.clipboardRetentionThreeMonths
        case .sixMonths: L10n.clipboardRetentionSixMonths
        case .year: L10n.clipboardRetentionYear
        case .forever: L10n.clipboardRetentionForever
        }
    }
}
