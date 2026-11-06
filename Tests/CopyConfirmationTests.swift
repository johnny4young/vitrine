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
}

/// The one path the Copy button, the command palette and the File menu call.
@Suite("Editor session copy")
struct EditorSessionCopyTests {
    private final class FeedbackSpy {
        var received: [Notifier.CaptureFeedback] = []
        var display: FeedbackDisplay { FeedbackDisplay { [self] item, _ in received.append(item) } }
    }

    private func makeSession(
        code: String = "let x = 1", feedback: FeedbackDisplay = .noOp,
        presentation: EditorPresentation = .noOp
    ) -> EditorSession {
        let settings = AppSettings(defaults: testDefaults())
        settings.config.code = code
        settings.outputBehavior.closeAfterCopy = false
        settings.export.richClipboard = false
        settings.export.textSidecar = true
        return EditorSession(
            identity: EditorWindowIdentity(index: 62),
            environment: AppEnvironment(defaults: testDefaults()),
            feedback: feedback, presentation: presentation, settings: settings)
    }

    @Test func aSuccessCopiesReportsAndConfirms() throws {
        let spy = FeedbackSpy()
        let session = makeSession(feedback: spy.display)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        #expect(session.copyImage(closing: nil, pasteboard: pasteboard) == nil)

        let png = try #require(pasteboard.data(forType: .png))
        // The HUD reports the bytes that reached the clipboard.
        #expect(spy.received == [ExportFeedback.copyOutcome(.copied, pngBytes: png.count)])
        #expect(session.copyConfirmation.isShowing)
    }

    /// A canvas past the render budget is a real failed copy, not a stubbed one.
    @Test func aFailedCopyReportsAndClearsAnEarlierCheck() throws {
        let spy = FeedbackSpy()
        let session = makeSession(feedback: spy.display)
        session.settings.outputBehavior.closeAfterCopy = true
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        session.copyConfirmation.record(.copied)
        session.settings.config.padding = 1_000_000

        let window = NSWindow()
        window.isReleasedWhenClosed = false
        #expect(session.copyImage(closing: window, pasteboard: pasteboard) == nil)

        #expect(try #require(spy.received.first).category == .failure)
        #expect(!session.copyConfirmation.isShowing)
    }

    @Test func cancellingTheExportCheckCopiesAndConfirmsNothing() {
        let spy = FeedbackSpy()
        let cancelling = EditorPresentation(
            presentPin: { _ in }, presentShare: { _, _ in }, batchExport: .noOp,
            resolvePreflight: { _, _ in .cancel })
        let session = makeSession(
            code: "let a = \"gh" + "p_" + String(repeating: "x", count: 36) + "\"",
            feedback: spy.display, presentation: cancelling)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        #expect(session.copyImage(closing: nil, pasteboard: pasteboard) == nil)

        #expect(pasteboard.pasteboardItems?.isEmpty ?? true)
        #expect(spy.received.isEmpty)
        #expect(!session.copyConfirmation.isShowing)
    }
}

/// The primary session outlives its window, so a check must not outlive the copy's context.
@Suite("Copy confirmation lifetime", .serialized)
struct CopyConfirmationLifetimeTests {
    private func makeController() -> EditorWindowController {
        EditorWindowController(
            environment: AppEnvironment(defaults: testDefaults()), feedback: .noOp,
            presentation: .noOp)
    }

    @Test func closingThePrimaryWindowClearsTheCheckItsReusedSessionWouldShow() throws {
        let controller = makeController()
        defer { controller.discardAllSessions() }
        controller.show()
        let window = try #require(controller.movePrimaryEditorOffScreenForTesting())
        let session = controller.session(for: .primary)
        session.copyConfirmation.record(.copied)

        window.close()

        #expect(controller.session(for: .primary) === session)
        #expect(!session.copyConfirmation.isShowing)
    }

    @Test func loadingIntoAClosedPrimaryWindowClearsTheCheck() throws {
        let controller = makeController()
        defer { controller.discardAllSessions() }
        let session = controller.session(for: .primary)
        session.copyConfirmation.record(.copied)

        controller.loadIntoPrimary(SnapshotConfig())
        let window = try #require(controller.movePrimaryEditorOffScreenForTesting())
        defer { window.close() }

        #expect(!session.copyConfirmation.isShowing)
    }

    @Test func replacingTheDocumentClearsTheCheck() {
        let environment = AppEnvironment(defaults: testDefaults())
        let session = EditorSession(
            identity: EditorWindowIdentity(index: 63), environment: environment,
            feedback: .noOp, presentation: .noOp)
        defer { session.discard() }
        let hosting = EditorWindowController.makeHostingController(
            environment: environment, session: session)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 680),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        defer { window.contentViewController = nil }
        func settle() {
            for _ in 0..<5 {
                hosting.view.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            }
        }
        settle()
        session.copyConfirmation.record(.copied)

        session.settings.noteDocumentReplaced()
        settle()

        #expect(!session.copyConfirmation.isShowing)
    }
}
