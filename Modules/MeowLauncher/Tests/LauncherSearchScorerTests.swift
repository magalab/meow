import MeowLauncher
import Testing

struct LauncherSearchScorerTests {
    @Test
    func scoresExactPrefixWordAndSubstringMatches() {
        #expect(LauncherSearchScorer.score(text: "settings", query: "settings") == 120)
        #expect(LauncherSearchScorer.score(text: "settings window", query: "settings") == 90)
        #expect(LauncherSearchScorer.score(text: "open settings", query: "settings") == 70)
        #expect(LauncherSearchScorer.score(text: "systemsettings", query: "settings") == 50)
    }

    @Test
    func onlyScoresCandidateTextThatContainsTheQuery() {
        #expect(LauncherSearchScorer.scoreIfMatching(text: "settings", query: "settings") == 120)
        #expect(LauncherSearchScorer.scoreIfMatching(text: "open settings", query: "settings") == 70)
        #expect(LauncherSearchScorer.scoreIfMatching(text: "system", query: "settings") == nil)
    }

    @Test
    func ranksByScoreThenPrimaryTextAndAppliesTheResultLimit() {
        let matches = [
            LauncherSearchMatch(
                item: .command(CommandEntry(id: "zulu", title: "Zulu", subtitle: "", keywords: [])),
                score: 80
            ),
            LauncherSearchMatch(
                item: .command(CommandEntry(id: "high", title: "High score", subtitle: "", keywords: [])),
                score: 100
            ),
            LauncherSearchMatch(
                item: .command(CommandEntry(id: "alpha", title: "Alpha", subtitle: "", keywords: [])),
                score: 80
            ),
        ]

        let ranked = LauncherSearchResultRanker.rank(matches: matches, limit: 2)
        #expect(ranked.map(\.primaryText) == ["High score", "Alpha"])
        #expect(LauncherSearchResultRanker.rank(matches: matches, limit: 0).isEmpty)
    }
}
