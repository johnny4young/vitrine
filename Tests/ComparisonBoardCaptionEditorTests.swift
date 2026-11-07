import AppKit
import SwiftUI
import Testing

@testable import Vitrine

/// Drives the inline caption fields in a real window with AppKit's field editor, because
/// what a field commits, and to which capture, is decided there.
@MainActor
@Suite("Comparison board caption editor")
struct ComparisonBoardCaptionEditorTests {
    @Observable final class Model {
        let first = UUID()
        let second = UUID()
        var editing: UUID
        var labels: [UUID: String]
        var details: [UUID: String] = [:]
        var ended: [UUID] = []

        init() {
            editing = first
            labels = [first: "First", second: "Second"]
        }
    }

    private struct Host: View {
        @Bindable var model: Model

        var body: some View {
            let id = model.editing
            ComparisonBoardCaptionEditor(
                captureID: id,
                index: 0,
                label: Binding(
                    get: { model.labels[id] ?? "" }, set: { model.labels[id] = $0 }),
                detail: Binding(
                    get: { model.details[id] ?? "" }, set: { model.details[id] = $0 }),
                onEnd: { model.ended.append($0) })
        }
    }

    private struct Harness {
        let window: NSWindow
        let other: NSTextView
        let model: Model

        var fieldEditor: NSTextView? { window.firstResponder as? NSTextView }

        func replaceText(with text: String) {
            guard let fieldEditor, fieldEditor !== other else {
                Issue.record("no inline field has focus")
                return
            }
            fieldEditor.selectAll(nil)
            fieldEditor.insertText(text, replacementRange: fieldEditor.selectedRange())
        }

        func textField(placeholder: String) -> NSTextField? {
            func search(_ view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.placeholderString == placeholder {
                    return field
                }
                return view.subviews.lazy.compactMap(search).first
            }
            return window.contentView.flatMap(search)
        }

        func press(characters: String, keyCode: UInt16) throws {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                window.sendEvent(
                    try #require(
                        NSEvent.keyEvent(
                            with: type, location: .zero, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: window.windowNumber, context: nil,
                            characters: characters, charactersIgnoringModifiers: characters,
                            isARepeat: false, keyCode: keyCode)))
            }
        }
    }

    private func makeHarness() async throws -> Harness {
        let model = Model()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled],
            backing: .buffered, defer: false)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        let other = NSTextView(frame: NSRect(x: 0, y: 160, width: 320, height: 40))
        let hosting = NSHostingView(rootView: Host(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 150)
        container.addSubview(other)
        container.addSubview(hosting)
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        let harness = Harness(window: window, other: other, model: model)
        // Focus arrives asynchronously, so every step waits for its outcome instead of a fixed pause.
        try await waitUntil { harness.fieldEditor.map { $0 !== other } ?? false }
        return harness
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<60 where !condition() { try await Task.sleep(for: .milliseconds(50)) }
    }

    private func waitForFieldEditor(showing text: String, in harness: Harness) async throws {
        for _ in 0..<60 where harness.fieldEditor?.string != text {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func switchingCaptionsKeepsEachCapturesText() async throws {
        let harness = try await makeHarness()
        defer { harness.window.orderOut(nil) }
        let model = harness.model

        harness.replaceText(with: "Typed for first")
        try await waitUntil { model.labels[model.first] == "Typed for first" }
        #expect(model.labels[model.first] == "Typed for first")

        model.editing = model.second
        try await waitForFieldEditor(showing: "Second", in: harness)

        #expect(model.labels[model.first] == "Typed for first")
        #expect(model.labels[model.second] == "Second")
        #expect(harness.fieldEditor?.string == "Second")
        #expect(!model.ended.contains(model.second))

        harness.replaceText(with: "Typed for second")
        try await waitUntil { model.labels[model.second] == "Typed for second" }
        #expect(model.labels[model.first] == "Typed for first")
        #expect(model.labels[model.second] == "Typed for second")
    }

    @Test func switchingStraightAfterTypingKeepsEachCapturesText() async throws {
        let harness = try await makeHarness()
        defer { harness.window.orderOut(nil) }
        let model = harness.model

        harness.replaceText(with: "Typed for first")
        model.editing = model.second
        try await waitForFieldEditor(showing: "Second", in: harness)

        #expect(model.labels[model.first] == "Typed for first")
        #expect(model.labels[model.second] == "Second")
    }

    /// Each caption opens on its label, even if the last one was left in its detail field.
    @Test func switchingCaptionsStartsOnTheNewLabel() async throws {
        let harness = try await makeHarness()
        defer { harness.window.orderOut(nil) }
        let model = harness.model

        let detail = try #require(harness.textField(placeholder: "Optional detail"))
        #expect(harness.window.makeFirstResponder(detail))
        try await waitUntil { harness.fieldEditor?.delegate === detail }
        harness.replaceText(with: "Detail for first")
        try await waitUntil { model.details[model.first] == "Detail for first" }
        #expect(model.details[model.first] == "Detail for first")

        model.editing = model.second
        try await waitForFieldEditor(showing: "Second", in: harness)

        #expect(harness.fieldEditor?.string == "Second")
        #expect(model.details[model.second, default: ""].isEmpty)
    }

    @Test func returnEndsTheEdit() async throws {
        let harness = try await makeHarness()
        defer { harness.window.orderOut(nil) }

        try harness.press(characters: "\r", keyCode: 36)
        try await waitUntil { harness.model.ended.contains(harness.model.first) }

        #expect(harness.model.ended.contains(harness.model.first))
    }

    @Test func escapeEndsTheEdit() async throws {
        let harness = try await makeHarness()
        defer { harness.window.orderOut(nil) }

        try harness.press(characters: "\u{1B}", keyCode: 53)
        try await waitUntil { harness.model.ended.contains(harness.model.first) }

        #expect(harness.model.ended.contains(harness.model.first))
    }

    @Test func movingFocusElsewhereEndsTheEdit() async throws {
        let harness = try await makeHarness()
        defer { harness.window.orderOut(nil) }

        #expect(harness.window.makeFirstResponder(harness.other))
        try await waitUntil { harness.model.ended.contains(harness.model.first) }

        #expect(harness.model.ended.contains(harness.model.first))
    }
}
