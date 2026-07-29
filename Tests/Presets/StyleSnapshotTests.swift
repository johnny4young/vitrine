import Testing

@testable import Vitrine

// MARK: - StyleSnapshot capture / apply

@Suite("StyleSnapshot capture and apply")
struct StyleSnapshotTests {
    @Test func captureRecordsPresentationButNeverCodeOrLanguage() {
        var config = SnapshotConfig()
        config.code = "let secret = 42"
        config.language = .python
        config.theme = .monokai
        config.fontName = "Hack"
        config.padding = 40
        config.showChrome = false

        let snapshot = StyleSnapshot(capturing: config)

        // Presentation is captured…
        #expect(snapshot.themeID == "monokai")
        #expect(snapshot.fontName == "Hack")
        #expect(snapshot.padding == 40)
        #expect(snapshot.showChrome == false)
        // …and applying it back reproduces the style without ever touching source.
        var target = SnapshotConfig()
        target.code = "print('keep me')"
        target.language = .swift
        let originalCode = target.code
        let originalLanguage = target.language
        snapshot.apply(to: &target)
        #expect(target.code == originalCode)
        #expect(target.language == originalLanguage)
        #expect(target.theme.id == "monokai")
        #expect(target.fontName == "Hack")
        #expect(target.padding == 40)
        #expect(target.showChrome == false)
    }

    @Test func captureDropsNonPortableImageBackgroundToGradient() {
        var config = SnapshotConfig()
        config.background = .image(ImageBackground(reference: ImageReference(fileName: "x.png")))
        let snapshot = StyleSnapshot(capturing: config)
        // An image references a container file that won't travel with the preset,
        // so it degrades to the signature gradient.
        #expect(snapshot.background == .gradient(.aurora))
    }

    @Test func applyResolvesUnknownThemeAndFontToDefaults() {
        let snapshot = StyleSnapshot(
            themeID: "no-such-theme", fontName: "Comic Sans", background: .gradient(.ocean))
        var config = SnapshotConfig()
        snapshot.apply(to: &config)
        #expect(config.theme.id == Theme.oneDark.id)
        #expect(config.fontName == CodeFont.default)
        // A valid background still applies.
        #expect(config.background == .gradient(.ocean))
    }

    @Test func initClampsOutOfRangeNumbers() {
        let snapshot = StyleSnapshot(
            themeID: Theme.oneDark.id, fontSize: 999, padding: 999, cornerRadius: 999,
            wrapColumns: 999,
            background: .gradient(.aurora))
        #expect(snapshot.fontSize == SettingsDefaults.fontSizeRange.upperBound)
        #expect(snapshot.padding == SettingsDefaults.paddingRange.upperBound)
        #expect(snapshot.cornerRadius == SettingsDefaults.cornerRadiusRange.upperBound)
        #expect(snapshot.wrapColumns == SettingsDefaults.wrapColumnsRange.upperBound)
    }

    @Test func fullInitAlsoDropsNonPortableImageBackground() {
        // The non-`capturing` initializer (used by built-ins and shared files) runs
        // the same portability rule, so a snapshot can never be constructed carrying
        // a container-local image reference.
        let snapshot = StyleSnapshot(
            themeID: Theme.oneDark.id,
            background: .image(ImageBackground(reference: ImageReference(fileName: "x.png"))))
        #expect(snapshot.background == .gradient(.aurora))
    }
}
