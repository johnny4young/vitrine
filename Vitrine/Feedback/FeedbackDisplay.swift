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

    init(
        _ perform:
            @escaping (
                Notifier.CaptureFeedback,
                @escaping (Notifier.RecoveryAction) -> Void
            ) -> Void
    ) {
        self.perform = perform
    }

    func callAsFunction(
        _ feedback: Notifier.CaptureFeedback,
        onAction: @escaping (Notifier.RecoveryAction) -> Void = { _ in }
    ) {
        perform(feedback, onAction)
    }

    static let live = FeedbackDisplay { feedback, onAction in
        CaptureHUDController.shared.present(feedback, onAction: onAction)
    }

    static let noOp = FeedbackDisplay { _, _ in }
}
