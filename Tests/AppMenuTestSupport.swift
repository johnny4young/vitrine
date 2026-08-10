import Foundation

@testable import Vitrine

@MainActor
func makeIsolatedAppMenu() -> AppMenu {
    let defaults = testDefaults()
    return AppMenu(
        environment: AppEnvironment(defaults: defaults),
        feedback: CaptureFeedbackPresenter(),
        editorPresentation: .noOp)
}
