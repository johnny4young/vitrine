/// Presents capture feedback without exposing the window-owning HUD controller to the
/// feedback coordinator.
///
/// The live adapter remains the only place this operation reaches the reusable AppKit
/// HUD. Tests can substitute a recording closure and exercise feedback/action routing
/// without creating a window.
struct CaptureFeedbackDisplay {
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

    static let live = CaptureFeedbackDisplay { feedback, onAction in
        CaptureHUDController.shared.present(feedback, onAction: onAction)
    }
}

/// Routes recovery actions to app-owned windows without coupling the feedback
/// coordinator to their singleton lifecycles.
///
/// This value describes only the three operations recovery needs. The live adapter
/// owns the AppKit/WebKit bridge, while tests inject recording closures and prove the
/// coordinator's behavior deterministically.
struct CaptureRecoveryRouting {
    private let loadPrimaryEditor: (SnapshotConfig) -> Void
    private let presentEditor: () -> Void
    private let presentWebSnapshot: (String?) -> Void

    init(
        loadPrimaryEditor: @escaping (SnapshotConfig) -> Void,
        presentEditor: @escaping () -> Void,
        presentWebSnapshot: @escaping (String?) -> Void
    ) {
        self.loadPrimaryEditor = loadPrimaryEditor
        self.presentEditor = presentEditor
        self.presentWebSnapshot = presentWebSnapshot
    }

    func loadIntoPrimaryEditor(_ config: SnapshotConfig) {
        loadPrimaryEditor(config)
    }

    func showEditor() {
        presentEditor()
    }

    func showWebSnapshot(prefillURL: String? = nil) {
        presentWebSnapshot(prefillURL)
    }

    static let live = CaptureRecoveryRouting(
        loadPrimaryEditor: { EditorWindowController.shared.loadIntoPrimary($0) },
        presentEditor: { EditorWindowController.shared.show() },
        presentWebSnapshot: { WebSnapshotPresenter.show(prefillURL: $0) })
}
