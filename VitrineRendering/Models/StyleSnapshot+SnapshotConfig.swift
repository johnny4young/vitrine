import Foundation
import VitrineDomain

extension StyleSnapshot {
    /// Captures the portable style half of an app render configuration.
    public init(capturing config: SnapshotConfig) {
        self.init(
            themeID: config.theme.id,
            fontName: config.fontName,
            fontSize: config.fontSize,
            fontLigatures: config.fontLigatures,
            padding: config.padding,
            paddingMode: config.paddingMode,
            cornerRadius: config.cornerRadius,
            showChrome: config.showChrome,
            showShadow: config.showShadow,
            shadowRadius: config.shadowRadius,
            showLineNumbers: config.showLineNumbers,
            wrapColumns: config.wrapColumns,
            // A non-terminal document doesn't show these, so its preset must not carry them.
            terminalPalette: config.language == .terminal ? config.terminalPalette : nil,
            terminalCursor: config.language == .terminal ? config.terminalCursor : nil,
            background: config.background
        )
    }

    /// Applies this portable style to the app render configuration without touching content.
    public func apply(
        to config: inout SnapshotConfig,
        resolvingThemeWith resolveTheme: (String) -> Theme = Theme.theme(withID:)
    ) {
        config.theme = resolveTheme(themeID)
        config.fontName = CodeFont.all.contains(fontName) ? fontName : CodeFont.default
        config.fontSize = SettingsDefaults.clampFontSize(fontSize)
        config.fontLigatures = fontLigatures
        config.padding = SettingsDefaults.clampPadding(padding)
        if !config.locksPaddingMode { config.paddingMode = paddingMode ?? .manual }
        config.cornerRadius = SettingsDefaults.clampCornerRadius(cornerRadius)
        config.showChrome = showChrome
        config.showShadow = showShadow
        config.shadowRadius = SettingsDefaults.clampShadowRadius(shadowRadius)
        config.showLineNumbers = showLineNumbers
        config.wrapColumns = wrapColumns.map(SettingsDefaults.clampWrapColumns)
        config.terminalPalette = terminalPalette ?? .theme
        config.terminalCursor = terminalCursor ?? .hidden
        config.background = background
    }
}
