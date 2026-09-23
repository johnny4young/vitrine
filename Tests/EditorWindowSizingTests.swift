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

    /// The production editor's title-bar configuration, without ordering on screen.
    private static func makeWindow(hosting content: NSViewController) -> NSWindow {
        let window = TitleBarAlignedWindow(contentViewController: content)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
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

    /// Qualify the product minimum independently of XCUITest pointer hit-testing.
    /// A resize stopping early must not be assumed to be only an automation problem.
    @Test(arguments: ["", "let value = 1\n"])
    func compactViewportFitsTheMeasuredMinimum(code: String) {
        let environment = AppEnvironment(defaults: testDefaults())
        let session = Self.makeSession(environment, index: 44)
        defer { session.discard() }
        session.settings.documentCode = code
        let window = Self.makeWindow(
            hosting: EditorWindowController.makeHostingController(
                environment: environment, session: session))
        defer { window.contentViewController = nil }
        window.contentView?.layoutSubtreeIfNeeded()
        EditorWindowController.pinMinimumContentSize(of: window)
        let minimumFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: window.contentMinSize)
        ).size
        print(
            "EDITOR-MINIMUM hasContent=\(!code.isEmpty) width=\(minimumFrame.width) height=\(minimumFrame.height)"
        )
        #expect(minimumFrame.width <= 960, "Measured minimum frame: \(minimumFrame)")
        #expect(minimumFrame.height <= 600, "Measured minimum frame: \(minimumFrame)")
    }

    /// The compact limit must also hold after the real title-bar window is shown;
    /// a detached hosting controller can report a smaller minimum than live AppKit.
    @Test func displayedDemoEditorFitsTheCompactViewport() {
        let environment = AppEnvironment(defaults: testDefaults())
        let session = Self.makeSession(environment, index: 45)
        defer { session.discard() }
        session.settings.documentCode = """
            import SwiftUI

            struct CounterView: View {
                @State private var count = 0

                var body: some View {
                    Button("Tapped \\(count) times") { count += 1 }
                }
            }
            """
        let window = Self.makeWindow(
            hosting: EditorWindowController.makeHostingController(
                environment: environment, session: session))
        defer {
            window.close()
            window.contentViewController = nil
        }
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
        let controller = EditorWindowController(
            environment: environment, feedback: .noOp, presentation: .noOp)
        controller.windowWillStartLiveResize(
            Notification(name: NSWindow.willStartLiveResizeNotification, object: window))
        let minimumFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: window.contentMinSize)
        ).size
        print("EDITOR-DISPLAYED-MINIMUM width=\(minimumFrame.width) height=\(minimumFrame.height)")
        print("EDITOR-DISPLAYED-FRAME-MINIMUM width=\(window.minSize.width)")
        #expect(minimumFrame.width <= 960, "Displayed minimum frame: \(minimumFrame)")
        #expect(minimumFrame.height <= 600, "Displayed minimum frame: \(minimumFrame)")
        #expect(window.minSize.width <= 960, "Displayed frame minimum: \(window.minSize)")
        window.setFrame(NSRect(x: 0, y: 0, width: 960, height: 600), display: true)
        for _ in 0..<5 {
            window.layoutIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        print("EDITOR-DISPLAYED-RESIZE width=\(window.frame.width) height=\(window.frame.height)")
        #expect(window.frame.width <= 962, "Displayed compact frame: \(window.frame)")
        #expect(window.frame.height <= 602, "Displayed compact frame: \(window.frame)")
    }

    /// Sets a frame far below any editor minimum in code, gives layout a few passes to
    /// react, and returns the content size the window ends up with.
    private static func contentSizeAfterShrinking(_ window: NSWindow) -> NSSize {
        window.setFrame(NSRect(x: 0, y: 0, width: 600, height: 400), display: false)
        for _ in 0..<5 {
            window.layoutIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        return window.contentRect(forFrameRect: window.frame).size
    }

    private static func minimumConstraints(of window: NSWindow) -> [NSLayoutConstraint] {
        let identifiers = [
            EditorWindowController.minimumWidthIdentifier,
            EditorWindowController.minimumHeightIdentifier,
        ]
        let constraints = window.contentViewController?.view.constraints ?? []
        return constraints.filter { identifiers.contains($0.identifier ?? "") }
    }

    /// The same editor hosted with the default sizing options is the reference: the
    /// minimum its constraints impose, and how a window holds to it when code sets a
    /// smaller frame, is what the pinned window must reproduce on every macOS release.
    @Test func thePinnedMinimumHoldsLikeTheConstraintsItReplaces() {
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
        let referenceShrunk = Self.contentSizeAfterShrinking(reference)
        reference.contentViewController = nil

        let window = Self.makeWindow(
            hosting: EditorWindowController.makeHostingController(
                environment: environment, session: session))
        defer { window.contentViewController = nil }
        EditorWindowController.pinMinimumContentSize(of: window)

        #expect(expected.width > EditorLayout.codeColumnWidth + EditorLayout.inspectorMinWidth)
        #expect(window.contentMinSize == expected)
        #expect(
            Self.minimumConstraints(of: window).map(\.constant).sorted()
                == [expected.height, expected.width].sorted())

        let shrunk = Self.contentSizeAfterShrinking(window)
        let referenceHeld =
            referenceShrunk.width >= expected.width && referenceShrunk.height >= expected.height
        let pinnedHeld = shrunk.width >= expected.width && shrunk.height >= expected.height
        #expect(
            pinnedHeld == referenceHeld,
            "the reference ended at \(referenceShrunk), the pinned window at \(shrunk)")
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
        for constraint in Self.minimumConstraints(of: window) { constraint.constant = 0 }

        controller.windowWillStartLiveResize(
            Notification(name: NSWindow.willStartLiveResizeNotification, object: window))

        #expect(measured != .zero)
        #expect(window.contentMinSize == measured)
        // Measuring again updates the same two constraints instead of stacking new ones.
        #expect(
            Self.minimumConstraints(of: window).map(\.constant).sorted()
                == [measured.height, measured.width].sorted())
    }
}
