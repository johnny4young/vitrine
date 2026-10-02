import AppKit
import VitrineDomain

/// Owns the one large format that may still be running for an editor window, so the
/// Format Code command and the toolbar button share its cancellation and stale-result
/// rules. A short-lived owner would cancel the work as soon as it was released.
final class CodeFormatOperation {
    /// Small snippets format synchronously so the command feels instant. Larger ones do
    /// the string work off the main actor; beyond the cap, formatting is refused instead
    /// of risking an unresponsive editor.
    static let asyncThresholdBytes = 64 * 1024
    static let maxInteractiveBytes = 1 * 1024 * 1024

    private let feedback: FeedbackDisplay
    /// Replacing the running format cancels stale work and keeps an older result from
    /// winning over a newer command or a synchronous small edit.
    private var task: Task<Void, Never>?
    private var generation: UInt = 0

    init(feedback: FeedbackDisplay) {
        self.feedback = feedback
    }

    isolated deinit {
        task?.cancel()
    }

    /// Formats the code editor hosted in `window`, if there is one.
    func formatEditor(in window: NSWindow?, language: Language) {
        guard let textView = Self.editorTextView(in: window) else { return }
        format(textView, language: language)
    }

    /// Formats `textView` through its native edit cycle so the change is undoable.
    /// Returns the asynchronous operation when one was started.
    @discardableResult
    func format(_ textView: NSTextView, language: Language) -> Task<Void, Never>? {
        let original = textView.string
        let byteCount = original.utf8.count
        task?.cancel()
        task = nil
        generation &+= 1
        let current = generation
        guard byteCount <= Self.maxInteractiveBytes else {
            feedback(
                Notifier.failure(String(localized: "Code is too large to format interactively")))
            return nil
        }

        if byteCount > Self.asyncThresholdBytes {
            task = Task(priority: .userInitiated) { [weak self, weak textView] in
                defer {
                    if self?.generation == current { self?.task = nil }
                }
                guard
                    let tidied = try? await CodeFormatter.tidyConcurrently(
                        original, language: language),
                    !Task.isCancelled,
                    let textView,
                    textView.string == original
                else { return }
                Self.apply(tidied, original: original, to: textView)
            }
            return task
        }

        Self.apply(CodeFormatter.tidy(original, language: language), original: original, to: textView)
        return nil
    }

    private static func apply(_ tidied: String, original: String, to textView: NSTextView) {
        guard tidied != original else { return }
        let whole = NSRange(location: 0, length: (original as NSString).length)
        guard textView.shouldChangeText(in: whole, replacementString: tidied) else { return }
        textView.textStorage?.replaceCharacters(in: whole, with: tidied)
        textView.didChangeText()  // fires the delegate → writes back to the document
        textView.undoManager?.setActionName(String(localized: "Format Code"))
    }

    /// The code editor's `NSTextView` in `window`, found by the accessibility identifier
    /// `CodeEditorView` assigns it, so formatting edits the real text view and its undo
    /// stack rather than mutating the model behind its back.
    static func editorTextView(in window: NSWindow?) -> NSTextView? {
        guard let root = window?.contentView else { return nil }
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if let textView = view as? NSTextView,
                textView.accessibilityIdentifier() == "code-editor-text-view"
            {
                return textView
            }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }
}
