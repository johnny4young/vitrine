import AppKit
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Documentation package contracts")
struct DocumentationPackageTests {
    private func config() throws -> SnapshotConfig {
        var config = SnapshotConfig(
            code: "let value = \"safe\"\nPRIVATE_REDACTED_SENTINEL\n", language: .swift)
        config.redactedLineRanges = [2...2]
        config.altText = try SnapshotAltText.normalized("Description [x] <&> \"quoted\"\nUnicode 👩🏽‍💻")
        return config
    }

    @Test func selectionAndSafeSourceDriveEveryRepresentation() throws {
        let config = try config()
        let png = Data([1, 2, 3])
        let package = DocumentationPackage(
            config: config, png: png, representations: Set(DocumentationRepresentation.allCases))
        #expect(Set(package.files.keys) == ["image.png", "README.md", "index.html", "source.txt"])
        #expect(package.files["image.png"] == png)
        for name in ["README.md", "index.html", "source.txt"] {
            let text = String(decoding: try #require(package.files[name]), as: UTF8.self)
            #expect(!text.contains("PRIVATE_REDACTED_SENTINEL"))
            #expect(text.contains("[redacted]"))
        }
        let html = String(decoding: package.files["index.html"]!, as: UTF8.self)
        #expect(html.contains("&lt;&amp;&gt; &quot;quoted&quot;"))
        #expect(!html.contains("<script"))
        #expect(!html.contains("data:image"))
        let markdown = String(decoding: package.files["README.md"]!, as: UTF8.self)
        #expect(markdown.contains("](image.png)"))
        #expect(markdown.contains("\\[x\\]"))
        #expect(
            DocumentationPackage(config: config, png: png, representations: []).files.count == 1)
    }

    @Test func multilineDescriptionsAndMarkupCannotBreakOutOfImageAttributes() throws {
        var config = SnapshotConfig(code: "let fence = \"```\"", language: .swift)
        config.altText = try SnapshotAltText.normalized(
            "[label] \"quoted\"\r\n<script>alert(1)</script> & Unicode 👩🏽‍💻")
        let markdown = MarkdownExport.document(for: config, imageSource: "image.png")
        #expect(markdown.hasPrefix("![\\[label\\] \"quoted\" \\<script\\>"))
        #expect(!markdown.contains("\r"))
        #expect(markdown.contains("````swift"))
        let html = HTMLExport.document(for: config, imageSource: "image.png")
        #expect(html.contains("&quot;quoted&quot; &lt;script&gt;"))
        #expect(!html.contains("<script>"))
    }

    @Test func terminalUsesFinalScreenIncludingCursorScrollWrappingAndUnicode() throws {
        let esc = "\u{1B}"
        let inputs = [
            "PRIVATE_HIDDEN_SENTINEL\(esc)[1G\(esc)[2Ksafe 👩🏽‍💻",
            "PRIVATE_HIDDEN_SENTINEL\rsafe\(esc)[K",
            "PRIVATE_HIDDEN_SENTINEL\(esc)[?1049hsafe\(esc)[?1049l\(esc)[2Jsafe",
            "PRIVATE_HIDDEN_SENTINEL\(esc)[2J\(esc)[Hsafe\n界界界界\(esc)[1;1Hsafe",
        ]
        for input in inputs {
            var config = SnapshotConfig(code: input, language: .terminal)
            config.terminalColumns = 8
            let safe = config.sidecarText
            let package = DocumentationPackage(
                config: config, png: Data(),
                representations: Set(DocumentationRepresentation.allCases))
            #expect(String(decoding: package.files["source.txt"]!, as: UTF8.self) == safe)
            for name in ["README.md", "index.html", "source.txt"] {
                #expect(
                    !String(decoding: package.files[name]!, as: UTF8.self).contains(
                        "PRIVATE_HIDDEN_SENTINEL"))
            }
        }
    }

    @Test func importedImageCannotCarryResidualSourceOrEmptyCodeFences() throws {
        var config = try config()
        config.foregroundImage = ImageReference(fileName: "test.png")
        let package = DocumentationPackage(
            config: config, png: Data(), representations: Set(DocumentationRepresentation.allCases))
        #expect(package.files["source.txt"] == nil)
        #expect(!String(decoding: package.files["README.md"]!, as: UTF8.self).contains("```"))
        #expect(!String(decoding: package.files["index.html"]!, as: UTF8.self).contains("<pre>"))
    }

    @Test func descriptionsDoNotChangeRenderGeometryOrPixels() throws {
        var plain = SnapshotConfig(code: "let answer = 42", language: .swift)
        let before = try #require(ExportManager.renderCGImage(plain, scale: 1))
        plain.altText = try SnapshotAltText.normalized("The answer is assigned to a constant.")
        let after = try #require(ExportManager.renderCGImage(plain, scale: 1))
        #expect(before.width == after.width)
        #expect(before.height == after.height)
        #expect(ExportManager.pngData(from: before) == ExportManager.pngData(from: after))
    }

    @Test func contentReplacementClearsDescriptionButSharedLinksRestoreIt() throws {
        let config = try config()
        #expect(config.replacingContent(with: "new").altText == nil)
        var reopened = SnapshotConfig()
        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: config))
        try SnapshotShareLink.snapshot(from: url).apply(to: &reopened)
        #expect(reopened.altText == config.altText)
        #expect(!reopened.code.contains("PRIVATE_REDACTED_SENTINEL"))
        let encoded = try JSONEncoder().encode(SharedSnapshot(capturing: config))
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "altText")
        let old = try JSONDecoder().decode(
            SharedSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        old.apply(to: &reopened)
        #expect(reopened.altText == nil)
        let restoredCode = reopened.code
        for invalid: Any in [42, String(repeating: "a", count: 1_025)] {
            legacy["altText"] = invalid
            let decoded = try JSONDecoder().decode(
                SharedSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
            reopened.altText = config.altText
            decoded.apply(to: &reopened)
            #expect(reopened.altText == nil)
            #expect(reopened.code == restoredCode)
        }
    }

    @Test func descriptionNeverBecomesARecipeOrDefaultAndWindowsStayIndependent() throws {
        let defaults = testDefaults()
        let kit = BrandKitStore(defaults: testDefaults())
        let entitlement = Entitlements(provider: FreeProvider())
        let app = AppSettings(defaults: defaults, brandKit: kit, entitlements: entitlement)
        let first = AppSettings.makeEditorSession(
            seededFrom: defaults, sharing: app.outputBehavior,
            brandKit: BrandKitStore(defaults: testDefaults()),
            entitlements: Entitlements(provider: FreeProvider()))
        let second = AppSettings.makeEditorSession(
            seededFrom: defaults, sharing: app.outputBehavior,
            brandKit: BrandKitStore(defaults: testDefaults()),
            entitlements: Entitlements(provider: FreeProvider()))
        first.config.altText = try SnapshotAltText.normalized("First document only")
        #expect(second.config.altText == nil)
        app.makeDefault(from: first)
        #expect(app.config.altText == nil)
        #expect(
            AppSettings(defaults: defaults, brandKit: kit, entitlements: entitlement).config.altText
                == nil)
        let recipe = first.workspaceRecipe(named: "Example")
        #expect(
            !String(decoding: try JSONEncoder().encode(recipe), as: UTF8.self).contains(
                "First document only"))
    }
}
