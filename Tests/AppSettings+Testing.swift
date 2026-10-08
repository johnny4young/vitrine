import Foundation
import VitrineRendering

@testable import Vitrine

extension AppSettings {
    /// Settings over `defaults` with their own Brand Kit and a locked entitlement, so a
    /// test never reads the host app's stores.
    convenience init(defaults: UserDefaults) {
        self.init(
            defaults: defaults,
            brandKit: BrandKitStore(defaults: defaults),
            entitlements: Entitlements(provider: FreeProvider()))
    }
}

extension EditorWindowState {
    /// Restores with an isolated, empty custom-theme store.
    func config() -> SnapshotConfig {
        config(themes: CustomThemeStore(defaults: testDefaults()))
    }
}
