/// Applies the launcher's stable text-match ranking tiers.
public enum LauncherSearchScorer {
    public static func score(text: String, query: String) -> Int {
        if text == query { return 120 }
        if text.hasPrefix(query) { return 90 }
        if text.contains(" \(query)") { return 70 }
        return 50
    }
}
