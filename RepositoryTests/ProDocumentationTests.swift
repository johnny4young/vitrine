import Foundation
import Testing

/// Keeps the monetization explanation aligned with the executable entitlement lifecycle.
/// The end-to-end behavior is covered elsewhere; this suite prevents a completed capability
/// from being documented as missing or the old process-global wiring from reappearing in samples.
@Suite("PRO architecture documentation")
struct ProDocumentationTests {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func proDocumentation() throws -> String {
        let documentation = try text("docs/PRO.md")
        return documentation.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func text(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8)
    }

    @Test func documentsTheInjectedEntitlementAndWatermarkGraph() throws {
        let documentation = try Self.proDocumentation()

        #expect(documentation.contains("`AppEnvironment` owns the app-wide `Entitlements`"))
        #expect(
            documentation.contains(
                "brandKit.resolvedWatermark(isPro: entitlements.isPro)"))
        #expect(
            documentation.contains(
                "environment.entitlements.isUnlocked(.automation)"))
        #expect(
            documentation.contains(
                "BrandKitStore.shared.resolvedWatermark(isPro: Entitlements.shared.isPro)")
                == false)
    }

    @Test func documentsCurrentSeatDeactivationAndHonestBoundaries() throws {
        let documentation = try Self.proDocumentation()

        #expect(documentation.contains("LicenseActivationRecord"))
        #expect(documentation.contains("Settings → About can deactivate seats"))
        #expect(documentation.contains("Automatic cross-device Restore"))
        #expect(documentation.contains("periodic refund revocation"))
        #expect(documentation.contains("background provider validation"))
        #expect(documentation.contains("v1 has no in-app Restore or Deactivate control") == false)
        #expect(
            documentation.contains(
                "does not retain the Lemon Squeezy `instanceID` after minting") == false)
    }

    @Test func documentsTheSecretFreeManagedLicenseFixture() throws {
        let documentation = try Self.proDocumentation()

        #expect(documentation.contains("VITRINE_MANAGED_LICENSE_UI_TEST=1"))
        #expect(documentation.contains("VITRINE_USER_DEFAULTS_SUITE"))
        #expect(documentation.contains("#if DEBUG && VITRINE_DIRECT_DOWNLOAD"))
        #expect(documentation.contains("never reads a real Keychain item"))
        #expect(documentation.contains("Release validation"))
        #expect(documentation.contains("inspect it for the fixture's environment"))
    }

    @Test func publicProductPolicyKeepsEvaluationFreeAndDistributionDirect() throws {
        let readme = try Self.text("README.md")
        let project = try Self.text("docs/PROJECT.md")
        let architecture = try Self.text("docs/ARCHITECTURE.md")
        let pro = try Self.text("docs/PRO.md")
        let website = try Self.text("site/src/i18n/content.ts")

        for document in [readme, project, architecture, pro, website] {
            #expect(document.localizedCaseInsensitiveContains("no expiring trial"))
        }
        #expect(website.contains("No hay una prueba que caduque"))

        for document in [readme, project, architecture, pro] {
            #expect(document.contains("Homebrew"))
            #expect(document.localizedCaseInsensitiveContains("signed, notarized DMG"))
            #expect(
                document.localizedCaseInsensitiveContains("optional")
                    && document.contains("App Store"))
        }
    }

    /// A new `ProFeature` case must be named in the capability reference, which has no
    /// other link to the entitlement source.
    @Test func capabilityReferenceNamesEveryProFeature() throws {
        let source = try Self.text("Vitrine/Pro/Entitlements.swift")
        let capabilities = try Self.text("docs/CAPABILITIES.md")
        let enumBody = try #require(
            source.components(separatedBy: "enum ProFeature").dropFirst().first?
                .components(separatedBy: "var paywallTitle").first)
        let cases = enumBody.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("case ") else { return nil }
            return String(trimmed.dropFirst("case ".count))
        }
        let documentedPhrases = [
            "brandKit": "Brand Kit", "multiSizeExport": "multi-size export",
            "carouselExport": "carousel", "automation": "rendering automation",
            "advancedFrames": "advanced frames",
        ]
        #expect(!cases.isEmpty)
        for feature in cases {
            let phrase = try #require(
                documentedPhrases[feature], "Map \(feature) to its docs/CAPABILITIES.md wording")
            #expect(capabilities.contains(phrase), "docs/CAPABILITIES.md must mention \(phrase)")
        }
    }
}
