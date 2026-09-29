/// Coordinates a full settings reset across the central defaults owner and the
/// observable catalogs that cache values from that defaults suite.
///
/// `AppSettings.resetToDefaults()` clears every persisted key and resets its own
/// live state. The independent stores then reload rather than writing empty values
/// themselves, keeping persistence ownership centralized while updating every
/// open settings surface immediately.
struct SettingsResetCoordinator {
    let settings: AppSettings
    let presets: PresetStore
    let themes: CustomThemeStore
    let brandKit: BrandKitStore
    let workspaceRecipes: WorkspaceRecipeStore
    /// Reset turns off saved sessions and localhost access, so an open sign-in window
    /// must not keep browsing under the previous policy.
    var closeWebSignIn: () -> Void = { WebSessionWindowController.shared.close() }

    func reset() {
        settings.resetToDefaults()
        closeWebSignIn()
        presets.reload()
        themes.reload()
        brandKit.reload()
        workspaceRecipes.reload()
    }
}
