import AppKit
import SwiftUI
import Testing
import VitrineRendering

@testable import Vitrine

/// Timers wake only when a test releases them, so nothing here depends on wall-clock time.
private final class ManualHold {
    private var waiters: [AsyncStream<Void>.Continuation] = []

    var started: Int { waiters.count }

    func sleep(_: Duration) async throws {
        let stream = AsyncStream<Void> { waiters.append($0) }
        for await _ in stream {}
    }

    func release(_ index: Int) {
        waiters[index].finish()
    }

    func waitForStart(of count: Int) async {
        while started < count { await Task.yield() }
    }
}

@Suite("Copy button confirmation")
struct CopyConfirmationTests {
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    @Test func aSuccessShowsTheCheckUntilTheHoldEnds() async {
        let hold = ManualHold()
        let confirmation = CopyConfirmation(sleep: hold.sleep)

        confirmation.record(.copied)
        #expect(confirmation.isShowing)
        await hold.waitForStart(of: 1)

        hold.release(0)
        await settle()
        #expect(!confirmation.isShowing)
    }

    @Test func aFailureNeverShowsTheCheckAndClearsAnEarlierOne() {
        let outcomes: [ExportManager.CopyOutcome] = [.failed, .renderFailed(.allocationFailed)]
        for outcome in outcomes {
            let hold = ManualHold()
            let confirmation = CopyConfirmation(sleep: hold.sleep)

            confirmation.record(outcome)
            #expect(!confirmation.isShowing)

            confirmation.record(.copied)
            confirmation.record(outcome)
            #expect(!confirmation.isShowing)
        }
    }

    @Test func anEarlierHoldCannotEndALaterConfirmation() async {
        let hold = ManualHold()
        let confirmation = CopyConfirmation(sleep: hold.sleep)

        confirmation.record(.copied)
        await hold.waitForStart(of: 1)
        confirmation.record(.copied)
        await hold.waitForStart(of: 2)

        hold.release(0)
        await settle()
        #expect(confirmation.isShowing)

        hold.release(1)
        await settle()
        #expect(!confirmation.isShowing)
    }

    @Test(arguments: [false, true])
    func theCheckKeepsTheButtonsSize(compact: Bool) {
        let hold = ManualHold()
        let confirmation = CopyConfirmation(sleep: hold.sleep)
        let host = NSHostingView(
            rootView: CopyImageCTALabel(confirmation: confirmation, compact: compact))
        host.layoutSubtreeIfNeeded()
        let idle = host.fittingSize
        #expect(idle.width > 0)

        confirmation.record(.copied)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize == idle)
    }

    @Test func onlyASuccessChangesWhatTheLabelDraws() throws {
        func pixels(after outcome: ExportManager.CopyOutcome?) throws -> Data {
            let hold = ManualHold()
            let confirmation = CopyConfirmation(sleep: hold.sleep)
            if let outcome { confirmation.record(outcome) }
            let renderer = ImageRenderer(
                content: CopyImageCTALabel(confirmation: confirmation, compact: false)
                    .foregroundStyle(.white)
                    .frame(width: 120, height: 30)
                    .background(.black))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            return try #require(NSBitmapImageRep(cgImage: image).tiffRepresentation)
        }
        let idle = try pixels(after: nil)
        #expect(try pixels(after: .failed) == idle)
        #expect(try pixels(after: .copied) != idle)
    }

    @Test func theMenuCommandConfirmsARealCopyOnly() throws {
        let settings = AppSettings(defaults: testDefaults())
        settings.outputBehavior.closeAfterCopy = false
        settings.export.richClipboard = false
        settings.export.textSidecar = true
        let hold = ManualHold()
        let confirmation = CopyConfirmation(sleep: hold.sleep)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        // Cancelling the export check leaves nothing copied, so nothing to confirm.
        let cancelling = EditorPresentation(
            presentPin: { _ in }, presentShare: { _, _ in }, batchExport: .noOp,
            resolvePreflight: { _, _ in .cancel })
        settings.config.code = "let a = \"gh" + "p_" + String(repeating: "x", count: 36) + "\""
        EditorCommandResponder(settings: settings, feedback: .noOp, presentation: cancelling)
            .copyImage(
                from: settings, editorWindow: nil, confirmation: confirmation,
                pasteboard: pasteboard)
        #expect(!confirmation.isShowing)
        #expect(pasteboard.pasteboardItems?.isEmpty ?? true)

        settings.config.code = "let x = 1"
        EditorCommandResponder(settings: settings, feedback: .noOp, presentation: .noOp)
            .copyImage(
                from: settings, editorWindow: nil, confirmation: confirmation,
                pasteboard: pasteboard)
        #expect(confirmation.isShowing)
        #expect(pasteboard.data(forType: .png) != nil)
    }
}
