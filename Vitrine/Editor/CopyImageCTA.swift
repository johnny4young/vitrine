import SwiftUI
import VitrineRendering

/// Whether the window's Copy button is confirming a copy. Lives outside the editor's
/// state so only the button's label reads it, whichever toolbar density is on screen.
@Observable
final class CopyConfirmation {
    private(set) var isShowing = false

    @ObservationIgnored private var resetTask: Task<Void, Never>?
    @ObservationIgnored private let hold: Duration
    @ObservationIgnored private let sleep: (Duration) async throws -> Void

    /// Holds as long as the HUD reporting the same copy.
    init(
        hold: Duration = CaptureHUD.displayDuration(hasActions: false),
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.hold = hold
        self.sleep = sleep
    }

    /// Any outcome replaces the previous one, so a failure clears an earlier check at once.
    func record(_ outcome: ExportManager.CopyOutcome) {
        resetTask?.cancel()
        resetTask = nil
        isShowing = outcome == .copied
        guard isShowing else { return }
        resetTask = Task { [weak self, hold, sleep] in
            try? await sleep(hold)
            guard !Task.isCancelled else { return }
            self?.isShowing = false
        }
    }
}

/// The Copy button's label. Both states always take part in layout, so the check never
/// resizes the button or shifts the toolbar. VoiceOver keeps the button's own label and
/// hears the confirmation from the HUD's announcement.
struct CopyImageCTALabel: View {
    let confirmation: CopyConfirmation
    let compact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isConfirmed = confirmation.isShowing
        ZStack {
            HStack(spacing: 7) {
                Image(systemName: VitrineCommand.copyImage.systemImageName)
                    .font(.system(size: 12, weight: .semibold))
                if !compact {
                    Text("Copy image")
                }
            }
            .opacity(isConfirmed ? 0 : 1)

            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .opacity(isConfirmed ? 1 : 0)
                .modifier(
                    DecorativeScaleEffect(
                        isActive: !isConfirmed, scale: 0.7, reduceMotion: reduceMotion)
                )
                .accessibilityHidden(true)
        }
        .motionSensitiveAnimation(.easeOut(duration: 0.12), value: isConfirmed)
    }
}
