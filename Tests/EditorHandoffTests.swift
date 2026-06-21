import AppKit
import Testing

@testable import Vitrine

/// The CLI → editor handoff contract (`vitrine render … --edit`): the CLI stages the
/// captured text on a private pasteboard and opens a `vitrine://edit` URL; the app reads
/// it back. These tests exercise both halves against the real named pasteboard (a custom
/// name, so they never touch the user's general clipboard).
@MainActor
@Suite("Editor handoff (--edit)")
struct EditorHandoffTests {
    private let esc = "\u{1B}"

    @Test func stageAndConsumeRoundTrip() {
        let content = "\(esc)[31mmodified:\(esc)[0m file.swift"
        let url = EditorHandoff.stage(content: content, language: .terminal)
        #expect(url.scheme == "vitrine" && url.host == "edit")

        let consumed = EditorHandoff.consume(url: url)
        #expect(consumed?.content == content)
        #expect(consumed?.language == .terminal)
    }

    @Test func consumeIsOneShot() {
        let url = EditorHandoff.stage(content: "x", language: .terminal)
        #expect(EditorHandoff.consume(url: url) != nil)
        // The staged payload is cleared on read, so a second open finds nothing and
        // can never re-seed the editor with stale content.
        #expect(EditorHandoff.consume(url: url) == nil)
    }

    @Test func stageWithoutLanguageOmitsTheQuery() {
        let url = EditorHandoff.stage(content: "plain output", language: nil)
        #expect(url.query == nil)
        #expect(EditorHandoff.consume(url: url)?.language == nil)
    }

    @Test func consumeRejectsAForeignURL() {
        // Stage something so the pasteboard is non-empty, then prove a non-handoff URL
        // is ignored (scheme/host mismatch), not blindly read from the pasteboard.
        _ = EditorHandoff.stage(content: "x", language: .terminal)
        #expect(EditorHandoff.consume(url: URL(string: "https://example.com")!) == nil)
        #expect(EditorHandoff.consume(url: URL(string: "vitrine://settings")!) == nil)
    }
}
