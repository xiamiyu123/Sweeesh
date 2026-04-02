import Testing
@testable import Swooshy

struct DockItemApplicationMatcherTests {
    @Test
    func exactWindowTitleBeatsPartialAliasMatch() {
        let score = DockItemApplicationMatcher.matchScore(
            forNormalizedDockName: "xiamimrslearnsomethingswooshy",
            normalizedAliases: ["swooshy"],
            normalizedMinimizedWindowTitles: ["xiamimrslearnsomethingswooshy"]
        )

        #expect(score == 3)
    }

    @Test
    func exactAliasBeatsWindowTitleFallback() {
        let score = DockItemApplicationMatcher.matchScore(
            forNormalizedDockName: "ghostty",
            normalizedAliases: ["ghostty", "commitchellhghostty"],
            normalizedMinimizedWindowTitles: ["ghosttyproject"]
        )

        #expect(score == 4)
    }

    @Test
    func unrelatedDockItemDoesNotMatch() {
        let score = DockItemApplicationMatcher.matchScore(
            forNormalizedDockName: "xiamimrslearnsomethingghostty",
            normalizedAliases: ["swooshy"],
            normalizedMinimizedWindowTitles: ["preview"]
        )

        #expect(score == 0)
    }

    @Test
    func partialAliasDoesNotMatchWindowTitleLikeDockItem() {
        let score = DockItemApplicationMatcher.matchScore(
            forNormalizedDockName: "signintocodex",
            normalizedAliases: ["codex", "comopenaicodex"],
            normalizedMinimizedWindowTitles: []
        )

        #expect(score == 0)
    }

    @Test
    func minimizedWindowTitlePrefixMatchesRecentWindowDockItem() {
        let score = DockItemApplicationMatcher.matchScore(
            forNormalizedDockName: "signintocodex",
            normalizedAliases: ["chrome", "googlechrome", "comgooglechrome"],
            normalizedMinimizedWindowTitles: ["signintocodexgooglechrome"]
        )

        #expect(score == 2)
    }
}
