extension StylePreset {
    /// Builds a user preset from the app render configuration.
    static func capturing(_ config: SnapshotConfig, name: String) -> StylePreset {
        StylePreset(name: name, style: StyleSnapshot(capturing: config))
    }

    /// Returns the next curated built-in style for a deterministic visual refresh.
    static func surprise(after config: SnapshotConfig) -> StylePreset {
        let current = StyleSnapshot(capturing: config)
        guard let index = builtIns.firstIndex(where: { $0.style == current }) else {
            return .sunset
        }
        return builtIns[(index + 1) % builtIns.count]
    }
}
