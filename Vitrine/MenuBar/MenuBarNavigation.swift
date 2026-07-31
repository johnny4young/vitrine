/// Routes menu-bar commands to app-owned windows without exposing their global
/// lifecycles to the SwiftUI panel.
///
/// The status-item controller supplies this value at the composition boundary. Tests
/// can record destinations and editor documents without constructing AppKit windows.
struct MenuBarNavigation {
    enum Destination: CaseIterable, Equatable {
        case recents
        case editor
        case webSnapshot
        case socialCard
        case settings
        case help
        case about
    }

    private let present: (Destination) -> Void
    private let loadPrimaryEditor: (SnapshotConfig) -> Void

    init(
        present: @escaping (Destination) -> Void,
        loadPrimaryEditor: @escaping (SnapshotConfig) -> Void
    ) {
        self.present = present
        self.loadPrimaryEditor = loadPrimaryEditor
    }

    func show(_ destination: Destination) {
        present(destination)
    }

    func loadIntoPrimaryEditor(_ config: SnapshotConfig) {
        loadPrimaryEditor(config)
    }

    static let live = MenuBarNavigation(
        present: { destination in
            switch destination {
            case .recents:
                RecentsGalleryWindowController.shared.show()
            case .editor:
                EditorWindowController.shared.show()
            case .webSnapshot:
                WebSnapshotPresenter.show()
            case .socialCard:
                SocialCardWindowController.shared.show()
            case .settings:
                SettingsWindowManager.shared.show()
            case .help:
                HelpWindowController.shared.show()
            case .about:
                AboutPanel.present()
            }
        },
        loadPrimaryEditor: { EditorWindowController.shared.loadIntoPrimary($0) })

    /// Safe standalone routing for tests that only exercise panel construction.
    static let noOp = MenuBarNavigation(present: { _ in }, loadPrimaryEditor: { _ in })
}
