import AppKit
import SwiftUI
import VitrineDomain
import VitrineRendering

/// What a capture's code steps may hold. The editor edits the active step: a step change
/// saves the text back into it before loading the next one.
enum CodeStepRules {
    static let limit = 20

    /// Redactions and blur boxes cover one state of the code, so a step could show what
    /// they hide elsewhere. Captures that have them keep a single state.
    static func isAvailable(for style: SnapshotConfig) -> Bool {
        !style.usesImageContent && style.language != .terminal
            && style.redactedLineRanges.isEmpty && !style.annotations.contains { $0.kind == .blur }
    }

    /// A pasted document drops marks placed over the old content, but pasting the next
    /// version is how steps are built, so they stay.
    static func pastingDocument(over style: SnapshotConfig, language: Language) -> SnapshotConfig {
        var pasted = style
        pasted.resetForNewContent()
        pasted.codeSteps = style.codeSteps
        pasted.activeCodeStep = style.activeCodeStep
        pasted.language = language
        return pasted
    }

    /// Appends `code` as the active step, unless a step can't hold it.
    static func adding(_ code: String, to style: inout SnapshotConfig) -> Bool {
        guard isAvailable(for: style), !code.isEmpty, style.codeSteps.count < limit,
            SecretScanner.scan(code).isEmpty
        else { return false }
        style.codeSteps.append(code)
        style.activeCodeStep = style.codeSteps.count - 1
        return true
    }

    /// Saves `draft` into the active step and returns the code of step `index`.
    static func showing(_ index: Int, draft: String, in style: inout SnapshotConfig) -> String? {
        guard isAvailable(for: style), style.codeSteps.indices.contains(index),
            SecretScanner.scan(draft).isEmpty
        else { return nil }
        if let active = style.activeCodeStep, style.codeSteps.indices.contains(active) {
            style.codeSteps[active] = draft
        }
        style.activeCodeStep = index
        return style.codeSteps[index]
    }

    /// Removes the active step, or the last one, and returns the code to load in its place:
    /// none when steps are unavailable, since loading would move redactions off their lines.
    static func removing(from style: inout SnapshotConfig) -> String? {
        guard let index = style.activeCodeStep ?? style.codeSteps.indices.last,
            style.codeSteps.indices.contains(index)
        else { return nil }
        style.codeSteps.remove(at: index)
        guard isAvailable(for: style), !style.codeSteps.isEmpty else {
            style.activeCodeStep = nil
            return nil
        }
        style.activeCodeStep = min(index, style.codeSteps.count - 1)
        return style.codeSteps[style.activeCodeStep ?? 0]
    }
}

/// Commits a step change as one undoable edit: the steps, and the editor text through the
/// text view's own edit cycle, so typing undo survives.
struct CodeStepEditor {
    let settings: AppSettings
    let textView: NSTextView?
    let undoManager: UndoManager?

    func commit(_ style: SnapshotConfig, text: String?, actionName: String) {
        Self.setSteps(style, in: settings, undoManager: undoManager)
        if let text, text != settings.documentCode {
            if let textView {
                let whole = NSRange(location: 0, length: (textView.string as NSString).length)
                textView.breakUndoCoalescing()
                if textView.shouldChangeText(in: whole, replacementString: text) {
                    textView.textStorage?.replaceCharacters(in: whole, with: text)
                    textView.didChangeText()
                }
            }
            settings.documentCode = text
        }
        undoManager?.setActionName(actionName)
    }

    private static func setSteps(
        _ style: SnapshotConfig, in settings: AppSettings, undoManager: UndoManager?
    ) {
        let current = settings.style
        undoManager?.registerUndo(withTarget: settings) { settings in
            setSteps(current, in: settings, undoManager: undoManager)
        }
        var next = settings.style
        next.codeSteps = style.codeSteps
        next.activeCodeStep = style.activeCodeStep
        settings.style = next
    }
}

extension EditorView {
    var codeStepsAvailable: Bool { CodeStepRules.isAvailable(for: settings.style) }

    private var codeStepEditor: CodeStepEditor {
        let textView = CodeFormatOperation.editorTextView(in: editorWindow.value)
        return CodeStepEditor(
            settings: settings, textView: textView,
            undoManager: textView?.undoManager ?? undoManager)
    }

    var addCodeStepButton: some View {
        Button(action: addCodeStep) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VitrineTokens.Text.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(
            codeStepsAvailable
                ? "Add the current code as a step."
                : "Steps can't be used with redactions, blur boxes, terminal output or images."
        )
        .accessibilityLabel("Add Step")
        .accessibilityIdentifier("code-step-add")
        .disabled(
            settings.documentIsEmpty || !codeStepsAvailable
                || settings.style.codeSteps.count >= CodeStepRules.limit)
    }

    /// One chip per step. Removing stays possible when steps are otherwise off.
    var codeStepStrip: some View {
        let steps = settings.style.codeSteps.indices
        return HStack(spacing: VitrineTokens.Spacing.xs) {
            TokenSegmentedPicker(
                options: steps.map { (value: $0, label: Text(verbatim: "\($0 + 1)")) },
                selection: Binding(
                    // A closure, not the method itself: Xcode 26.6 crashes building that thunk.
                    get: { settings.style.activeCodeStep ?? -1 }, set: { showCodeStep($0) }),
                optionIdentifiers: steps.map { "code-step-\($0 + 1)" }
            )
            .accessibilityLabel("Code Steps")
            .accessibilityIdentifier("code-steps")
            .disabled(!codeStepsAvailable)
            Spacer(minLength: 0)
            Button(action: removeCodeStep) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove Step")
            .accessibilityLabel("Remove Step")
            .accessibilityIdentifier("code-step-remove")
        }
    }

    func addCodeStep() {
        var style = settings.style
        guard CodeStepRules.adding(settings.documentCode, to: &style) else {
            refuseSecret(in: settings.documentCode)
            return
        }
        codeStepEditor.commit(style, text: nil, actionName: String(localized: "Add Step"))
    }

    func removeCodeStep() {
        var style = settings.style
        guard !style.codeSteps.isEmpty else { return }
        let next = CodeStepRules.removing(from: &style)
        changeCodeStep(to: style, text: next, actionName: String(localized: "Remove Step"))
    }

    func showCodeStep(_ index: Int) {
        guard index != settings.style.activeCodeStep else { return }
        let draft = settings.documentCode
        var style = settings.style
        guard let target = CodeStepRules.showing(index, draft: draft, in: &style) else {
            refuseSecret(in: draft)
            return
        }
        changeCodeStep(to: style, text: target, actionName: String(localized: "Show Step"))
    }

    private func refuseSecret(in code: String) {
        guard !SecretScanner.scan(code).isEmpty else { return }
        session.feedback(Notifier.failure(String(localized: "Steps can't hold a secret.")))
    }

    /// Commits the change and plays it: tokens move, or the canvases cross-fade under
    /// Reduce Motion and wherever tokens can't be paired.
    private func changeCodeStep(to style: SnapshotConfig, text: String?, actionName: String) {
        let shown = stagedPreviewCode ?? settings.documentCode
        // The step change is the only motion; the chip's own must not resize the card.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            codeStepEditor.commit(style, text: text, actionName: actionName)
            guard let text, text != shown else { return }
            stagedPreviewCode = text
            let font = CodeFont.resolved(
                family: style.fontName, size: style.fontSize, ligatures: style.fontLigatures)
            codeStepAnimation =
                reduceMotion
                ? nil
                : CodeStepAnimation(
                    id: (codeStepAnimation?.id ?? 0) + 1, from: shown, to: text,
                    language: style.language, theme: style.theme, font: font)
            guard let animation = codeStepAnimation else {
                codeStepFade += 1
                return
            }
            Task {
                try? await Task.sleep(for: .seconds(CodeStepAnimation.duration))
                if codeStepAnimation?.id == animation.id { codeStepAnimation = nil }
            }
        }
    }
}
