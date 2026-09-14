import AppKit
import SwiftUI
import Testing

@testable import Vitrine

/// The editor window's sizing.
///
/// The hosting controller derives no size constraints from the editor, because deriving
/// them re-measured the whole hierarchy on every keystroke. These tests pin the two halves
/// of that trade: the hosting controller stays out of sizing, and the window still refuses
/// to shrink below the minimum the content would have enforced.
@MainActor
@Suite("Editor window sizing")
struct EditorWindowSizingTests {
    private static func makeSession(_ environment: AppEnvironment, index: Int) -> EditorSession {
        EditorSession(
            identity: EditorWindowIdentity(index: index), environment: environment,
            feedback: .noOp, presentation: .noOp)
    }

    /// An editor-shaped window that is never ordered on screen.
    private static func makeWindow(hosting content: NSViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = content
        window.setContentSize(NSSize(width: 1_180, height: 680))
        return window
    }

    @Test func theHostingControllerDerivesNoSizeConstraints() {
        let environment = AppEnvironment(defaults: testDefaults())
        let session = Self.makeSession(environment, index: 41)
        defer { session.discard() }

        let hosting = EditorWindowController.makeHostingController(
            environment: environment, session: session)

        #expect(hosting.sizingOptions.isEmpty)
    }

    /// The same editor hosted with the default sizing options is the reference: the
    /// minimum its constraints impose is the one the pinned window must keep.
    @Test func thePinnedMinimumIsTheOneTheContentWouldEnforce() {
        let environment = AppEnvironment(defaults: testDefaults())
        let session = Self.makeSession(environment, index: 42)
        defer { session.discard() }
        session.settings.documentCode = "let value = 1\n"

        let reference = Self.makeWindow(
            hosting: NSHostingController(
                rootView: EditorView(environment: environment)
                    .environment(session.settings)
                    .environment(session)))
        // The hosting controller installs its constraints over the next few layout passes.
        for _ in 0..<40 where reference.contentMinSize == .zero {
            reference.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        let expected = reference.contentMinSize
        reference.contentViewController = nil

        let window = Self.makeWindow(
            hosting: EditorWindowController.makeHostingController(
                environment: environment, session: session))
        defer { window.contentViewController = nil }
        EditorWindowController.pinMinimumContentSize(of: window)

        #expect(expected.width > EditorLayout.codeColumnWidth + EditorLayout.inspectorMinWidth)
        #expect(window.contentMinSize == expected)

        // AppKit holds the window to that minimum even when code sets a smaller frame.
        window.setFrame(NSRect(x: 0, y: 0, width: 600, height: 400), display: false)
        window.layoutIfNeeded()
        let content = window.contentRect(forFrameRect: window.frame).size
        #expect(content.width >= expected.width)
        #expect(content.height >= expected.height)
    }

    @Test func aResizeMeasuresTheMinimumAgain() {
        let environment = AppEnvironment(defaults: testDefaults())
        let controller = EditorWindowController(
            environment: environment, feedback: .noOp, presentation: .noOp)
        let session = Self.makeSession(environment, index: 43)
        defer { session.discard() }
        let window = Self.makeWindow(
            hosting: EditorWindowController.makeHostingController(
                environment: environment, session: session))
        defer { window.contentViewController = nil }
        EditorWindowController.pinMinimumContentSize(of: window)
        let measured = window.contentMinSize
        window.contentMinSize = .zero

        controller.windowWillStartLiveResize(
            Notification(name: NSWindow.willStartLiveResizeNotification, object: window))

        #expect(measured != .zero)
        #expect(window.contentMinSize == measured)
    }
}
