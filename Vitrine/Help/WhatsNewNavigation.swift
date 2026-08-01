/// Routes release-note actions to app-owned windows without coupling the SwiftUI
/// surface to their reusable controller lifecycles.
struct WhatsNewNavigation {
    private let presentHelp: () -> Void

    init(presentHelp: @escaping () -> Void) {
        self.presentHelp = presentHelp
    }

    func showHelp() {
        presentHelp()
    }

    static let live = WhatsNewNavigation {
        HelpWindowController.shared.show()
    }

    static let noOp = WhatsNewNavigation {}
}
