/// Routes Recents gallery actions to app-owned editor windows without exposing their
/// singleton lifecycle to the SwiftUI gallery.
struct RecentsGalleryNavigation {
    private let presentEditor: () -> Void
    private let loadPrimaryEditor: (SnapshotConfig) -> Void

    init(
        presentEditor: @escaping () -> Void,
        loadPrimaryEditor: @escaping (SnapshotConfig) -> Void
    ) {
        self.presentEditor = presentEditor
        self.loadPrimaryEditor = loadPrimaryEditor
    }

    func showEditor() {
        presentEditor()
    }

    func loadIntoPrimaryEditor(_ config: SnapshotConfig) {
        loadPrimaryEditor(config)
    }

    static let live = RecentsGalleryNavigation(
        presentEditor: { EditorWindowController.shared.show() },
        loadPrimaryEditor: { EditorWindowController.shared.loadIntoPrimary($0) })

    static let noOp = RecentsGalleryNavigation(
        presentEditor: {},
        loadPrimaryEditor: { _ in })
}
