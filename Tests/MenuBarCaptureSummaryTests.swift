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

    private static func summary(
        _ content: ClipboardContent,
        destination: ExportPreset? = .twitter,
        capturesURLs: Bool = false,
        theme: String = "Aurora",
        bundle: Bundle
    ) -> MenuBarCaptureSummary? {
        MenuBarCaptureSummary.make(
            content: content, themeName: theme, destination: destination,
            capturesURLs: capturesURLs, bundle: bundle)
    }

    private static func line(
        _ content: ClipboardContent,
        destination: ExportPreset? = .twitter,
        capturesURLs: Bool = false,
        bundle: Bundle
    ) -> String? {
        summary(content, destination: destination, capturesURLs: capturesURLs, bundle: bundle)?.line
    }

    private static func facts(
        _ language: Language = .swift, lines: Int = 12, blocks: Int = 0, isURL: Bool = false
    ) -> ClipboardContent {
        .text(
            ClipboardTextFacts(
                language: language, lineCount: lines, blockCount: blocks, isURL: isURL))
    }

    /// The preset's own name and fixed size, so a renamed or resized preset cannot break this.
    private static var twitterLabel: String {
        let size = ExportPreset.twitter.sizing.fixedSize ?? .zero
        return "\(ExportPreset.twitter.displayName) \(Int(size.width)) × \(Int(size.height))"
    }

    // MARK: - Line

    @Test func codeNamesLanguageLinesThemeAndDestination() throws {
        let line = Self.line(Self.facts(), bundle: try Self.bundle("en"))
        #expect(line == "Swift · 12 lines · Aurora · \(Self.twitterLabel)")
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

    @Test func severalBlocksCountBlocksAndDropTheDestination() throws {
        let content = Self.facts(lines: 40, blocks: 3)
        #expect(
            Self.line(content, bundle: try Self.bundle("en")) == "Swift · 3 code blocks · Aurora")
        #expect(
            Self.line(content, bundle: try Self.bundle("es"))
                == "Swift · 3 bloques de código · Aurora")
    }

    @Test func oneFencedBlockStillCountsLinesAndKeepsTheDestination() throws {
        let content = Self.facts(lines: 2, blocks: 1)
        #expect(
            Self.line(content, bundle: try Self.bundle("en"))
                == "Swift · 2 lines · Aurora · \(Self.twitterLabel)")
    }

    @Test func unreadTextShowsThemeAndDestinationOrNothing() throws {
        let bundle = try Self.bundle("en")
        #expect(Self.line(.text(nil), bundle: bundle) == "Aurora · \(Self.twitterLabel)")
        #expect(Self.summary(.text(nil), destination: nil, bundle: bundle) == nil)
    }

    @Test func imageNamesOnlyItself() throws {
        #expect(Self.line(.image, bundle: try Self.bundle("en")) == "Image")
        #expect(Self.line(.image, destination: nil, bundle: try Self.bundle("es")) == "Imagen")
    }

    @Test func emptyClipboardHasNoSummary() throws {
        #expect(Self.summary(.nothing, bundle: try Self.bundle("en")) == nil)
    }

    @Test func urlFollowsTheCaptureGate() throws {
        let url = Self.facts(.plaintext, lines: 1, isURL: true)
        let english = try Self.bundle("en")
        #expect(Self.line(url, capturesURLs: true, bundle: english) == "Web Snapshot")
        #expect(
            Self.line(url, destination: nil, capturesURLs: false, bundle: english)
                == "\(Language.plaintext.displayName) · 1 line · Aurora")
        #expect(Self.line(url, capturesURLs: true, bundle: try Self.bundle("es")) == "Captura web")

        // The system's check also matches code containing a URL, so it never claims a snapshot.
        #expect(Self.summary(.possibleWebURL, capturesURLs: true, bundle: english) == nil)
        #expect(
            Self.line(.possibleWebURL, capturesURLs: false, bundle: english)
                == "Aurora · \(Self.twitterLabel)")
        #expect(
            Self.summary(.possibleWebURL, destination: nil, capturesURLs: false, bundle: english)
                == nil)
    }

    @Test func destinationNeverRepeatsASizeInItsName() {
        let size = ExportPreset.openGraph.sizing.fixedSize ?? .zero
        let pixels = "\(Int(size.width))×\(Int(size.height))"
        #expect(ExportPreset.openGraph.displayName.contains(pixels))
        let label = MenuBarCaptureSummary.destinationLabel(for: .openGraph)
        #expect(!label.contains(pixels))
        #expect(label.hasSuffix("\(Int(size.width)) × \(Int(size.height))"))

        let hugging = ExportPreset(
            id: "hug", displayName: "Hug", summary: "",
            sizing: .aspect(width: 16, height: 9), scale: 2, background: nil, padding: 0)
        #expect(MenuBarCaptureSummary.destinationLabel(for: hugging) == "Hug")
    }

    @Test func accessibilityLabelUsesCommasAndSpokenDimensions() throws {
        let size = ExportPreset.twitter.sizing.fixedSize ?? .zero
        let (width, height) = (Int(size.width).formatted(), Int(size.height).formatted())
        let name = ExportPreset.twitter.displayName
        #expect(
            Self.summary(Self.facts(), bundle: try Self.bundle("en"))?.accessibilityLabel
                == "Swift, 12 lines, Aurora, \(name) \(width) by \(height)")
        #expect(
            Self.summary(.text(nil), bundle: try Self.bundle("es"))?.accessibilityLabel
                == "Aurora, \(name) \(width) por \(height)")
    }

    @Test func fallbackLineDropsOnlyTheTheme() throws {
        let summary = try #require(Self.summary(Self.facts(), bundle: try Self.bundle("en")))
        #expect(summary.lineWithoutTheme == "Swift · 12 lines · \(Self.twitterLabel)")
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
        (NSPasteboard.AccessBehavior.default, ClipboardInspector.Inspection.detectWebURL),
        (.ask, .detectWebURL), (.alwaysDeny, .detectWebURL), (.alwaysAllow, .read),
    ])
    func readingRequiresAlwaysAllow(
        access: NSPasteboard.AccessBehavior, expected: ClipboardInspector.Inspection
    ) {
        let types = [NSPasteboard.PasteboardType.string.rawValue]
        #expect(ClipboardInspector.inspection(access: access, types: types) == expected)
    }

    @Test(arguments: [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "de.petermaurer.TransientPasteboardType", "com.agilebits.onepassword",
        "net.antelle.keeweb", "com.apple.is-remote-clipboard",
    ])
    func markedContentIsNeverInspected(marker: String) {
        let types = [NSPasteboard.PasteboardType.string.rawValue, marker]
        #expect(ClipboardInspector.inspection(access: .alwaysAllow, types: types) == .none)
        #expect(ClipboardInspector.inspection(access: .ask, types: types) == .none)
    }

    // MARK: - Measuring

    /// Runs the real capture without touching the system clipboard.
    @MainActor
    private func capture(_ text: String) -> (QuickCapture.Result, RecentsStore) {
        let settings = AppSettings(defaults: testDefaults())
        settings.outputBehavior.autoCopy = false
        let recents = RecentsStore(defaults: testDefaults())
        let result = QuickCapture.capture(
            settings: settings, recents: recents, clipboard: { text }, urlCaptureEnabled: true)
        return (result, recents)
    }

    @MainActor
    @Test(arguments: [
        "import SwiftUI\nguard let value else { return }\n",
        "Intro\n```go\na\nb\n```\nOutro",
        "plain words\nmore words",
    ])
    func factsMatchWhatACaptureRenders(text: String) throws {
        let (result, recents) = capture(text)
        #expect(result.outcome == .rendered)
        let rendered = try #require(recents.captures.first)
        let facts = try #require(ClipboardInspector.facts(of: text))
        #expect(facts.language == rendered.language)
        #expect(facts.lineCount == LineSplitter.lineCount(of: rendered.code))
    }

    @MainActor
    @Test func factsMatchACaptureDeferredToTheEditor() throws {
        let text = "```go\na\n```\n```go\nb\n```"
        let (result, _) = capture(text)
        let facts = try #require(ClipboardInspector.facts(of: text))
        #expect(result.outcome == .deferredToEditor(blocks: facts.blockCount))
        #expect(result.editorDocument?.language == facts.language)
    }

    @MainActor
    @Test func factsMatchACaptureThatRendersAURLAsText() throws {
        let text = " https://example.com/a.css\n"
        let (_, recents) = capture(text)
        let facts = try #require(ClipboardInspector.facts(of: text))
        #expect(facts.isURL)
        #expect(facts.language == recents.captures.first?.language)
    }

    @Test func blankTextCountsAsEmpty() {
        #expect(ClipboardInspector.facts(of: "") == nil)
        #expect(ClipboardInspector.content(ofUTF8: Data(" \n\t\n".utf8)) == .nothing)
    }

    @Test func textAtTheLimitIsMeasuredAndAboveItIsNot() {
        let limit = ClipboardInspector.maximumMeasuredBytes
        let atLimit = Data(repeating: UInt8(ascii: "x"), count: limit)
        guard case .text(.some) = ClipboardInspector.content(ofUTF8: atLimit) else {
            Issue.record("Text at the limit should be measured")
            return
        }
        let above = Data(repeating: UInt8(ascii: "x"), count: limit + 1)
        #expect(ClipboardInspector.content(ofUTF8: above) == .text(nil))
    }

    @Test func undecodableTextStaysUnmeasured() {
        #expect(ClipboardInspector.content(ofUTF8: Data([0xFF, 0xFE, 0xFF])) == .text(nil))
    }
}

/// Holds reads and detections open, and records each one.
private actor GatedReads {
    private(set) var reads = 0
    private(set) var detections = 0
    private var waiting: [CheckedContinuation<ClipboardContent?, Never>] = []

    func read() async -> ClipboardContent? {
        reads += 1
        return await withCheckedContinuation { waiting.append($0) }
    }

    func detect() -> Bool {
        detections += 1
        return false
    }

    var pendingReads: Int { waiting.count }

    func release(_ content: ClipboardContent?) {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume(returning: content)
    }
}

@MainActor
@Suite("Menu-bar panel clipboard state")
struct MenuBarPanelClipboardTests {
    private static let measured = ClipboardContent.text(
        ClipboardTextFacts(language: .go, lineCount: 7))

    private func pasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("CaptureSummary-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    private func gatedState(on pasteboard: NSPasteboard) -> (MenuBarPanelState, GatedReads) {
        let gate = GatedReads()
        let reader = ClipboardReader(
            read: { _, _ in await gate.read() },
            detectsWebURL: { _, _ in await gate.detect() })
        return (MenuBarPanelState(pasteboard: pasteboard, reader: reader), gate)
    }

    private func waitForPendingRead(_ gate: GatedReads) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while await gate.pendingReads == 0 {
            guard ContinuousClock.now < deadline else {
                Issue.record("No read started")
                return
            }
            await Task.yield()
        }
    }

    @Test func stateMeasuresTextOnlyWhenAllowed() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("func a() {}\n", forType: .string)

        let state = MenuBarPanelState(pasteboard: pasteboard)
        state.refreshClipboard(access: .ask)
        await state.clipboardInspectionFinished()
        #expect(state.clipboard == .text(nil))

        // A later Always Allow takes effect without a new copy.
        state.refreshClipboard(access: .alwaysAllow)
        await state.clipboardInspectionFinished()
        guard case .text(let facts?) = state.clipboard else {
            Issue.record("Expected measured text, got \(state.clipboard)")
            return
        }
        #expect(facts.lineCount == 2)
    }

    @Test func concealedTextIsNotReadEvenWhenAlwaysAllowed() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        #expect(ClipboardWriter.copy("hunter2", concealed: true, to: pasteboard))

        let (state, gate) = gatedState(on: pasteboard)
        state.refreshClipboard(access: .alwaysAllow)
        await state.clipboardInspectionFinished()

        #expect(state.clipboard == .text(nil))
        #expect(await gate.reads == 0)
        #expect(await gate.detections == 0)
    }

    @Test func aReadDiscardsContentThatChangedOrBecameMarked() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("a", forType: .string)
        let count = pasteboard.changeCount

        let stale = await ClipboardInspector.readContent(
            from: pasteboard.name, expecting: count - 1)
        #expect(stale == nil)

        let current = await ClipboardInspector.readContent(from: pasteboard.name, expecting: count)
        #expect(current != nil)

        pasteboard.setData(Data(), forType: ClipboardWriter.concealedType)
        #expect(pasteboard.changeCount == count)
        let marked = await ClipboardInspector.readContent(from: pasteboard.name, expecting: count)
        #expect(marked == nil)
    }

    @Test func stateFollowsTheClipboardThroughEveryKind() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("a\nb", forType: .string)
        let state = MenuBarPanelState(pasteboard: pasteboard)
        state.refreshClipboard(access: .alwaysAllow)
        await state.clipboardInspectionFinished()
        #expect(state.clipboard != .text(nil))

        pasteboard.clearContents()
        pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        state.refreshClipboard(access: .alwaysAllow)
        #expect(state.clipboard == .image)

        pasteboard.clearContents()
        state.refreshClipboard(access: .alwaysAllow)
        #expect(state.clipboard == .nothing)

        // Same change count as the clear: writers add types after clearing.
        pasteboard.setString("  \n", forType: .string)
        state.refreshClipboard(access: .alwaysAllow)
        #expect(state.clipboard == .text(nil))
        await state.clipboardInspectionFinished()
        #expect(state.clipboard == .nothing)
    }

    @Test func aSupersededMeasurementNeverOverwritesNewerContent() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("old", forType: .string)
        let (state, gate) = gatedState(on: pasteboard)
        state.refreshClipboard(access: .alwaysAllow)
        await waitForPendingRead(gate)

        pasteboard.clearContents()
        pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        state.refreshClipboard(access: .alwaysAllow)
        #expect(state.clipboard == .image)

        await gate.release(Self.measured)
        await state.clipboardInspectionFinished()
        #expect(state.clipboard == .image)
        #expect(await gate.reads == 1)
    }

    @Test func onlyOneReadRunsAndTheLatestClipboardIsReadNext() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("first", forType: .string)
        let (state, gate) = gatedState(on: pasteboard)
        state.refreshClipboard(access: .alwaysAllow)
        await waitForPendingRead(gate)

        pasteboard.clearContents()
        pasteboard.setString("second", forType: .string)
        state.refreshClipboard(access: .alwaysAllow)
        await Task.yield()
        #expect(await gate.reads == 1)

        await gate.release(.text(ClipboardTextFacts(language: .swift, lineCount: 1)))
        await waitForPendingRead(gate)
        #expect(await gate.reads == 2)

        await gate.release(Self.measured)
        await state.clipboardInspectionFinished()
        #expect(state.clipboard == Self.measured)
    }

    @Test func previousFactsStayUntilTheNewMeasurementAndNoLongerThanATick() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("first", forType: .string)
        let (state, gate) = gatedState(on: pasteboard)
        state.refreshClipboard(access: .alwaysAllow)
        await waitForPendingRead(gate)
        await gate.release(Self.measured)
        await state.clipboardInspectionFinished()

        pasteboard.clearContents()
        pasteboard.setString("second", forType: .string)
        state.refreshClipboard(access: .alwaysAllow)
        #expect(state.clipboard == Self.measured)

        // The next refresh finds the read still running and drops the old facts.
        await waitForPendingRead(gate)
        state.refreshClipboard(access: .alwaysAllow)
        #expect(state.clipboard == .text(nil))

        await gate.release(Self.measured)
        await state.clipboardInspectionFinished()
        #expect(state.clipboard == Self.measured)
    }

    @Test func anUnchangedClipboardIsNotReadAgain() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("one", forType: .string)
        let (state, gate) = gatedState(on: pasteboard)
        state.refreshClipboard(access: .alwaysAllow)
        await waitForPendingRead(gate)
        await gate.release(Self.measured)
        await state.clipboardInspectionFinished()

        state.refreshClipboard(access: .alwaysAllow)
        await state.clipboardInspectionFinished()
        #expect(state.clipboard == Self.measured)
        #expect(await gate.reads == 1)
    }

    @Test func aPossibleURLIsRememberedWithoutReading() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("https://example.com", forType: .string)
        let reader = ClipboardReader(
            read: { _, _ in
                Issue.record("A possible URL must not be read")
                return nil
            },
            detectsWebURL: { _, _ in true })
        let state = MenuBarPanelState(pasteboard: pasteboard, reader: reader)
        state.refreshClipboard(access: .ask)
        #expect(state.clipboard == .text(nil))
        await state.clipboardInspectionFinished()
        #expect(state.clipboard == .possibleWebURL)
    }

    @Test func detectionRunsOnARealPasteboardAndIgnoresAChangedOne() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("https://example.com/a", forType: .string)
        let count = pasteboard.changeCount
        #expect(await ClipboardInspector.detectsWebURL(on: pasteboard.name, expecting: count))
        #expect(
            !(await ClipboardInspector.detectsWebURL(on: pasteboard.name, expecting: count - 1)))

        pasteboard.clearContents()
        pasteboard.setString("let answer = 42\nprint(answer)", forType: .string)
        #expect(
            !(await ClipboardInspector.detectsWebURL(
                on: pasteboard.name, expecting: pasteboard.changeCount)))
    }

    @Test func theWatcherFollowsTheClipboardOnlyWhileStarted() async throws {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        let state = MenuBarPanelState(pasteboard: pasteboard, watchInterval: .milliseconds(5))
        state.refreshClipboard()
        #expect(state.clipboard == .nothing)

        state.startWatchingClipboard()
        pasteboard.clearContents()
        pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        let deadline = ContinuousClock.now + .seconds(5)
        while state.clipboard != .image, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(state.clipboard == .image)

        state.stopWatchingClipboard()
        pasteboard.clearContents()
        try await Task.sleep(for: .milliseconds(50))
        #expect(state.clipboard == .image)
    }
}
