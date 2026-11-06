import Foundation

/// Presents transient in-app feedback without exposing the window-owning HUD
/// controller to coordinators or views.
///
/// The live adapter is the only place this operation reaches the reusable AppKit HUD.
/// Tests can substitute a recording closure without constructing a window.
struct FeedbackDisplay {
    private let perform:
        (
            Notifier.CaptureFeedback,
            @escaping (Notifier.RecoveryAction) -> Void
        ) -> Void
    private let presentPreview: (CopyPreview.Item) -> Void

    init(
        _ perform:
            @escaping (
                Notifier.CaptureFeedback,
                @escaping (Notifier.RecoveryAction) -> Void
            ) -> Void,
        preview: @escaping (CopyPreview.Item) -> Void = { _ in }
    ) {
        self.perform = perform
        self.presentPreview = preview
    }

    func callAsFunction(
        _ feedback: Notifier.CaptureFeedback,
        onAction: @escaping (Notifier.RecoveryAction) -> Void = { _ in }
    ) {
        perform(feedback, onAction)
    }

    /// Floats the copied PNG when `behavior` allows it; `reopen` runs on a click.
    func preview(
        _ png: Data?, behavior: OutputBehavior, reopen: @escaping () -> Void
    ) {
        guard let png, CopyPreview.isShown(for: behavior) else { return }
        presentPreview(CopyPreview.Item(png: png, reopen: reopen))
    }

    static let live = FeedbackDisplay(
        { feedback, onAction in
            CaptureHUDController.shared.present(feedback, onAction: onAction)
        },
        preview: { CopyPreviewController.shared.present($0) })

    static let noOp = FeedbackDisplay { _, _ in }
}
