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
}
