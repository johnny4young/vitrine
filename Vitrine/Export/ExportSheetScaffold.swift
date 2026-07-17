import SwiftUI

/// The shared chrome behind the export sheets (analysis §3.2.5).
///
/// The multi-size and carousel sheets are the same shape: a bold title over a subtitle,
/// a body of choices, an optional red failure note, and a footer of Cancel · live
/// progress · a prominent confirm button — all on a fixed-width window surface. They
/// were built twice, and the divergence already bit: the SwiftUI identifier-clobbering
/// fix (`.accessibilityElement(children: .contain)` before the root id) had to be
/// applied to *both* sheets and the paywall separately. This scaffold owns that chrome
/// once so a third export surface — and any future fix to the shared parts — lands in
/// one place; each sheet supplies only its distinct body and its action wiring.
///
/// The accessibility identifiers are passed in per sheet rather than derived, so the
/// existing UI tests keep addressing the exact ids they always have.
struct ExportSheetScaffold<Body: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    /// The sheet's fixed width — the one dimension the two sheets don't share.
    let width: CGFloat
    /// The root accessibility id; applied with `.contain` so the body's own ids survive.
    let rootIdentifier: String

    /// A short failure message shown in red above the footer, or `nil` when the last
    /// action succeeded (or none has run).
    let failureNote: String?

    /// Live "completed/total" while an export runs; `nil` when idle.
    let progress: (completed: Int, total: Int)?
    /// The accessibility id for the progress indicator, or `nil` to leave it untagged
    /// (the carousel sheet never tagged its progress; the multi-size sheet did).
    let progressIdentifier: String?

    let cancelIdentifier: String
    let cancelDisabled: Bool
    let onCancel: () -> Void

    let confirmTitle: LocalizedStringKey
    let confirmIdentifier: String
    let confirmDisabled: Bool
    let onConfirm: () -> Void

    /// The sheet's distinct body — the stepper, the preset list — between the header
    /// and the failure note.
    @ViewBuilder let content: () -> Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: VitrineTokens.FontSize.headline, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.primary)
                Text(subtitle)
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
            }

            content()

            if let failureNote {
                Text(verbatim: failureNote)
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(24)
        .frame(width: width)
        .background(VitrineTokens.Surface.window)
        // A plain VStack is not an accessibility element, so an id put directly on it
        // propagates down and clobbers every child's id. `.contain` makes the root a
        // real container element so the body keeps its own ids (root-caused in the
        // UI-test workflow notes; the reason this chrome is shared).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(rootIdentifier)
    }

    private var footer: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .disabled(cancelDisabled)
                .accessibilityIdentifier(cancelIdentifier)
            Spacer()
            if let progress {
                let indicator = HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: "\(progress.completed)/\(progress.total)")
                        .font(.system(size: VitrineTokens.FontSize.caption))
                        .foregroundStyle(VitrineTokens.Text.secondary)
                        .monospacedDigit()
                }
                if let progressIdentifier {
                    indicator.accessibilityIdentifier(progressIdentifier)
                } else {
                    indicator
                }
            }
            Button(confirmTitle, action: onConfirm)
                .buttonStyle(.borderedProminent)
                .disabled(confirmDisabled)
                .accessibilityIdentifier(confirmIdentifier)
        }
    }
}
