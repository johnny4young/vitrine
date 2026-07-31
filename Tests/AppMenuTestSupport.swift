import Foundation

@testable import Vitrine

@MainActor
func makeIsolatedAppMenu() -> AppMenu {
    let defaults = UserDefaults(
        suiteName: "VitrineAppMenuTests-\(UUID().uuidString)")!
    return AppMenu(
        environment: AppEnvironment(defaults: defaults),
        feedback: CaptureFeedbackPresenter())
}
