import AppKit
import Foundation
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@Suite("Menu-bar capture summary")
struct MenuBarCaptureSummaryTests {
    private static func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private static func line(
        _ content: ClipboardContent,
        destination: ExportPreset? = .twitter,
        capturesURLs: Bool = false,
        bundle: Bundle
    ) -> String? {
        MenuBarCaptureSummary.line(
            content: content, themeName: "Aurora", destination: destination,
            capturesURLs: capturesURLs, bundle: bundle)
    }

    private static func facts(
        _ language: Language? = .swift, lines: Int = 12, blocks: Int = 0, isURL: Bool = false
    ) -> ClipboardContent {
        .text(
            ClipboardTextFacts(
                language: language, lineCount: lines, blockCount: blocks, isURL: isURL))
    }

    // MARK: - Line

    @Test func codeNamesLanguageLinesThemeAndDestination() throws {
        let line = Self.line(Self.facts(), bundle: try Self.bundle("en"))
        #expect(line == "Swift · 12 lines · Aurora · X / Twitter 1600 × 900")
    }

    @Test func linesPluralizeInEnglishAndSpanish() throws {
        let english = try Self.bundle("en")
        let spanish = try Self.bundle("es")
        let one = Self.facts(lines: 1)
        let many = Self.facts(lines: 3)
        #expect(Self.line(one, destination: nil, bundle: english) == "Swift · 1 line · Aurora")
        #expect(Self.line(many, destination: nil, bundle: english) == "Swift · 3 lines · Aurora")
        #expect(Self.line(one, destination: nil, bundle: spanish) == "Swift · 1 línea · Aurora")
        #expect(Self.line(many, destination: nil, bundle: spanish) == "Swift · 3 líneas · Aurora")
    }

    @Test func severalBlocksCountBlocksInsteadOfLines() throws {
        let content = Self.facts(lines: 40, blocks: 3)
        #expect(
            Self.line(content, destination: nil, bundle: try Self.bundle("en"))
                == "Swift · 3 code blocks · Aurora")
        #expect(
            Self.line(content, destination: nil, bundle: try Self.bundle("es"))
                == "Swift · 3 bloques de código · Aurora")
    }

    @Test func oneFencedBlockStillCountsLines() throws {
        let content = Self.facts(lines: 2, blocks: 1)
        #expect(
            Self.line(content, destination: nil, bundle: try Self.bundle("en"))
                == "Swift · 2 lines · Aurora")
    }

    @Test func unreadableTextShowsOnlyThemeAndDestination() throws {
        let bundle = try Self.bundle("en")
        #expect(Self.line(.text(nil), bundle: bundle) == "Aurora · X / Twitter 1600 × 900")
        #expect(Self.line(.text(nil), destination: nil, bundle: bundle) == "Aurora")
    }

    @Test func oversizedTextOmitsTheLanguage() throws {
        let content = Self.facts(nil, lines: 90_000)
        #expect(
            Self.line(content, destination: nil, bundle: try Self.bundle("en"))
                == "\(90_000.formatted()) lines · Aurora")
    }

    @Test func imageSkipsTheThemeItDoesNotUse() throws {
        #expect(
            Self.line(.image, bundle: try Self.bundle("en")) == "Image · X / Twitter 1600 × 900")
        #expect(
            Self.line(.image, destination: nil, bundle: try Self.bundle("es")) == "Imagen")
    }

    @Test func emptyClipboardHasNoLine() throws {
        #expect(Self.line(.nothing, bundle: try Self.bundle("en")) == nil)
    }

    @Test func urlFollowsTheCaptureSetting() throws {
        let url = Self.facts(.plaintext, lines: 1, isURL: true)
        let bundle = try Self.bundle("en")
        #expect(Self.line(url, capturesURLs: true, bundle: bundle) == "Web Snapshot")
        #expect(
            Self.line(url, destination: nil, capturesURLs: false, bundle: bundle)
                == "\(Language.plaintext.displayName) · 1 line · Aurora")
        #expect(
            Self.line(url, capturesURLs: true, bundle: try Self.bundle("es")) == "Captura web")
    }

    @Test func destinationNeverRepeatsASizeInItsName() {
        #expect(
            MenuBarCaptureSummary.destinationLabel(for: .openGraph) == "OpenGraph 1200 × 630")
        let hugging = ExportPreset(
            id: "hug", displayName: "Hug", summary: "",
            sizing: .aspect(width: 16, height: 9), scale: 2, background: nil, padding: 0)
        #expect(MenuBarCaptureSummary.destinationLabel(for: hugging) == "Hug")
    }

    // MARK: - What may be known

    @Test func typesAloneClassifyTheClipboard() {
        let string = NSPasteboard.PasteboardType.string.rawValue
        let png = NSPasteboard.PasteboardType.png.rawValue
        #expect(ClipboardInspector.content(types: []) == .nothing)
        #expect(ClipboardInspector.content(types: ["com.example.private"]) == .nothing)
        #expect(ClipboardInspector.content(types: [string]) == .text(nil))
        #expect(ClipboardInspector.content(types: [string, png]) == .image)
    }

    @Test(arguments: [
        (NSPasteboard.AccessBehavior.default, false), (.ask, false), (.alwaysDeny, false),
        (.alwaysAllow, true),
    ])
    func readingRequiresAlwaysAllow(access: NSPasteboard.AccessBehavior, expected: Bool) {
        let types = [NSPasteboard.PasteboardType.string.rawValue]
        #expect(ClipboardInspector.mayReadContents(access: access, types: types) == expected)
    }

    @Test(arguments: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"])
    func privateContentIsNeverRead(marker: String) {
        let types = [NSPasteboard.PasteboardType.string.rawValue, marker]
        #expect(!ClipboardInspector.mayReadContents(access: .alwaysAllow, types: types))
    }

    // MARK: - Measuring

    @Test func factsMatchWhatACaptureWouldRender() throws {
        let swift = try #require(
            ClipboardInspector.facts(of: "import SwiftUI\nguard let value else { return }\n"))
        #expect(swift.language == .swift)
        #expect(swift.lineCount == 3)
        #expect(!swift.isURL)

        let fenced = try #require(ClipboardInspector.facts(of: "Intro\n```go\na\nb\n```\nOutro"))
        #expect(fenced.language == .go)
        #expect(fenced.lineCount == 2)
        #expect(fenced.blockCount == 1)

        let blocks = try #require(ClipboardInspector.facts(of: "```go\na\n```\n```go\nb\n```"))
        #expect(blocks.blockCount == 2)

        let url = try #require(ClipboardInspector.facts(of: " https://example.com/a.css\n"))
        #expect(url.isURL)
        #expect(url.language == .plaintext)
    }

    @Test func blankTextCountsAsEmpty() {
        #expect(ClipboardInspector.facts(of: "") == nil)
        #expect(ClipboardInspector.facts(of: " \n\t\n") == nil)
    }

    @Test func oversizedTextIsCountedButNotScored() throws {
        let line = String(repeating: "x", count: 99) + "\n"
        let lines = ClipboardInspector.maximumScoredBytes / line.utf8.count + 1
        let facts = try #require(
            ClipboardInspector.facts(of: String(repeating: line, count: lines)))
        #expect(facts.language == nil)
        #expect(facts.lineCount == lines + 1)
    }

    // MARK: - Panel state

    @MainActor
    private func withPasteboard(_ body: (NSPasteboard) async throws -> Void) async rethrows {
        let pasteboard = NSPasteboard(name: .init("CaptureSummary-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try await body(pasteboard)
    }

    @MainActor
    @Test func stateMeasuresTextOnlyWhenAllowed() async {
        await withPasteboard { pasteboard in
            pasteboard.clearContents()
            pasteboard.setString("func a() {}\n", forType: .string)

            let state = MenuBarPanelState()
            state.refreshClipboard(pasteboard: pasteboard, access: .ask)
            await state.clipboardInspectionFinished()
            #expect(state.clipboard == .text(nil))

            // A later Always Allow takes effect without a new copy.
            state.refreshClipboard(pasteboard: pasteboard, access: .alwaysAllow)
            await state.clipboardInspectionFinished()
            guard case .text(let facts?) = state.clipboard else {
                Issue.record("Expected measured text, got \(state.clipboard)")
                return
            }
            #expect(facts.lineCount == 2)
        }
    }

    @MainActor
    @Test func stateDropsStaleFactsWhenTheClipboardChanges() async {
        await withPasteboard { pasteboard in
            pasteboard.clearContents()
            pasteboard.setString("a\nb", forType: .string)
            let state = MenuBarPanelState()
            state.refreshClipboard(pasteboard: pasteboard, access: .alwaysAllow)
            await state.clipboardInspectionFinished()
            #expect(state.clipboard != .text(nil))

            pasteboard.clearContents()
            pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
            state.refreshClipboard(pasteboard: pasteboard, access: .alwaysAllow)
            #expect(state.clipboard == .image)

            pasteboard.clearContents()
            state.refreshClipboard(pasteboard: pasteboard, access: .alwaysAllow)
            #expect(state.clipboard == .nothing)

            pasteboard.setString("  \n", forType: .string)
            state.refreshClipboard(pasteboard: pasteboard, access: .alwaysAllow)
            #expect(state.clipboard == .text(nil))
            await state.clipboardInspectionFinished()
            #expect(state.clipboard == .nothing)
        }
    }

    @MainActor
    @Test func aSupersededMeasurementNeverOverwritesNewerContent() async {
        await withPasteboard { pasteboard in
            pasteboard.clearContents()
            pasteboard.setString("old", forType: .string)
            let state = MenuBarPanelState()
            state.refreshClipboard(pasteboard: pasteboard, access: .alwaysAllow)

            pasteboard.clearContents()
            pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
            state.refreshClipboard(pasteboard: pasteboard, access: .alwaysAllow)
            await Task.yield()
            await state.clipboardInspectionFinished()
            #expect(state.clipboard == .image)
        }
    }

    @MainActor
    @Test func anUnchangedClipboardIsNotReadAgain() async {
        await withPasteboard { pasteboard in
            pasteboard.clearContents()
            pasteboard.setString("one", forType: .string)
            let state = MenuBarPanelState()
            state.refreshClipboard(pasteboard: pasteboard, access: .alwaysAllow)
            await state.clipboardInspectionFinished()
            let measured = state.clipboard

            state.refreshClipboard(pasteboard: pasteboard, access: .alwaysAllow)
            // A re-read would first fall back to the unmeasured state.
            #expect(state.clipboard == measured)
        }
    }
}
