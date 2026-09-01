import Foundation

extension StyleSnapshot {
    /// Captures the portable style half of an app render configuration.
    init(capturing config: SnapshotConfig) {
        self.init(
            themeID: config.theme.id,
            fontName: config.fontName,
            fontSize: config.fontSize,
            fontLigatures: config.fontLigatures,
            padding: config.padding,
            cornerRadius: config.cornerRadius,
            showChrome: config.showChrome,
            showShadow: config.showShadow,
            shadowRadius: config.shadowRadius,
            showLineNumbers: config.showLineNumbers,
            wrapColumns: config.wrapColumns,
            background: config.background
        )
    }

    /// Applies this portable style to the app render configuration without touching content.
    func apply(
        to config: inout SnapshotConfig,
        resolvingThemeWith resolveTheme: (String) -> Theme = Theme.theme(withID:)
    ) {
        config.theme = resolveTheme(themeID)
        config.fontName = CodeFont.all.contains(fontName) ? fontName : CodeFont.default
        config.fontSize = SettingsDefaults.clampFontSize(fontSize)
        config.fontLigatures = fontLigatures
        config.padding = SettingsDefaults.clampPadding(padding)
        config.cornerRadius = SettingsDefaults.clampCornerRadius(cornerRadius)
        config.showChrome = showChrome
        config.showShadow = showShadow
        config.shadowRadius = SettingsDefaults.clampShadowRadius(shadowRadius)
        config.showLineNumbers = showLineNumbers
        config.wrapColumns = wrapColumns.map(SettingsDefaults.clampWrapColumns)
        config.background = background
    }
}
