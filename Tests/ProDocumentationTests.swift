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
        let documentation = try String(
            contentsOf: repositoryRoot.appendingPathComponent("docs/PRO.md"),
            encoding: .utf8)
        return documentation.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
}
