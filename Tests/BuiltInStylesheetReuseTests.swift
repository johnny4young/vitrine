import Highlightr
import Testing
import VitrineDomain

@testable import VitrineRendering

@Suite("Built-in stylesheet reuse")
struct BuiltInStylesheetReuseTests {
    /// Highlightr merges rules in an order that changes between stylesheet parses, so a class
    /// two rules style (One Dark's `.hljs-meta`) could change color mid-session.
    @Test func returningToAThemeReusesItsParsedStylesheet() throws {
        let manager = HighlightManager.shared
        #expect(manager.selectBuiltInTheme(VitrineDomain.Theme.oneDark))
        let parsed = try #require(manager.highlightr?.theme)
        #expect(manager.selectBuiltInTheme(VitrineDomain.Theme.github))
        #expect(manager.selectBuiltInTheme(VitrineDomain.Theme.oneDark))
        #expect(manager.highlightr?.theme === parsed)
    }
}
