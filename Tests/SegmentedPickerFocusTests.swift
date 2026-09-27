import AppKit
import SwiftUI
import Testing

@testable import Vitrine

/// Drives a real window with AppKit events: a mouse click selects without taking focus from
/// the editor, and the keyboard reaches the control as one stop whose arrows change the value.
@MainActor
@Suite("Segmented picker focus")
struct SegmentedPickerFocusTests {
    @Observable final class Selection { var value = 0 }

    private struct Picker: View {
        @Bindable var selection: Selection
        var body: some View {
            TokenSegmentedPicker(
                options: [
                    (0, Text(verbatim: "A")), (1, Text(verbatim: "B")), (2, Text(verbatim: "C")),
                ],
                selection: $selection.value, fillsWidth: true)
        }
    }

    private struct Harness {
        let window: NSWindow
        let hosting: NSHostingView<Picker>
        let selection: Selection
    }

    private func makeHarness(above: NSView) -> Harness {
        let selection = Selection()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled],
            backing: .buffered, defer: false)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        above.frame = NSRect(x: 0, y: 120, width: 300, height: 60)
        let hosting = NSHostingView(rootView: Picker(selection: selection))
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        container.addSubview(above)
        container.addSubview(hosting)
        window.contentView = container
        window.orderFrontRegardless()
        return Harness(window: window, hosting: hosting, selection: selection)
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(200)) }

    private func click(_ harness: Harness, segment: Int) throws {
        let point = harness.hosting.convert(NSPoint(x: 50 + 100 * segment, y: 50), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            harness.window.sendEvent(
                try #require(
                    NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: harness.window.windowNumber, context: nil, eventNumber: 0,
                        clickCount: 1, pressure: 1)))
        }
    }

    private func pressRightArrow(_ window: NSWindow) throws {
        let arrow = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            window.sendEvent(
                try #require(
                    NSEvent.keyEvent(
                        with: type, location: .zero, modifierFlags: [.numericPad, .function],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, characters: arrow,
                        charactersIgnoringModifiers: arrow, isARepeat: false, keyCode: 124)))
        }
    }

    @Test func mouseSelectionKeepsTheEditorsKeyboardFocus() async throws {
        let editor = NSTextView()
        let harness = makeHarness(above: editor)
        defer { harness.window.orderOut(nil) }
        #expect(harness.window.makeFirstResponder(editor))
        try await settle()

        try click(harness, segment: 0)
        try await settle()
        #expect(harness.window.firstResponder === editor, "clicking the selected segment")

        try click(harness, segment: 1)
        try await settle()
        #expect(harness.selection.value == 1)
        #expect(harness.window.firstResponder === editor, "clicking another segment")
    }

    @Test func keyboardReachesTheControlAsOneStopFollowingTheSystemSetting() async throws {
        let before = NSButton(title: "Before", target: nil, action: nil)
        let harness = makeHarness(above: before)
        defer { harness.window.orderOut(nil) }
        #expect(harness.window.makeFirstResponder(before))
        try await settle()

        harness.window.selectNextKeyView(nil)
        try await settle()
        guard NSApp.isFullKeyboardAccessEnabled else {
            // Like native controls, it joins the key loop only with keyboard navigation on.
            #expect(harness.window.firstResponder === before)
            return
        }
        #expect(harness.window.firstResponder !== before)

        try pressRightArrow(harness.window)
        try await settle()
        try pressRightArrow(harness.window)
        try await settle()
        #expect(harness.selection.value == 2, "arrows keep focus between moves")
        try pressRightArrow(harness.window)
        try await settle()
        #expect(harness.selection.value == 2, "arrows stop at the last segment")

        harness.window.selectNextKeyView(nil)
        try await settle()
        #expect(harness.window.firstResponder === before, "one key-view stop for the whole control")
    }
}
