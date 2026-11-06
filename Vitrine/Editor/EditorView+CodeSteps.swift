import SwiftUI
import VitrineDomain
import VitrineRendering

/// What a capture's code steps may hold, apart from the views that drive them.
enum CodeStepRules {
    static let limit = 20

    /// Redactions and blur boxes cover one state of the code, so a step could show what
    /// they hide elsewhere. Captures that have them keep a single state.
    static func isAvailable(for style: SnapshotConfig) -> Bool {
        !style.usesImageContent && style.language != .terminal
            && style.redactedLineRanges.isEmpty && !style.annotations.contains { $0.kind == .blur }
    }

    /// The index the code was stored at, or `nil` when a step can't hold it.
    static func adding(_ code: String, to style: inout SnapshotConfig) -> Int? {
        guard isAvailable(for: style), !code.isEmpty, style.codeSteps.count < limit,
            SecretScanner.scan(code).isEmpty
        else { return nil }
        style.codeSteps.append(code)
        return style.codeSteps.count - 1
    }
}

extension EditorView {
    var codeStepsAvailable: Bool { CodeStepRules.isAvailable(for: settings.style) }

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
                : "Steps can't be used with redactions, blur boxes or terminal output."
        )
        .accessibilityLabel("Add Step")
        .accessibilityIdentifier("code-step-add")
        .disabled(
            settings.documentIsEmpty || !codeStepsAvailable
                || settings.style.codeSteps.count >= CodeStepRules.limit)
    }

    /// One chip per step; choosing one animates the stage to it and loads it for editing.
    var codeStepStrip: some View {
        let steps = settings.style.codeSteps.indices
        return HStack(spacing: VitrineTokens.Spacing.xs) {
            TokenSegmentedPicker(
                options: steps.map { (value: $0, label: Text(verbatim: "\($0 + 1)")) },
                selection: Binding(get: { activeCodeStep ?? -1 }, set: showCodeStep),
                optionIdentifiers: steps.map { "code-step-\($0 + 1)" }
            )
            .accessibilityLabel("Code Steps")
            .accessibilityIdentifier("code-steps")
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
            .disabled(activeCodeStep.map(settings.style.codeSteps.indices.contains) != true)
        }
        .disabled(!codeStepsAvailable)
    }

    func addCodeStep() {
        let code = settings.documentCode
        guard let index = CodeStepRules.adding(code, to: &settings.style) else {
            if !SecretScanner.scan(code).isEmpty {
                session.feedback(
                    Notifier.failure(
                        String(localized: "This code has a secret. Steps can't redact it yet.")))
            }
            return
        }
        activeCodeStep = index
    }

    func removeCodeStep() {
        guard let index = activeCodeStep, settings.style.codeSteps.indices.contains(index) else {
            return
        }
        settings.style.codeSteps.remove(at: index)
        let count = settings.style.codeSteps.count
        activeCodeStep = count == 0 ? nil : min(index, count - 1)
    }

    func showCodeStep(_ index: Int) {
        let steps = settings.style.codeSteps
        guard steps.indices.contains(index), codeStepsAvailable else { return }
        activeCodeStep = index
        let target = steps[index]
        let shown = stagedPreviewCode ?? settings.documentCode
        guard target != shown || target != settings.documentCode else { return }
        let animation = CodeStepAnimation(
            id: (codeStepAnimation?.id ?? 0) + 1, from: shown, to: target, moves: !reduceMotion)
        // The animation is the only motion; the segmented control's own must not resize the card.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            codeStepAnimation = animation
            stagedPreviewCode = target
            settings.documentCode = target
        }
        guard let animation else { return }
        Task {
            try? await Task.sleep(for: .seconds(CodeStepAnimation.duration))
            if codeStepAnimation?.id == animation.id { codeStepAnimation = nil }
        }
    }
}
