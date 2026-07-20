import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import Vitrine

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "VitrineMetadataTests-\(UUID().uuidString)")!
}

// MARK: - Value model

@Suite("SnapshotMetadata model")
struct SnapshotMetadataModelTests {
    @Test func defaultsAreEmptyWithNoBadge() {
        let metadata = SnapshotMetadata()
        #expect(metadata.filename == nil)
        #expect(metadata.title == nil)
        #expect(metadata.caption == nil)
        #expect(metadata.showLanguageBadge == false)
        #expect(metadata.isEmpty)
        #expect(metadata.hasText == false)
    }

    @Test func trimsAndCollapsesBlankFieldsToNil() {
        let metadata = SnapshotMetadata(
            filename: "  ContentView.swift  ",
            title: "   ",
            caption: "\n",
            showLanguageBadge: false
        )
        #expect(metadata.filename == "ContentView.swift")
        #expect(metadata.title == nil)
        #expect(metadata.caption == nil)
    }

    @Test func normalizedHelperTreatsEmptyAndWhitespaceAsNil() {
        #expect(SnapshotMetadata.normalized(nil) == nil)
        #expect(SnapshotMetadata.normalized("") == nil)
        #expect(SnapshotMetadata.normalized("   \n ") == nil)
        #expect(SnapshotMetadata.normalized("  hi ") == "hi")
    }

    @Test func isEmptyIsFalseWhenAnyFieldOrBadgeIsSet() {
        #expect(!SnapshotMetadata(filename: "a.swift").isEmpty)
        #expect(!SnapshotMetadata(title: "Title").isEmpty)
        #expect(!SnapshotMetadata(caption: "Caption").isEmpty)
        #expect(!SnapshotMetadata(showLanguageBadge: true).isEmpty)
    }

    @Test func hasTextIgnoresTheBadgeOnlyCase() {
        // A badge with no text fields is not "text"; the header still shows, but
        // only the badge row.
        #expect(SnapshotMetadata(showLanguageBadge: true).hasText == false)
        #expect(SnapshotMetadata(filename: "a.swift").hasText)
    }

    @Test func equatableComparesNormalizedValues() {
        #expect(
            SnapshotMetadata(filename: " a.swift ") == SnapshotMetadata(filename: "a.swift"))
        #expect(
            SnapshotMetadata(title: "A") != SnapshotMetadata(title: "B"))
    }
}

// MARK: - Codable round-trip

@Suite("SnapshotMetadata Codable")
struct SnapshotMetadataCodableTests {
    private func roundTrip(_ metadata: SnapshotMetadata) throws -> SnapshotMetadata {
        let data = try JSONEncoder().encode(metadata)
        return try JSONDecoder().decode(SnapshotMetadata.self, from: data)
    }

    @Test func fullValueRoundTrips() throws {
        let original = SnapshotMetadata(
            filename: "ContentView.swift",
            title: "Aurora gradient",
            caption: "A SwiftUI gradient",
            showLanguageBadge: true
        )
        #expect(try roundTrip(original) == original)
    }

    @Test func emptyValueRoundTrips() throws {
        let original = SnapshotMetadata()
        let decoded = try roundTrip(original)
        #expect(decoded == original)
        #expect(decoded.isEmpty)
    }

    @Test func partialValueRoundTrips() throws {
        let original = SnapshotMetadata(filename: "main.go", showLanguageBadge: true)
        #expect(try roundTrip(original) == original)
    }

    @Test func decodingTolueratesMissingKeys() throws {
        // A blob with no keys decodes to the empty default rather than failing.
        let decoded = try JSONDecoder().decode(SnapshotMetadata.self, from: Data("{}".utf8))
        #expect(decoded == SnapshotMetadata())
    }

    @Test func decodingMissingBadgeDefaultsToFalse() throws {
        let json = #"{"title":"Only a title"}"#
        let decoded = try JSONDecoder().decode(SnapshotMetadata.self, from: Data(json.utf8))
        #expect(decoded.title == "Only a title")
        #expect(decoded.showLanguageBadge == false)
    }

    @Test func decodingReNormalizesPersistedText() throws {
        // A hand-edited blob with untrimmed or empty-but-present strings must not
        // carry that into the renderer; the decoder re-normalizes (defensive behavior).
        let json = #"{"filename":"  a.swift  ","title":"   ","caption":""}"#
        let decoded = try JSONDecoder().decode(SnapshotMetadata.self, from: Data(json.utf8))
        #expect(decoded.filename == "a.swift")
        #expect(decoded.title == nil)
        #expect(decoded.caption == nil)
    }

    @Test func garbageBlobFailsToDecodeCleanly() {
        // Not valid JSON for the type: decoding throws (the caller treats this as
        // "no metadata"), rather than producing a half-populated value.
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(SnapshotMetadata.self, from: Data("not json".utf8))
        }
    }
}

// MARK: - Config integration

@Suite("SnapshotConfig metadata")
struct SnapshotConfigMetadataTests {
    @Test func defaultConfigHasEmptyMetadata() {
        #expect(SnapshotConfig().metadata.isEmpty)
    }

    @Test func equatableReflectsMetadata() {
        var a = SnapshotConfig()
        var b = SnapshotConfig()
        #expect(a == b)
        a.metadata.title = "Title"
        #expect(a != b)
        b.metadata.title = "Title"
        #expect(a == b)
    }
}

// MARK: - Persistence round-trip

@MainActor
@Suite("AppSettings metadata persistence")
struct AppSettingsMetadataPersistenceTests {
    @Test func metadataPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.config.metadata = SnapshotMetadata(
            filename: "ContentView.swift",
            title: "Aurora",
            caption: "A gradient",
            showLanguageBadge: true
        )

        let second = AppSettings(defaults: defaults)
        #expect(second.config.metadata.filename == "ContentView.swift")
        #expect(second.config.metadata.title == "Aurora")
        #expect(second.config.metadata.caption == "A gradient")
        #expect(second.config.metadata.showLanguageBadge == true)
    }

    @Test func emptyMetadataClearsThePersistedKey() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.config.metadata = SnapshotMetadata(title: "Temporary")
        #expect(defaults.data(forKey: "metadata") != nil)

        // Clearing the header back to empty removes the stored blob entirely so a
        // later read restores the empty default rather than a stale value.
        first.config.metadata = SnapshotMetadata()
        #expect(defaults.data(forKey: "metadata") == nil)

        let second = AppSettings(defaults: defaults)
        #expect(second.config.metadata.isEmpty)
    }

    @Test func garbagePersistedMetadataResolvesToEmpty() {
        let defaults = freshDefaults()
        defaults.set(Data("not a metadata blob".utf8), forKey: "metadata")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.config.metadata.isEmpty)
    }

    @Test func resetClearsMetadata() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.config.metadata = SnapshotMetadata(filename: "a.swift", showLanguageBadge: true)
        settings.resetToDefaults()
        #expect(settings.config.metadata.isEmpty)
        #expect(defaults.data(forKey: "metadata") == nil)
    }
}

// MARK: - Badge color

@MainActor
@Suite("Metadata badge color")
struct MetadataBadgeColorTests {
    @Test func badgeColorDiffersBetweenLightAndDarkThemes() {
        let dark = HighlightManager.shared.metadataBadgeColor(for: .oneDark)
        let light = HighlightManager.shared.metadataBadgeColor(for: .github)
        #expect(dark != light)
    }

    @Test func badgeColorIsTranslucentInBothThemes() throws {
        for theme in [Theme.oneDark, Theme.github] {
            let color = HighlightManager.shared.metadataBadgeColor(for: theme)
            let ns = try #require(NSColor(color).usingColorSpace(.sRGB))
            #expect(ns.alphaComponent > 0)
            #expect(ns.alphaComponent < 1)
        }
    }
}

// MARK: - Render smoke (header on/off)

@MainActor
@Suite("Metadata header render")
struct MetadataHeaderRenderTests {
    private func config(metadata: SnapshotMetadata) -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "let answer = 42\nprint(answer)"
        config.metadata = metadata
        return config
    }

    @Test func rendersWithoutHeaderByDefault() throws {
        let image = try #require(
            ExportManager.renderCGImage(config(metadata: SnapshotMetadata()), scale: 1))
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    @Test func rendersWithFullHeader() throws {
        let metadata = SnapshotMetadata(
            filename: "ContentView.swift",
            title: "Aurora gradient",
            caption: "A SwiftUI gradient",
            showLanguageBadge: true
        )
        let image = try #require(ExportManager.renderCGImage(config(metadata: metadata), scale: 1))
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    @Test func headerAddsHeightToTheRender() throws {
        // The header occupies a row above the code, so the same code renders taller
        // with a header than without it.
        let plain = try #require(
            ExportManager.renderCGImage(config(metadata: SnapshotMetadata()), scale: 1))
        let withHeader = try #require(
            ExportManager.renderCGImage(
                config(metadata: SnapshotMetadata(title: "A title", caption: "A caption")), scale: 1
            )
        )
        #expect(withHeader.height > plain.height)
    }

    @Test func badgeOnlyHeaderRendersSuccessfully() throws {
        // A header with only the language badge (no text fields) still renders.
        let metadata = SnapshotMetadata(showLanguageBadge: true)
        let image = try #require(ExportManager.renderCGImage(config(metadata: metadata), scale: 1))
        #expect(image.width > 0)
    }

    @Test func headerRendersAcrossLightAndDarkThemes() throws {
        let metadata = SnapshotMetadata(filename: "main.go", showLanguageBadge: true)
        for theme in [Theme.oneDark, Theme.github, Theme.dracula] {
            var config = config(metadata: metadata)
            config.theme = theme
            let image = try #require(ExportManager.renderCGImage(config, scale: 1))
            #expect(image.width > 0)
        }
    }

    @Test func headerRendersOverTransparentBackground() throws {
        var config = config(metadata: SnapshotMetadata(title: "Over transparency"))
        config.background = .transparent
        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        #expect(image.width > 0)
    }
}
