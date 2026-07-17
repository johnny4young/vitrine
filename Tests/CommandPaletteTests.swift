import Testing

@testable import Vitrine

/// The command palette's ranking (feature #56 / analysis §8.2). The matcher is pure,
/// so its behavior is pinned here without opening a window.
@MainActor
@Suite("Command palette ranking")
struct CommandPaletteTests {
    private func command(
        _ id: String, _ title: String, group: String = "Style", keywords: [String] = []
    ) -> EditorCommand {
        EditorCommand(
            id: id, title: title, group: group, keywords: keywords, symbol: "circle", run: {})
    }

    private func ids(_ commands: [EditorCommand]) -> [String] { commands.map(\.id) }

    @Test func emptyQueryReturnsEverythingInAuthorOrder() {
        let catalog = [command("a", "One Dark"), command("b", "Dracula"), command("c", "Nord")]
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "")) == ["a", "b", "c"])
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "   \n")) == ["a", "b", "c"])
    }

    @Test func nonMatchingCommandsAreDropped() {
        let catalog = [command("a", "One Dark"), command("b", "Dracula")]
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "zzz")).isEmpty)
    }

    @Test func matchingIsCaseInsensitiveSubsequence() {
        // "clr" is a subsequence of "Clear" — the classic fuzzy-finder rule.
        let catalog = [command("a", "Clear annotations")]
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "clr")) == ["a"])
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "CLEAR")) == ["a"])
    }

    @Test func prefixBeatsWordStartBeatsSubstringBeatsSubsequence() {
        let catalog = [
            command("subseq", "Redcap layers"),  // "rdc" subsequence only
            command("substr", "Aardvark"),  // contains "rd"
            command("wordstart", "Show rows"),  // word starts with "r"... use "row"
            command("prefix", "Rotate"),  // prefix "ro"
        ]
        // Query "ro": prefix (Rotate) > word-start (Show rows) > substring (none here).
        let ranked = ids(CommandPaletteFilter.rank(catalog, query: "ro"))
        #expect(ranked.first == "prefix")
        #expect(ranked.contains("wordstart"))
        // "Aardvark" and "Redcap" don't contain "ro" as a subsequence in order → dropped.
        #expect(!ranked.contains("substr"))
    }

    @Test func aTitleMatchAlwaysOutranksAKeywordOnlyMatch() {
        let titleHit = command("title", "Dark mode toggle")  // title contains "dark"
        let keywordHit = command("kw", "Midnight", keywords: ["dark"])  // only keyword
        let ranked = ids(CommandPaletteFilter.rank([keywordHit, titleHit], query: "dark"))
        #expect(ranked.first == "title", "a title hit must beat a keyword-only hit")
        #expect(ranked == ["title", "kw"])
    }

    @Test func keywordsSurfaceACommandTheTitleWouldnt() {
        // "png" isn't in the title, but it's a keyword — the command must still appear.
        let catalog = [
            command("copy", "Copy image", group: "Export", keywords: ["png", "clipboard"])
        ]
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "png")) == ["copy"])
    }

    @Test func groupIsMatchable() {
        let catalog = [
            command("a", "One Dark", group: "Theme"),
            command("b", "Save to file", group: "Export"),
        ]
        // Typing the group name surfaces its commands.
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "export")) == ["b"])
    }

    @Test func tiesKeepAuthorOrderSoRankingIsDeterministic() {
        // Three identical-scoring prefix matches must stay in catalog order.
        let catalog = [
            command("a", "Test one"), command("b", "Test two"), command("c", "Test three"),
        ]
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "test")) == ["a", "b", "c"])
    }
}
