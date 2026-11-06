import AppKit
import SwiftUI
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@Suite("Canvas mode")
@MainActor
struct CanvasModeTests {
    @Test func theViewMenuTogglesCanvasModeThroughTheEditorResponder() throws {
        let menu = makeIsolatedAppMenu()
        let view = try #require(
            menu.make().items.compactMap(\.submenu).first { $0.title == "View" })
        let item = try #require(
            view.items.first {
                $0.accessibilityIdentifier()
                    == VitrineCommand.toggleCanvasMode.accessibilityIdentifier
            })
        #expect(item.target === menu.editorCommands)
    }

    /// Covers the menu items that are not `VitrineCommand`s too: annotation tools, mark
    /// actions and full screen all compete for the same keys.
    @Test func noTwoMainMenuItemsShareAShortcut() {
        func items(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) }
        }
        var seen: [String: String] = [:]
        for item in items(makeIsolatedAppMenu().make()) where !item.keyEquivalent.isEmpty {
            var mask = item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)
            // AppKit reads an uppercase key equivalent as Shift plus that key.
            if item.keyEquivalent != item.keyEquivalent.lowercased() { mask.insert(.shift) }
            let signature = "\(mask.rawValue):\(item.keyEquivalent.lowercased())"
            #expect(seen[signature] == nil, "\(item.title) reuses \(seen[signature] ?? "")'s key")
            seen[signature] = item.title
        }
    }

    @Test func theMenuCheckMarkFollowsTheSessionsMode() {
        let environment = AppEnvironment(defaults: testDefaults())
        let session = EditorSession(
            identity: EditorWindowIdentity(index: 61), environment: environment,
            feedback: .noOp, presentation: .noOp)
        defer { session.discard() }
        let responder = makeIsolatedAppMenu().editorCommands
        let item = NSMenuItem()

        session.isCanvasMode = true
        _ = responder.validateCanvasMode(item, session: session)
        #expect(item.state == .on)
        session.isCanvasMode = false
        _ = responder.validateCanvasMode(item, session: session)
        #expect(item.state == .off)
        #expect(!responder.validateCanvasMode(item, session: nil))
    }

    @Test func anImageSwapsTheCodeOnlyPanesForItsFrame() {
        let code = InspectorPane.dockPanes(usesImageContent: false)
        let image = InspectorPane.dockPanes(usesImageContent: true)
        #expect(code.contains(.theme) && code.contains(.typography) && !code.contains(.frame))
        #expect(image.contains(.frame) && !image.contains(.theme) && !image.contains(.typography))
        #expect(code.contains(.background) && image.contains(.background))
    }

    @Test func theDockReadsTheValueTheInspectorShows() {
        var style = SnapshotConfig()
        style.background = .gradient(.ocean)
        #expect(
            InspectorPane.background.dockValue(in: style)
                == InspectorReadout.background(style.background))
        #expect(
            InspectorPane.typography.dockValue(in: style)
                == InspectorReadout.typography(fontName: style.fontName, fontSize: style.fontSize))
        style.padding = 47.6
        #expect(InspectorPane.canvas.dockValue(in: style) == "48")
    }

    /// The inspector header names only a gradient preset; the dock has no controls beside
    /// it, so every other kind still needs a name.
    @Test func everyBackgroundKindHasADistinctDockName() {
        let backgrounds: [VitrineDomain.BackgroundStyle] = [
            .gradient(.aurora), .customGradient(GradientPreset.aurora.asCustomGradient),
            .solid(RGBAColor(red: 1, green: 0, blue: 0, opacity: 1)),
            .image(ImageBackground(reference: ImageReference(fileName: "a.png"))), .transparent,
        ]
        let names = backgrounds.map { background in
            var style = SnapshotConfig()
            style.background = background
            return InspectorPane.background.dockValue(in: style)
        }
        #expect(!names.contains(""))
        #expect(Set(names).count == backgrounds.count)
    }

    /// A popover or panel can be key without becoming main; commands then act on the
    /// main window behind it. A real window, such as Settings, still wins.
    @Test func menuCommandsLookPastAKeyPopoverOrPanel() {
        final class MainCapableWindow: NSWindow {
            override var canBecomeMain: Bool { true }
        }
        let editor = MainCapableWindow()
        let settings = MainCapableWindow()
        let panel = NSPanel()
        #expect(!panel.canBecomeMain)
        #expect(EditorWindowController.commandTarget(key: panel, main: editor) === editor)
        #expect(EditorWindowController.commandTarget(key: settings, main: editor) === settings)
        #expect(EditorWindowController.commandTarget(key: nil, main: editor) === editor)
    }

    /// The click that closes a popover on mouse down reaches its button's action next.
    @Test func pressingTheOpenPanesButtonClosesItInsteadOfReopening() {
        let closed = DockPopoverClose(pane: .canvas, uptime: 100)
        #expect(
            DockPopoverClose.pane(afterPressing: .canvas, open: .canvas, lastClose: nil, now: 100)
                == nil)
        #expect(
            DockPopoverClose.pane(
                afterPressing: .canvas, open: nil, lastClose: closed, now: 100.1) == nil)
        #expect(
            DockPopoverClose.pane(
                afterPressing: .theme, open: nil, lastClose: closed, now: 100.1) == .theme)
        #expect(
            DockPopoverClose.pane(
                afterPressing: .canvas, open: nil, lastClose: closed, now: 102) == .canvas)
    }

    /// Collapsing keeps the text view alive at its column width, so its text, wrap and
    /// undo survive, but hides it from the key-view loop so typing cannot reach it.
    @Test func collapsingTheColumnsKeepsTheCodeEditorAndDropsItsFocus() throws {
        let environment = AppEnvironment(defaults: testDefaults())
        let session = EditorSession(
            identity: EditorWindowIdentity(index: 62), environment: environment,
            feedback: .noOp, presentation: .noOp)
        defer { session.discard() }
        session.settings.documentCode = "let answer = 42"
        let hosting = EditorWindowController.makeHostingController(
            environment: environment, session: session)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 680),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        defer { window.contentViewController = nil }
        hosting.view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let textView = try #require(Self.firstTextView(in: hosting.view))
        let width = textView.frame.width
        #expect(window.makeFirstResponder(textView))
        textView.insertText("!", replacementRange: textView.selectedRange())
        let text = textView.string

        session.isCanvasMode = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        hosting.view.layoutSubtreeIfNeeded()
        #expect(Self.firstTextView(in: hosting.view) === textView)
        #expect(textView.frame.width == width)
        #expect(window.firstResponder !== textView)
        #expect(!textView.canBecomeKeyView)
        for _ in 0..<40 {
            window.selectNextKeyView(nil)
            #expect(window.firstResponder !== textView)
        }

        session.isCanvasMode = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        hosting.view.layoutSubtreeIfNeeded()
        #expect(Self.firstTextView(in: hosting.view) === textView)
        #expect(textView.canBecomeKeyView)
        #expect(textView.string == text)
        #expect(textView.undoManager?.canUndo == true)
    }

    /// The stage gets every point the collapsed columns give up.
    @Test func collapsedColumnsLeaveTheWholeWidthToTheStage() {
        final class Probe: NSView {}
        struct ProbeView: NSViewRepresentable {
            let view: Probe
            func makeNSView(context: Context) -> Probe { view }
            func updateNSView(_ nsView: Probe, context: Context) {}
        }
        let stage = Probe()
        let columns = HStack(spacing: 0) {
            Color.clear.frame(width: EditorLayout.codeColumnWidth)
                .modifier(EditorView.CollapsedColumn(isCollapsed: true, overflow: .trailing))
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(EditorLayout.stageLayoutPriority)
                .background(ProbeView(view: stage))
            Color.clear
                .frame(
                    minWidth: EditorLayout.inspectorMinWidth,
                    maxWidth: EditorLayout.inspectorMaxWidth
                )
                .modifier(EditorView.CollapsedColumn(isCollapsed: true, overflow: .leading))
                .layoutPriority(EditorLayout.inspectorLayoutPriority)
        }
        let host = NSHostingView(rootView: columns)
        host.frame = NSRect(x: 0, y: 0, width: 940, height: 520)
        host.layoutSubtreeIfNeeded()
        #expect(stage.frame.width == 940)
    }

    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }
}
