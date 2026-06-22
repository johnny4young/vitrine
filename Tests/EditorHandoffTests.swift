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

    @Test func stageWithoutLanguageStillCarriesTheToken() {
        let url = EditorHandoff.stage(content: "plain output", language: nil)
        // The token always rides in the query (it names the pasteboard); the language
        // does not when none was supplied.
        let query = url.query ?? ""
        #expect(query.contains("token="))
        #expect(!query.contains("language="))
        #expect(EditorHandoff.consume(url: url)?.language == nil)
    }

    @Test func consumeRejectsAForeignURL() {
        // Stage something so a pasteboard is non-empty, then prove a non-handoff URL is
        // ignored (scheme/host mismatch), not blindly read from any pasteboard.
        _ = EditorHandoff.stage(content: "x", language: .terminal)
        #expect(EditorHandoff.consume(url: URL(string: "https://example.com")!) == nil)
        #expect(EditorHandoff.consume(url: URL(string: "vitrine://settings")!) == nil)
    }

    @Test func consumeRejectsAMissingOrMalformedToken() {
        _ = EditorHandoff.stage(content: "x", language: .terminal)
        // No token, and a non-UUID token, are both rejected before any pasteboard read —
        // the token can't be steered to an arbitrary pasteboard name.
        #expect(EditorHandoff.consume(url: URL(string: "vitrine://edit")!) == nil)
        #expect(
            EditorHandoff.consume(url: URL(string: "vitrine://edit?token=not%2Fa%2Fuuid")!) == nil)
    }

    @Test func eachHandoffIsolatesItsPayload() {
        // Two stages produce different tokens / pasteboards, so each URL consumes only
        // its own payload — a later open can't pick up an earlier handoff's content.
        let first = EditorHandoff.stage(content: "first", language: .terminal)
        let second = EditorHandoff.stage(content: "second", language: .terminal)
        #expect(first.query != second.query)
        #expect(EditorHandoff.consume(url: second)?.content == "second")
        #expect(EditorHandoff.consume(url: first)?.content == "first")
    }
}
