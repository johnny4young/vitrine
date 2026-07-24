import Foundation
import Testing

@testable import Vitrine

/// Sparkle auto-update channel.
///
/// These tests assert that the committed configuration, resources, workflow, and docs
/// actually encode every release requirement, so a future edit that drops
/// the Sparkle package, the EdDSA-signed appcast, the `SUFeedURL`, the per-release appcast
/// publish, the no-analytics posture, or the App Store exclusion of Sparkle fails the unit
/// suite rather than silently breaking the direct-download update story.
///
/// Like `WorkflowConfigurationTests`, `ReleaseSigningTests`,
/// `AppStoreReadinessTests`, and the permission-matrix suites, they read
/// the **committed** files from the source tree (anchored to this file via `#filePath`)
/// rather than any built bundle — the live update flow needs a signed appcast on a real
/// server and a Developer ID build, which a hosted unit test cannot exercise. So this suite
/// is the structural guard that the documented channel stays complete; the manual "version N
/// to N+1" and "signature verification" runs are documented in `docs/RELEASING.md`.
///
/// No SwiftUI `body` is rendered, so the suite stays clear of CoreText under the parallel
/// runner.
@Suite("Software update channel")
struct SoftwareUpdateChannelTests {

    // MARK: - Repository anchoring

    /// The repository root, anchored to this file (`<repo>/Tests/…`).
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    private static func url(_ components: String...) -> URL {
        components.reduce(repositoryRoot) { $0.appendingPathComponent($1) }
    }

    private static func text(_ components: String...) throws -> String {
        try String(
            contentsOf: components.reduce(repositoryRoot) { $0.appendingPathComponent($1) },
            encoding: .utf8)
    }

    private static func projectYAML() throws -> String {
        try text("project.yml")
    }

    private static func release() throws -> String {
        try text(".github", "workflows", "release.yml")
    }

    private static func appStoreWorkflow() throws -> String {
        try text(".github", "workflows", "appstore.yml")
    }

    private static func buildScript() throws -> String {
        try text("scripts", "build-dmg.sh")
    }

    private static func releasingDoc() throws -> String {
        try text("docs", "RELEASING.md")
    }

    private static func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: url("Vitrine", "Resources", "Info.plist"))
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Info.plist must be a property list")
    }

    /// The minimal app-target entitlements (App Store / local rendering / default build).
    private static func entitlements() throws -> [String: Any] {
        let data = try Data(contentsOf: url("Vitrine", "Resources", "Vitrine.entitlements"))
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Vitrine.entitlements must be a property list")
    }

    /// The direct-download (Sparkle) entitlements superset used only by the DMG build.
    private static func directDownloadEntitlements() throws -> [String: Any] {
        let data = try Data(
            contentsOf: url("Vitrine", "Resources", "Vitrine.DirectDownload.entitlements"))
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Vitrine.DirectDownload.entitlements must be a property list")
    }

    // MARK: - Files exist

    @Test func theUpdateChannelFilesExist() {
        let fileManager = FileManager.default
        for path in [
            Self.url("project.yml"),
            Self.url("Vitrine", "Resources", "Info.plist"),
            Self.url("Vitrine", "Resources", "Vitrine.DirectDownload.entitlements"),
            Self.url("Vitrine", "Updates", "SoftwareUpdater.swift"),
            Self.url(".github", "workflows", "release.yml"),
            Self.url("docs", "RELEASING.md"),
        ] {
            #expect(
                fileManager.fileExists(atPath: path.path),
                " expects \(path.lastPathComponent) to exist")
        }
    }

    // MARK: - Contract: Sparkle is embedded as a local framework through project.yml

    /// Sparkle is embedded as a LOCAL framework (Vendor/Sparkle.framework), not via its SPM
    /// binary artifact — that artifact's resolution hung intermittently on headless CI runners,
    /// stalling `xcodebuild` for 20+ minutes. The framework is fetched and checksum-verified by
    /// `scripts/fetch-sparkle.sh` before generate, and the app target embeds it.
    @Test func sparkleIsEmbeddedAsALocalFrameworkThroughProjectYAML() throws {
        let project = try Self.projectYAML()
        // The app target depends on the locally-vendored framework…
        #expect(
            project.contains("framework: Vendor/Sparkle.framework"),
            "project.yml must depend on the local Vendor/Sparkle.framework")
        // …and embeds it into the app bundle so the updater ships inside Vitrine.app.
        #expect(
            project.contains("embed: true"),
            "project.yml must embed Vendor/Sparkle.framework into the app bundle")
        // The framework is fetched + checksum-verified by a dedicated script, so the SPM
        // binary artifact (which hung CI) is never resolved.
        let fetchScript = try Self.text("scripts", "fetch-sparkle.sh")
        #expect(
            fetchScript.contains("Sparkle.framework"),
            "scripts/fetch-sparkle.sh must stage Sparkle.framework into Vendor/")
        #expect(
            fetchScript.localizedCaseInsensitiveContains("sha256")
                || fetchScript.contains("shasum"),
            "scripts/fetch-sparkle.sh must verify the download against a pinned checksum")
    }

    /// Sparkle must be linked into the **app** target but **not** the headless CLI (which
    /// ships no updater). Assert the CLI overrides the compilation conditions to drop the
    /// direct-download flag, so the shared `SoftwareUpdater` compiles to its no-op form there
    /// and never imports Sparkle (a framework the CLI does not depend on).
    @Test func cliExcludesSparkleViaCompilationConditions() throws {
        let project = try Self.projectYAML()
        // The CLI target sets SWIFT_ACTIVE_COMPILATION_CONDITIONS to empty (no inherited
        // VITRINE_DIRECT_DOWNLOAD), which is how it compiles without Sparkle.
        #expect(
            project.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS: \"\""),
            "the CLI target must drop VITRINE_DIRECT_DOWNLOAD so it never links Sparkle")
    }

    // MARK: - Contract: SUFeedURL points to a signed appcast (over HTTPS)

    @Test func infoPlistDeclaresAnHTTPSAppcastFeedURL() throws {
        let plist = try Self.infoPlist()
        let feed = try #require(
            plist["SUFeedURL"] as? String,
            "Info.plist must declare SUFeedURL for the appcast")
        #expect(
            feed.hasPrefix("https://"),
            "SUFeedURL must be served over HTTPS so the feed cannot be tampered with in transit")
        #expect(
            feed.hasSuffix(".xml"),
            "SUFeedURL must point at the appcast XML feed")
    }

    /// The appcast is **signed**: the app embeds an EdDSA public key Sparkle verifies every
    /// download against. Assert `SUPublicEDKey` is present (the signature-verification
    /// switch); its real value is pasted in at release time (documented in RELEASING.md).
    @Test func infoPlistDeclaresAnEdDSAPublicKeyForSignatureVerification() throws {
        let plist = try Self.infoPlist()
        let key = try #require(
            plist["SUPublicEDKey"] as? String,
            "Info.plist must declare SUPublicEDKey so Sparkle verifies update signatures")
        #expect(!key.isEmpty, "SUPublicEDKey must not be empty")
    }

    // MARK: - Contract: update checks do not collect analytics

    /// Sparkle's anonymous system-profiling feature must be off, so an update check sends no
    /// usage data. Assert `SUEnableSystemProfiling` is explicitly `false` in `Info.plist`
    /// (declared, not merely defaulted, so it cannot be silently flipped on).
    @Test func systemProfilingIsDisabledSoUpdateChecksCollectNoAnalytics() throws {
        let plist = try Self.infoPlist()
        #expect(
            plist["SUEnableSystemProfiling"] as? Bool == false,
            "SUEnableSystemProfiling must be NO so update checks collect no analytics")
        // The source comment that pins the no-analytics intent (no profiling delegate) lives
        // in SoftwareUpdater.swift; assert it states the no-analytics property.
        let updater = try Self.text("Vitrine", "Updates", "SoftwareUpdater.swift")
        #expect(
            updater.localizedCaseInsensitiveContains("no analytics")
                || updater.localizedCaseInsensitiveContains("no telemetry"),
            "SoftwareUpdater.swift must document the no-analytics posture")
    }

    // MARK: - Contract: update checks are user-visible

    /// The update check is reachable by the user: a "Check for Updates" command exists and
    /// is wired to the updater. Assert the command and its menu wiring are present in the
    /// app's command surface.
    @Test func updateCheckIsUserVisibleThroughACommand() throws {
        // The command exists in the app's command enum.
        #expect(
            VitrineCommand.allCases.contains(.checkForUpdates),
            "a user-visible Check for Updates command must exist")
        #expect(
            VitrineCommand.checkForUpdates.title.localizedCaseInsensitiveContains("update"),
            "the Check for Updates command title must mention updates")

        // The responder routes it to the updater, and the menu exposes it only on a build
        // that ships Sparkle.
        let commands = try Self.text("Vitrine", "App", "VitrineCommands.swift")
        #expect(
            commands.contains("SoftwareUpdater.shared.checkForUpdates()"),
            "the Check for Updates command must invoke the updater")
        let menu = try Self.text("Vitrine", "App", "AppMenu.swift")
        #expect(
            menu.contains("SoftwareUpdater.isSupported"),
            "the menu must add the update command only when Sparkle is supported")
    }

    // MARK: - Contract: appcast is published with each GitHub release

    @Test func releaseWorkflowPublishesTheAppcastWithEachRelease() throws {
        let release = try Self.release()
        // The appcast is generated and signed in the release workflow…
        #expect(
            release.contains("generate_appcast"),
            "release.yml must generate the appcast with Sparkle's generate_appcast")
        #expect(
            release.contains("appcast.xml"),
            "release.yml must produce appcast.xml")
        // …gated on the EdDSA private-key secret (graceful degradation, like signing)…
        #expect(
            release.contains("SPARKLE_EDDSA_PRIVATE_KEY"),
            "release.yml must sign the appcast with the EdDSA private-key secret")
        // …and the appcast is both attached to the release and deployed to where SUFeedURL
        // points (GitHub Pages).
        let publishMarker = try #require(
            release.range(of: "\n  publish:"),
            "release.yml must declare a publish job")
        let afterPublish = String(release[publishMarker.lowerBound...])
        #expect(
            afterPublish.contains("dist/appcast.xml"),
            "the published GitHub release must attach the appcast")
        #expect(
            release.contains("deploy-pages") || release.contains("upload-pages-artifact"),
            "release.yml must deploy the appcast to GitHub Pages (the SUFeedURL host)")
    }

    /// The appcast feed host in `Info.plist` must be the place the workflow deploys to.
    /// `SUFeedURL` points at GitHub Pages, and the workflow deploys the appcast via the Pages
    /// actions — assert both, so the feed the app polls is the feed the release refreshes.
    @Test func appcastFeedURLMatchesThePagesDeployTarget() throws {
        let plist = try Self.infoPlist()
        let feed = try #require(plist["SUFeedURL"] as? String)
        #expect(
            feed.contains("github.io"),
            "SUFeedURL must be the GitHub Pages feed the release workflow deploys")
        let release = try Self.release()
        #expect(
            release.contains("deploy-pages"),
            "release.yml must deploy the appcast to GitHub Pages so SUFeedURL resolves")
    }

    // MARK: - Contract: App Store build excludes Sparkle

    /// The compilation gate exists: the direct-download build defines `VITRINE_DIRECT_DOWNLOAD`
    /// (so Sparkle compiles in) and the App Store build removes it (so Sparkle compiles out).
    /// Assert the flag is set in the project base and removed in the App Store archive.
    @Test func appStoreBuildExcludesSparkleViaCompilationFlagAndStrip() throws {
        let project = try Self.projectYAML()
        // The direct-download build sets the flag at the project base.
        #expect(
            project.contains("VITRINE_DIRECT_DOWNLOAD"),
            "project.yml must define VITRINE_DIRECT_DOWNLOAD for the direct-download build"
        )

        // The App Store dry-run workflow removes the flag and strips the framework.
        let appStore = try Self.appStoreWorkflow()
        #expect(
            appStore.contains("'SWIFT_ACTIVE_COMPILATION_CONDITIONS='"),
            "the App Store archive must remove VITRINE_DIRECT_DOWNLOAD so Sparkle compiles out"
        )
        #expect(
            appStore.contains("Sparkle.framework"),
            "the App Store archive must strip the Sparkle framework")
        // And it proves the exclusion: the job fails if any Sparkle payload remains.
        #expect(
            appStore.localizedCaseInsensitiveContains("no Sparkle")
                || appStore.localizedCaseInsensitiveContains("excluded"),
            "the App Store workflow must verify Sparkle is excluded from the archive")
    }

    /// The runtime gate matches the build gate: `SoftwareUpdater.isSupported` reflects whether
    /// Sparkle is compiled in. The direct-download build is the default and defines
    /// `VITRINE_DIRECT_DOWNLOAD`, so the updater is live and reports itself supported here. The
    /// Mac App Store archive removes that flag and strips the framework, flipping this to
    /// `false` there — asserted by `appStoreBuildExcludesSparkleViaCompilationFlagAndStrip`.
    @Test func directDownloadBuildReportsUpdatesSupported() {
        #expect(
            SoftwareUpdater.isSupported,
            "the direct-download build defines VITRINE_DIRECT_DOWNLOAD, so Sparkle is compiled in and updates are supported"
        )
    }

    // MARK: - Contract: EdDSA signing keys are generated and documented

    /// The DMG build signs with the direct-download entitlements superset that grants Sparkle
    /// what it needs to auto-update a sandboxed app: outbound network and the Sparkle XPC
    /// mach-lookup exceptions. The minimal app entitlements (App Store / local rendering) must stay
    /// free of both, so the App Store posture and the local rendering "no network" guarantee are
    /// unchanged.
    @Test func directDownloadEntitlementsGrantSparkleNetworkAndXPCButTheMinimalSetDoesNot() throws {
        let direct = try Self.directDownloadEntitlements()
        // The superset keeps the App Sandbox on…
        #expect(direct["com.apple.security.app-sandbox"] as? Bool == true)
        // …and adds outbound network for the update download…
        #expect(
            direct[NetworkCapability.networkClientEntitlement] as? Bool == true,
            "the direct-download entitlements must grant network for Sparkle downloads")
        // …and the Sparkle XPC mach-lookup exceptions (…-spks / …-spki).
        let machLookup =
            direct["com.apple.security.temporary-exception.mach-lookup.global-name"] as? [String]
            ?? []
        #expect(
            machLookup.contains { $0.hasSuffix("-spks") }
                && machLookup.contains {
                    $0.hasSuffix("-spki")
                },
            "the direct-download entitlements must include Sparkle's XPC mach-lookup exceptions"
        )

        // The minimal (App Store / local rendering) entitlements must NOT carry network or the Sparkle
        // exceptions — that is what keeps the App Store build network-free and Sparkle-free.
        let minimal = try Self.entitlements()
        #expect(
            minimal[NetworkCapability.networkClientEntitlement] == nil,
            "the App Store / local rendering entitlements must stay network-free")
        #expect(
            minimal["com.apple.security.temporary-exception.mach-lookup.global-name"] == nil,
            "the App Store / local rendering entitlements must not carry Sparkle's XPC exceptions")
    }

    /// The DMG packaging step selects the direct-download entitlements, so the shipped DMG
    /// actually grants Sparkle its capabilities (rather than the minimal set, which would
    /// leave the updater unable to download under the sandbox).
    @Test func buildScriptSignsTheDMGWithTheDirectDownloadEntitlements() throws {
        let script = try Self.buildScript()
        #expect(
            script.contains("Vitrine.DirectDownload.entitlements"),
            "build-dmg.sh must sign the DMG with the direct-download entitlements")
        #expect(
            script.contains("VITRINE_ENTITLEMENTS_FILE="),
            "build-dmg.sh must select the entitlements file via VITRINE_ENTITLEMENTS_FILE")
    }

    // MARK: - Contract: documentation (keys generated + documented; N→N+1; signature; channels)

    @Test func releasingDocDocumentsKeysAppcastAndChannelExclusion() throws {
        let doc = try Self.releasingDoc()
        #expect(
            doc.contains("Vendor/Sparkle.framework") && doc.contains("scripts/fetch-sparkle.sh"),
            "RELEASING.md must document that Sparkle is embedded as the local checked framework, not an SPM package"
        )
        // EdDSA key generation is documented (the generate_keys tool + the secret).
        #expect(
            doc.contains("generate_keys"),
            "RELEASING.md must document generating the EdDSA keys with generate_keys")
        #expect(
            doc.contains("SPARKLE_EDDSA_PRIVATE_KEY"),
            "RELEASING.md must document the EdDSA private-key secret")
        #expect(
            doc.contains("SUPublicEDKey"),
            "RELEASING.md must document pasting the public key into Info.plist")
        // The appcast-per-release and the N→N+1 + signature-verification test are documented.
        #expect(
            doc.localizedCaseInsensitiveContains("appcast"),
            "RELEASING.md must document the appcast")
        #expect(
            doc.localizedCaseInsensitiveContains("N to N+1")
                || doc.localizedCaseInsensitiveContains("N+1"),
            "RELEASING.md must document testing an update from N to N+1")
        #expect(
            doc.localizedCaseInsensitiveContains("signature"),
            "RELEASING.md must document signature verification")
        // The App Store exclusion is documented.
        #expect(
            doc.localizedCaseInsensitiveContains("App Store build excludes Sparkle")
                || (doc.localizedCaseInsensitiveContains("App Store")
                    && doc.localizedCaseInsensitiveContains("excludes Sparkle")),
            "RELEASING.md must document that the App Store build excludes Sparkle")
        // No analytics on the update path.
        #expect(
            doc.localizedCaseInsensitiveContains("no telemetry")
                || doc.localizedCaseInsensitiveContains("no analytics"),
            "RELEASING.md must state the update path collects no analytics")
    }
}
