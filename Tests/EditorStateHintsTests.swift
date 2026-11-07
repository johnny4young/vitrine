import AppKit
import SwiftUI
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

/// Counts contents reads and can hold them open, so a test can prove what was never read.
private actor ReadLog {
    private(set) var reads = 0
    private var held: CheckedContinuation<Void, Never>?
    private let holdsReads: Bool

    init(holdsReads: Bool = false) { self.holdsReads = holdsReads }

    func read() async -> ClipboardContent? {
        reads += 1
        if holdsReads { await withCheckedContinuation { held = $0 } }
        return .text(ClipboardTextFacts(language: .swift, lineCount: 14))
    }

    func release() {
        held?.resume()
        held = nil
    }

    private(set) var detections = 0

    func detect() { detections += 1 }
}

@Suite("Editor state hints")
@MainActor
struct EditorStateHintsTests {
    private func pasteboard(holding text: String? = "let a = 1\n") -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("StateHints-\(UUID().uuidString)"))
        pasteboard.clearContents()
        if let text { pasteboard.setString(text, forType: .string) }
        return pasteboard
    }

    private func monitor(on pasteboard: NSPasteboard, log: ReadLog) -> ClipboardMonitor {
        ClipboardMonitor(
            pasteboard: pasteboard,
            reader: ClipboardReader(
                read: { _, _ in await log.read() }, detectsWebURL: { _, _ in false }))
    }

    private func waitForReads(_ count: Int, _ log: ReadLog) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while await log.reads < count, ContinuousClock.now < deadline { await Task.yield() }
    }

    // MARK: - What the empty stage may say

    @Test func onlyMeasuredTextIsNamed() {
        for unmeasured: ClipboardContent in [.nothing, .image, .possibleWebURL, .text(nil)] {
            #expect(unmeasured.measuredDescription() == nil)
        }
    }

    private func localization(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    /// Text whose line count a re-indenting paste changes, in each way the formatter can.
    nonisolated static let reformattedSnippets = [
        "\n\n\nfunc a() {}\n\n\n",
        #"{"name":"vitrine","tags":["a","b"],"nested":{"on":true}}"#,
        "SELECT a, b FROM t WHERE a = 1 ORDER BY b",
        "<html><body><p>hi</p></body></html>",
    ]

    private func measuredLineCount(
        of text: String, reindents: Bool
    ) async throws -> Int {
        let pasteboard = pasteboard(holding: text)
        defer { pasteboard.releaseGlobally() }
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard, reader: .editorPaste(reindents: reindents))
        monitor.refresh(access: .alwaysAllow)
        await monitor.inspectionFinished()
        guard case .text(let facts?) = monitor.clipboard else {
            Issue.record("Expected measured text, got \(monitor.clipboard)")
            return -1
        }
        return facts.lineCount
    }

    /// The claim against both real paste routes: the Paste Code button and a native ⌘V.
    @Test(arguments: Self.reformattedSnippets, [true, false])
    func theClaimCountsWhatAPasteProduces(text: String, reindents: Bool) async throws {
        let intake = LanguageDetector.interpret(text)
        let button = EditorView.pastedCode(intake, reindents: reindents)

        let textView = NSTextView()
        textView.string = text
        let coordinator = CodeEditorView.Coordinator(
            CodeEditorView(
                text: .constant(text), language: intake.language, theme: .oneDark,
                fontName: "SF Mono", fontSize: 13, fontLigatures: false,
                reindentOnPaste: reindents))
        coordinator.replaceAfterPaste(textView, with: intake.code, language: intake.language)
        #expect(textView.string == button)

        let claimed = try await measuredLineCount(of: text, reindents: reindents)
        #expect(claimed == LineSplitter.lineCount(of: button))
    }

    @Test(arguments: Self.reformattedSnippets)
    func reindentingChangesTheCountOfTheseSnippets(text: String) async throws {
        let raw = try await measuredLineCount(of: text, reindents: false)
        let tidied = try await measuredLineCount(of: text, reindents: true)
        #expect(raw != tidied)
    }

    @Test func theMenuBarKeepsCountingTheUntidiedText() async {
        let pasteboard = pasteboard(holding: "\n\nfunc a() {}\n\n")
        defer { pasteboard.releaseGlobally() }
        let state = MenuBarPanelState(pasteboard: pasteboard)
        state.refreshClipboard(access: .alwaysAllow)
        await state.clipboardInspectionFinished()
        guard case .text(let facts?) = state.clipboard else {
            Issue.record("Expected measured text, got \(state.clipboard)")
            return
        }
        #expect(facts.lineCount == 5)
    }

    @Test func aLanguageIsNamedOnlyWhenItIsOne() throws {
        let english = try localization("en")
        func description(_ language: Language, lines: Int) -> String? {
            ClipboardContent.text(ClipboardTextFacts(language: language, lineCount: lines))
                .measuredDescription(bundle: english)
        }
        #expect(description(.swift, lines: 1) == "1 line of Swift")
        #expect(description(.swift, lines: 14) == "14 lines of Swift")
        #expect(description(.plaintext, lines: 14) == "14 lines")
        #expect(description(.terminal, lines: 1) == "1 line")

        let blocks = ClipboardContent.text(
            ClipboardTextFacts(language: .swift, lineCount: 9, blockCount: 3))
        #expect(blocks.measuredDescription(bundle: english) == "3 code blocks")
    }

    @Test func theDescriptionIsTranslated() throws {
        let spanish = try localization("es")
        func description(_ language: Language) -> String? {
            ClipboardContent.text(ClipboardTextFacts(language: language, lineCount: 14))
                .measuredDescription(bundle: spanish)
        }
        #expect(description(.swift) == "14 líneas de Swift")
        #expect(description(.plaintext) == "14 líneas")
    }

    @Test func defaultAccessNeverReadsOrClaimsTheContents() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        let log = ReadLog()
        let monitor = monitor(on: pasteboard, log: log)

        for access: NSPasteboard.AccessBehavior in [.default, .ask, .alwaysDeny] {
            monitor.refresh(access: access)
            await monitor.inspectionFinished()
            #expect(monitor.clipboard.measuredDescription() == nil)
        }
        #expect(await log.reads == 0)
    }

    @Test func alwaysAllowMeasuresButHonorsConcealment() async throws {
        let english = try localization("en")
        let plain = pasteboard()
        let concealed = pasteboard(holding: nil)
        defer {
            plain.releaseGlobally()
            concealed.releaseGlobally()
        }
        let log = ReadLog()
        let open = monitor(on: plain, log: log)
        open.refresh(access: .alwaysAllow)
        await open.inspectionFinished()
        #expect(open.clipboard.measuredDescription(bundle: english) == "14 lines of Swift")

        #expect(ClipboardWriter.copy("hunter2", concealed: true, to: concealed))
        let secret = monitor(on: concealed, log: log)
        secret.refresh(access: .alwaysAllow)
        await secret.inspectionFinished()
        #expect(secret.clipboard.measuredDescription() == nil)
        #expect(await log.reads == 1)
    }

    @Test func resumingOnAnUnchangedClipboardKeepsTheMeasurementWithoutReading() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        let log = ReadLog()
        let monitor = monitor(on: pasteboard, log: log)
        monitor.resumeWatching(access: .alwaysAllow)
        await monitor.inspectionFinished()
        let measured = monitor.clipboard
        #expect(measured.measuredDescription() != nil)
        monitor.stopWatching()

        monitor.resumeWatching(access: .alwaysAllow)
        await monitor.inspectionFinished()
        monitor.stopWatching()
        #expect(monitor.clipboard == measured)
        #expect(await log.reads == 1)
    }

    @Test func resumingAfterAClipboardChangeShowsNoOldFacts() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        let log = ReadLog()
        let monitor = monitor(on: pasteboard, log: log)
        monitor.resumeWatching(access: .alwaysAllow)
        await monitor.inspectionFinished()
        #expect(monitor.clipboard.measuredDescription() != nil)
        monitor.stopWatching()

        pasteboard.clearContents()
        pasteboard.setString("let b = 2", forType: .string)
        monitor.resumeWatching(access: .alwaysAllow)
        // Before the new read lands, only what the types reveal is known.
        #expect(monitor.clipboard == .text(nil))
        await monitor.inspectionFinished()
        monitor.stopWatching()
        #expect(await log.reads == 2)
    }

    @Test func aReadStillRunningWhenTheClipboardChangesIsDiscarded() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        let log = ReadLog(holdsReads: true)
        let monitor = monitor(on: pasteboard, log: log)
        monitor.resumeWatching(access: .alwaysAllow)
        await waitForReads(1, log)
        monitor.stopWatching()

        pasteboard.clearContents()
        pasteboard.setString("let b = 2", forType: .string)
        monitor.resumeWatching(access: .alwaysAllow)
        monitor.stopWatching()
        await log.release()
        await waitForReads(2, log)
        #expect(monitor.clipboard == .text(nil))

        await log.release()
        await monitor.inspectionFinished()
        #expect(monitor.clipboard.measuredDescription() != nil)
    }

    @Test func resumingAfterAccessIsRevokedDropsTheMeasurement() async {
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        let log = ReadLog()
        let monitor = monitor(on: pasteboard, log: log)
        monitor.resumeWatching(access: .alwaysAllow)
        await monitor.inspectionFinished()
        monitor.stopWatching()

        monitor.resumeWatching(access: .ask)
        monitor.stopWatching()
        #expect(monitor.clipboard == .text(nil))
    }

    @Test func aMonitorCanSkipURLDetection() async {
        let pasteboard = pasteboard(holding: "https://example.com")
        defer { pasteboard.releaseGlobally() }
        let log = ReadLog()
        let reader = ClipboardReader(
            read: { _, _ in await log.read() },
            detectsWebURL: { _, _ in
                await log.detect()
                return true
            })

        let skipping = ClipboardMonitor(
            pasteboard: pasteboard, reader: reader, detectsWebURLs: false)
        skipping.refresh(access: .ask)
        await skipping.inspectionFinished()
        #expect(await log.detections == 0)
        #expect(skipping.clipboard == .text(nil))

        let detecting = ClipboardMonitor(pasteboard: pasteboard, reader: reader)
        detecting.refresh(access: .ask)
        await detecting.inspectionFinished()
        #expect(await log.detections == 1)
        #expect(detecting.clipboard == .possibleWebURL)
    }

    // MARK: - The copied PNG's size

    private func demoConfig() -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "let answer = 42"
        return config
    }

    @Test(arguments: [false, true])
    func theReportedBytesAreThePNGOnThePasteboard(richText: Bool) throws {
        let pasteboard = pasteboard(holding: nil)
        defer { pasteboard.releaseGlobally() }
        var reported: Data?
        let outcome = ExportManager.copyToPasteboardOutcome(
            demoConfig(), scale: 1, richText: richText, pasteboard: pasteboard,
            onCopied: { reported = $0 })

        #expect(outcome == .copied)
        let png = try #require(pasteboard.data(forType: .png))
        #expect(reported == png)
    }

    @Test func aRenderedRasterReportsItsBytesOnBothCopyPaths() throws {
        let pasteboard = pasteboard(holding: nil)
        defer { pasteboard.releaseGlobally() }
        let raster = try ExportManager.renderCGImageChecked(demoConfig(), scale: 1)

        var plain: Data?
        #expect(
            ExportManager.copyPNGToPasteboardOutcome(
                raster, to: pasteboard, onCopied: { plain = $0 }) == .copied)
        #expect(plain == pasteboard.data(forType: .png))

        var rich: Data?
        #expect(
            RichPasteboard.copyOutcome(
                cgImage: raster, config: demoConfig(), includeRichText: true, to: pasteboard,
                onCopied: { rich = $0 }) == .copied)
        #expect(rich == pasteboard.data(forType: .png))
    }

    @Test func aCaptureReportsTheSizeOfThePNGItCopied() {
        let pasteboard = pasteboard(holding: nil)
        defer { pasteboard.releaseGlobally() }
        let settings = AppSettings(defaults: testDefaults())
        settings.outputBehavior.autoCopy = true
        settings.outputBehavior.alsoSaveToFile = false
        let copied = QuickCapture.renderText(
            "let answer = 42", settings: settings, recents: nil, pasteboard: pasteboard)
        #expect(copied.copiedPNG != nil)
        #expect(copied.copiedPNG == pasteboard.data(forType: .png))

        settings.export.richClipboard = true
        let rich = QuickCapture.renderText(
            "let answer = 42", settings: settings, recents: nil, pasteboard: pasteboard)
        #expect(rich.copiedPNG == pasteboard.data(forType: .png))

        settings.outputBehavior.autoCopy = false
        let unsent = QuickCapture.renderText(
            "let answer = 42", settings: settings, recents: nil, pasteboard: pasteboard)
        #expect(unsent.copiedPNGBytes == nil)
    }

    @Test func onlyASuccessfulCopyCarriesTheSize() {
        let copied = ExportFeedback.copyOutcome(.copied, pngBytes: 210_000)
        #expect(copied.detail?.text.hasPrefix("PNG · ") == true)

        #expect(ExportFeedback.copyOutcome(.copied).detail == nil)
        #expect(ExportFeedback.copyOutcome(.failed, pngBytes: 210_000).detail == nil)
    }

    @Test func aCaptureThatAlsoSavedDoesNotPresentTheSizeAsTheFiles() {
        let copyOnly = Notifier.feedback(
            for: .copied, copiedToClipboard: true, savedToFile: false, copiedPNGBytes: 210_000)
        #expect(copyOnly.detail != nil)

        let alsoSaved = Notifier.feedback(
            for: .copied, copiedToClipboard: true, savedToFile: true, copiedPNGBytes: 210_000)
        #expect(alsoSaved.detail == nil)
    }

    @Test func voiceOverHearsTheSizeWithoutSymbols() throws {
        let feedback = ExportFeedback.copyOutcome(.copied, pngBytes: 210_000)
        let spoken = CaptureHUDController.announcement(for: feedback).message
        #expect(spoken.hasPrefix(feedback.message))
        #expect(spoken.contains("PNG"))
        #expect(!spoken.contains("·"))

        let plain = ExportFeedback.copyOutcome(.copied)
        #expect(CaptureHUDController.announcement(for: plain).message == plain.message)
    }
}
