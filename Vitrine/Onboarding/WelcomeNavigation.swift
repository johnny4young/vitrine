/// Routes first-run actions to app-owned windows without coupling the SwiftUI
/// onboarding surface to their reusable controller lifecycles.
struct WelcomeNavigation {
    private let presentSampleEditor: () -> Void

    init(presentSampleEditor: @escaping () -> Void) {
        self.presentSampleEditor = presentSampleEditor
    }

    func showSampleEditor() {
        presentSampleEditor()
    }

    static let live = WelcomeNavigation {
        EditorWindowController.shared.showWithSample()
    }

    static let noOp = WelcomeNavigation {}
}
