import VitrineDomain

extension ExportPreset {
    /// Applies destination guidance without changing the user's source content.
    public func apply(to config: inout SnapshotConfig) {
        config.padding = SettingsDefaults.clampPadding(padding)
        if let background {
            config.background = background
        }
    }

    /// Whether the app render configuration matches this preset's presentation values.
    public func matches(_ config: SnapshotConfig) -> Bool {
        guard config.padding == SettingsDefaults.clampPadding(padding) else { return false }
        if let background, config.background != background { return false }
        return true
    }
}
