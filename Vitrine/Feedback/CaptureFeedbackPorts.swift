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
