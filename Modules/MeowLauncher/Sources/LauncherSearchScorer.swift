import Foundation

/// A launcher item paired with the score assigned by the app's feature rules.
public struct LauncherSearchMatch: Hashable {
    public let item: SearchItem
    public let score: Int

    public init(item: SearchItem, score: Int) {
        self.item = item
        self.score = score
    }
}

/// Applies the launcher's stable text-match ranking tiers and result ordering.
public enum LauncherSearchScorer {
    /// Returns the base score when the candidate text contains the query.
    public static func scoreIfMatching(text: String, query: String) -> Int? {
        guard text.contains(query) else { return nil }
        return score(text: text, query: query)
    }

    public static func score(text: String, query: String) -> Int {
        if text == query { return 120 }
        if text.hasPrefix(query) { return 90 }
        if text.contains(" \(query)") { return 70 }
        return 50
    }
}

public enum LauncherSearchResultRanker {
    public static func rank(matches: [LauncherSearchMatch], limit: Int) -> [SearchItem] {
        guard limit > 0 else { return [] }

        return matches
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.item.primaryText.localizedCaseInsensitiveCompare(rhs.item.primaryText)
                    == .orderedAscending
            }
            .prefix(limit)
            .map(\.item)
    }
}
