import Testing

@testable import Vitrine

/// The command palette's pure ranking behavior, pinned without opening a window.
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

    @Test func matchingIsDiacriticInsensitive() {
        let catalog = [command("capture", "Captúra rápida")]
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "captura")) == ["capture"])
    }

    @Test func matchingIsWidthInsensitive() {
        let catalog = [command("capture", "Capture")]
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "Ｃａｐｔｕｒｅ")) == ["capture"])
    }

    @Test func everyTermCanMatchADifferentTargetInAnyOrder() {
        let catalog = [
            command("dark", "One Dark", group: "Theme", keywords: ["syntax"]),
            command("save", "Save image", group: "Export", keywords: ["png"]),
        ]
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "theme dark")) == ["dark"])
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "dark theme")) == ["dark"])
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "export png")) == ["save"])
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "theme png")).isEmpty)
    }

    @Test func prefixBeatsWordStartBeatsSubstringBeatsSubsequence() {
        let catalog = [
            command("subsequence", "Arrange code"),
            command("substring", "Marchive"),
            command("word-start", "Open archive"),
            command("prefix", "Archive"),
        ]
        #expect(
            ids(CommandPaletteFilter.rank(catalog, query: "arc")) == [
                "prefix", "word-start", "substring", "subsequence",
            ])
    }

    @Test func hyphensRemainWordBoundariesButOtherPunctuationDoesNot() {
        let catalog = [
            command("slash", "Open/archive"),
            command("hyphen", "Open-archive"),
        ]
        #expect(ids(CommandPaletteFilter.rank(catalog, query: "archive")) == ["hyphen", "slash"])
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
