import VitrineRendering

/// Routes Recents gallery actions to app-owned editor windows without exposing their
/// singleton lifecycle to the SwiftUI gallery.
struct RecentsGalleryNavigation {
    private let presentEditor: () -> Void
    private let loadPrimaryEditor: (SnapshotConfig) -> Void
    private let presentComparisonBoard: ([Capture]) -> Void
    private let presentThemeVariants: (Capture) -> Void

    init(
        presentEditor: @escaping () -> Void,
        loadPrimaryEditor: @escaping (SnapshotConfig) -> Void,
        presentComparisonBoard: @escaping ([Capture]) -> Void,
        presentThemeVariants: @escaping (Capture) -> Void
    ) {
        self.presentEditor = presentEditor
        self.loadPrimaryEditor = loadPrimaryEditor
        self.presentComparisonBoard = presentComparisonBoard
        self.presentThemeVariants = presentThemeVariants
    }

    func showEditor() {
        presentEditor()
    }

    func loadIntoPrimaryEditor(_ config: SnapshotConfig) {
        loadPrimaryEditor(config)
    }

    func showComparisonBoard(_ captures: [Capture]) {
        presentComparisonBoard(captures)
    }

    func showThemeVariants(of capture: Capture) {
        presentThemeVariants(capture)
    }

    static let live = RecentsGalleryNavigation(
        presentEditor: { EditorWindowController.shared.show() },
        loadPrimaryEditor: { EditorWindowController.shared.loadIntoPrimary($0) },
        presentComparisonBoard: { ComparisonBoardWindowController.shared.show(captures: $0) },
        presentThemeVariants: {
            ComparisonBoardWindowController.shared.showThemeVariants(of: $0)
        })

    static let noOp = RecentsGalleryNavigation(
        presentEditor: {},
        loadPrimaryEditor: { _ in },
        presentComparisonBoard: { _ in },
        presentThemeVariants: { _ in })
}
