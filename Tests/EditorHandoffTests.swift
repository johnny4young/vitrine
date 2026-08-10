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

    @Test func stageAndConsumeRoundTrip() throws {
        let content = "\(esc)[31mmodified:\(esc)[0m file.swift"
        let url = try #require(EditorHandoff.stage(content: content, language: .terminal))
        #expect(url.scheme == "vitrine" && url.host == "edit")

        let consumed = EditorHandoff.consume(url: url)
        #expect(consumed?.content == content)
        #expect(consumed?.language == .terminal)
    }

    @Test func consumeIsOneShot() throws {
        let url = try #require(EditorHandoff.stage(content: "x", language: .terminal))
        #expect(EditorHandoff.consume(url: url) != nil)
        // The staged payload is cleared on read, so a second open finds nothing and
        // can never re-seed the editor with stale content.
        #expect(EditorHandoff.consume(url: url) == nil)
    }

    @Test func stageWithoutLanguageStillCarriesTheToken() throws {
        let url = try #require(EditorHandoff.stage(content: "plain output", language: nil))
        // The token always rides in the query (it names the pasteboard); the language
        // does not when none was supplied.
        let query = url.query ?? ""
        #expect(query.contains("token="))
        #expect(!query.contains("language="))
        #expect(EditorHandoff.consume(url: url)?.language == nil)
    }

    @Test func consumeRejectsAForeignURL() throws {
        // Stage something so a pasteboard is non-empty, then prove a non-handoff URL is
        // ignored (scheme/host mismatch), not blindly read from any pasteboard.
        let staged = try #require(EditorHandoff.stage(content: "x", language: .terminal))
        defer { _ = EditorHandoff.consume(url: staged) }
        let website = try #require(URL(string: "https://example.com"))
        let settings = try #require(URL(string: "vitrine://settings"))
        #expect(EditorHandoff.consume(url: website) == nil)
        #expect(EditorHandoff.consume(url: settings) == nil)
    }

    @Test func consumeRejectsAMissingOrMalformedToken() throws {
        let staged = try #require(EditorHandoff.stage(content: "x", language: .terminal))
        defer { _ = EditorHandoff.consume(url: staged) }
        // No token, and a non-UUID token, are both rejected before any pasteboard read —
        // the token can't be steered to an arbitrary pasteboard name.
        let missingToken = try #require(URL(string: "vitrine://edit"))
        let malformedToken = try #require(
            URL(string: "vitrine://edit?token=not%2Fa%2Fuuid"))
        #expect(EditorHandoff.consume(url: missingToken) == nil)
        #expect(EditorHandoff.consume(url: malformedToken) == nil)
    }

    @Test func eachHandoffIsolatesItsPayload() throws {
        // Two stages produce different tokens / pasteboards, so each URL consumes only
        // its own payload — a later open can't pick up an earlier handoff's content.
        let first = try #require(EditorHandoff.stage(content: "first", language: .terminal))
        let second = try #require(EditorHandoff.stage(content: "second", language: .terminal))
        #expect(first.query != second.query)
        #expect(EditorHandoff.consume(url: second)?.content == "second")
        #expect(EditorHandoff.consume(url: first)?.content == "first")
    }
}
