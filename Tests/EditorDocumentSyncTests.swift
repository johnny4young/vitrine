import AppKit
import SwiftUI
import Testing

@testable import Vitrine

/// A keystroke no longer re-evaluates the editor's root view: only the views that read
/// the document text observe it. The code editor used to receive every document change
/// through that root, so this pins the change that arrives from outside the text view —
/// a paste from the empty state, Format, a live-file reload, a restored draft.
@MainActor
@Suite("Editor document sync")
struct EditorDocumentSyncTests {
    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }

    /// Runs the layout pass and the main-actor work a visible window would run before
    /// its next frame.
    private static func settle(_ view: NSView) {
        for _ in 0..<5 {
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

    @Test func aDocumentChangeFromOutsideTheTextViewReachesIt() throws {
        let environment = AppEnvironment(defaults: testDefaults())
        let session = EditorSession(
            identity: EditorWindowIdentity(index: 51), environment: environment,
            feedback: .noOp, presentation: .noOp)
        defer { session.discard() }
        session.settings.documentCode = "let first = 1"

        let hosting = EditorWindowController.makeHostingController(
            environment: environment, session: session)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        defer { window.contentViewController = nil }
        Self.settle(hosting.view)
        let textView = try #require(Self.firstTextView(in: hosting.view))
        #expect(textView.string == "let first = 1")

        session.settings.documentCode = "let second = 2\nlet third = 3"
        Self.settle(hosting.view)
        #expect(textView.string == "let second = 2\nlet third = 3")

        session.settings.documentCode = ""
        Self.settle(hosting.view)
        #expect(textView.string.isEmpty)
    }
}
