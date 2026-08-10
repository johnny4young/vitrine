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
        let website = try Self.text("site/src/components/Commercial.astro")
        let websiteTranslations = try Self.text("site/public/scripts/site.js")

        for document in [readme, project, architecture, pro, website] {
            #expect(document.localizedCaseInsensitiveContains("no expiring trial"))
        }
        #expect(websiteTranslations.contains("No hay una prueba que caduque"))

        for document in [readme, project, architecture, pro] {
            #expect(document.contains("Homebrew"))
            #expect(document.localizedCaseInsensitiveContains("signed, notarized DMG"))
            #expect(
                document.localizedCaseInsensitiveContains("optional")
                    && document.contains("App Store"))
        }
    }
}
