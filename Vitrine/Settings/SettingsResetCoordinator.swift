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

    func reset() {
        settings.resetToDefaults()
        presets.reload()
        themes.reload()
        brandKit.reload()
        workspaceRecipes.reload()
    }
}
