import Foundation
import Testing

@testable import Vitrine

/// CS-062 — Mac App Store distribution readiness.
///
/// These tests assert that the committed App Store documentation, the shipped resources,
/// and the optional dry-run workflow actually encode every acceptance criterion of the
/// ticket, so a future edit that drops the documented metadata, weakens the sandbox/
/// entitlement posture, lets the App Store privacy labels drift from `PrivacyInfo.xcprivacy`,
/// removes the TestFlight upload path, strips the App Review notes, or turns the dry-run
/// workflow into an auto-submitting one fails the unit suite rather than silently breaking
/// App Store review.
///
/// Like `WorkflowConfigurationTests` (CS-060), `ReleaseSigningTests` (CS-061), and the
/// permission-matrix suites (CS-065), they read the **committed** files from the source
/// tree (anchored to this file via `#filePath`) rather than any built bundle — a real App
/// Store archive/validation cannot run in a hosted unit test without an Apple account, so
/// this suite is the structural guard that the documented readiness stays complete. The
/// archive itself is validated manually in Xcode Organizer (or via the dry-run workflow
/// once App Store Connect credentials exist).
@Suite("App Store distribution readiness · CS-062")
struct AppStoreReadinessTests {

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

    private static func doc() throws -> String {
        try text("docs", "APP-STORE.md")
    }

    private static func workflow() throws -> String {
        try text(".github", "workflows", "appstore.yml")
    }

    private static func entitlements() throws -> [String: Any] {
        let data = try Data(contentsOf: url("Vitrine", "Resources", "Vitrine.entitlements"))
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Vitrine.entitlements must be a property list")
    }

    private static func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: url("Vitrine", "Resources", "Info.plist"))
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Info.plist must be a property list")
    }

    private static func privacyManifest() throws -> [String: Any] {
        let data = try Data(contentsOf: url("Vitrine", "Resources", "PrivacyInfo.xcprivacy"))
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "PrivacyInfo.xcprivacy must be a property list")
    }

    private static func projectYAML() throws -> String {
        try text("project.yml")
    }

    // MARK: - Files exist

    @Test func theAppStoreReadinessFilesExist() {
        let fileManager = FileManager.default
        for path in [
            Self.url("docs", "APP-STORE.md"),
            Self.url(".github", "workflows", "appstore.yml"),
        ] {
            #expect(
                fileManager.fileExists(atPath: path.path),
                "CS-062 expects \(path.lastPathComponent) to exist")
        }
    }

    // MARK: - Acceptance: bundle identifier, category, versioning, copyright, metadata documented

    /// The doc must document the App Store metadata. Each value is cross-checked against the
    /// real source of truth (`Info.plist` / `project.yml`) so the doc cannot drift from the
    /// shipped identity: a stale bundle id, category, copyright, or version in the doc fails
    /// here, not silently in App Store Connect.
    @Test func documentsAppMetadataMatchingTheShippedIdentity() throws {
        let doc = try Self.doc()
        let plist = try Self.infoPlist()
        let project = try Self.projectYAML()

        // Bundle identifier — documented and matching project.yml's PRODUCT_BUNDLE_IDENTIFIER.
        #expect(doc.localizedCaseInsensitiveContains("bundle identifier"))
        #expect(doc.contains("app.vitrine"), "APP-STORE.md must document the bundle identifier")
        #expect(
            project.contains("PRODUCT_BUNDLE_IDENTIFIER: app.vitrine"),
            "the documented bundle identifier must match project.yml")

        // Category — documented and matching the Info.plist LSApplicationCategoryType.
        let category = try #require(
            plist["LSApplicationCategoryType"] as? String,
            "Info.plist must declare an App Store category")
        #expect(category == "public.app-category.developer-tools")
        #expect(doc.contains(category), "APP-STORE.md must document the App Store category")
        #expect(doc.localizedCaseInsensitiveContains("Developer Tools"))

        // Versioning — both the marketing version and the build number are documented, with
        // the App Store Connect "build number must increase" policy called out.
        #expect(doc.contains("MARKETING_VERSION"))
        #expect(doc.contains("CURRENT_PROJECT_VERSION"))
        #expect(
            doc.localizedCaseInsensitiveContains("build number"),
            "APP-STORE.md must document the App Store build-number versioning policy")

        // Copyright — documented and matching the Info.plist NSHumanReadableCopyright.
        let copyright = try #require(
            plist["NSHumanReadableCopyright"] as? String,
            "Info.plist must declare a copyright string")
        #expect(doc.contains(copyright), "APP-STORE.md must document the copyright string")
        #expect(doc.localizedCaseInsensitiveContains("copyright"))
    }

    /// The documented metadata table hard-codes the marketing version and build number
    /// (e.g. `0.1.0` / `1`); assert those exact values match `project.yml`, the source of
    /// truth they expand from. `documentsAppMetadataMatchingTheShippedIdentity` only checks
    /// the build-setting *names* are mentioned, so without this a version bump in
    /// `project.yml` would leave the doc's version table silently stale before a submission.
    @Test func documentedVersionValuesMatchProjectYAML() throws {
        let doc = try Self.doc()
        let project = try Self.projectYAML()

        // Extract the values project.yml actually sets, then require the doc names them.
        func projectValue(_ key: String) throws -> String {
            let pattern = #"(?m)^\s*\#(key):\s*"?([0-9][0-9A-Za-z.\-]*)"?\s*$"#
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(project.startIndex..<project.endIndex, in: project)
            let match = try #require(
                regex.firstMatch(in: project, range: range),
                "project.yml must set \(key)")
            let valueRange = try #require(Range(match.range(at: 1), in: project))
            return String(project[valueRange])
        }

        let marketingVersion = try projectValue("MARKETING_VERSION")
        let buildNumber = try projectValue("CURRENT_PROJECT_VERSION")

        // The doc's metadata table must carry the same marketing version and build number,
        // so the App Store Connect submission values documented here stay in lockstep with
        // what `project.yml` actually ships.
        #expect(
            doc.contains("`\(marketingVersion)`"),
            "APP-STORE.md must document the marketing version \(marketingVersion) from project.yml")
        #expect(
            doc.contains("`\(buildNumber)`"),
            "APP-STORE.md must document the build number \(buildNumber) from project.yml")
    }

    // MARK: - Acceptance: App Sandbox remains enabled; entitlements minimal and justified

    /// The App Sandbox stays enabled and the entitlement set is the minimal Phase 1 set —
    /// the App Store-compatible posture. Asserted against the real entitlements so the App
    /// Store readiness claim is concrete: the App Store requires the sandbox, and nothing
    /// broader than user-selected file access may appear.
    @Test func appSandboxStaysEnabledAndEntitlementsStayMinimal() throws {
        let entitlements = try Self.entitlements()
        #expect(
            entitlements["com.apple.security.app-sandbox"] as? Bool == true,
            "App Store builds must keep the App Sandbox enabled (CS-062)")
        #expect(
            entitlements["com.apple.security.files.user-selected.read-write"] as? Bool == true)

        // The set is exactly sandbox + user-selected files — no broader/heavier entitlement.
        let keys = Set(entitlements.keys)
        #expect(
            keys == [
                "com.apple.security.app-sandbox",
                "com.apple.security.files.user-selected.read-write",
            ],
            """
            App Store entitlement set drifted from the documented minimal set (CS-062). \
            Found \(keys.sorted()). Update docs/APP-STORE.md, docs/PERMISSIONS.md, and the \
            tests in the same change.
            """)
    }

    /// The doc must state that the App Sandbox remains enabled and that the entitlement set
    /// is minimal and justified — the acceptance criterion in prose, beside the entitlement
    /// check above.
    @Test func documentsSandboxAndMinimalJustifiedEntitlements() throws {
        let doc = try Self.doc()
        #expect(doc.localizedCaseInsensitiveContains("App Sandbox"))
        #expect(
            doc.localizedCaseInsensitiveContains("required")
                && doc.localizedCaseInsensitiveContains("sandbox"),
            "APP-STORE.md must note the App Store requires the App Sandbox")
        #expect(doc.contains("com.apple.security.app-sandbox"))
        #expect(doc.contains("com.apple.security.files.user-selected.read-write"))
        // It points at the authoritative per-entitlement matrix.
        #expect(
            doc.contains("PERMISSIONS.md"),
            "APP-STORE.md must reference the entitlement matrix (docs/PERMISSIONS.md)")
    }

    // MARK: - Acceptance: network entitlement absent for Phase 1 App Store builds

    /// Phase 1 App Store builds request **no network**: the network-client entitlement is
    /// absent from the shipped entitlements (so a Phase 1 build provably cannot reach the
    /// network), and the doc states this for the App Store channel.
    @Test func phase1AppStoreBuildsRequestNoNetwork() throws {
        let entitlements = try Self.entitlements()
        #expect(
            entitlements[NetworkCapability.networkClientEntitlement] == nil,
            "Phase 1 App Store builds must not request \(NetworkCapability.networkClientEntitlement) (CS-062)"
        )

        let doc = try Self.doc()
        #expect(doc.localizedCaseInsensitiveContains("no network"))
        #expect(
            doc.contains(NetworkCapability.networkClientEntitlement),
            "APP-STORE.md must name the network-client entitlement it says is absent")
    }

    // MARK: - Acceptance: Phase 2 URL capture updates the network entitlement and privacy copy first

    /// If Phase 2 URL capture ships, the network entitlement and the privacy copy must be
    /// updated **before** an App Store submission. The doc must spell out that gate: name the
    /// network entitlement as the switch, require the privacy copy update, and tie it to the
    /// drift-guard test.
    @Test func documentsThePhase2NetworkAndPrivacyGate() throws {
        let doc = try Self.doc()
        #expect(doc.localizedCaseInsensitiveContains("Phase 2"))
        #expect(doc.localizedCaseInsensitiveContains("URL capture"))
        // The page loads locally in WebKit — no remote screenshot service.
        #expect(doc.localizedCaseInsensitiveContains("locally in WebKit"))
        #expect(doc.localizedCaseInsensitiveContains("no remote screenshot service"))
        // The gate: add the network entitlement and update privacy copy before submission.
        #expect(doc.contains(NetworkCapability.networkClientEntitlement))
        #expect(
            doc.localizedCaseInsensitiveContains("before")
                && doc.localizedCaseInsensitiveContains("privacy copy"),
            "APP-STORE.md must require the privacy copy to be updated before an App Store submission"
        )
        // It points at the test that enforces the entitlement is absent today.
        #expect(doc.contains("Tests/PrivacyManifestTests.swift"))
    }

    // MARK: - Acceptance: App Store privacy labels listed and match PrivacyInfo.xcprivacy

    /// The App Store privacy labels are listed in the doc and match the bundled privacy
    /// manifest. The manifest is read and asserted to be "no tracking, no collected data,
    /// UserDefaults-only", and the doc must claim exactly that label ("Data Not Collected"),
    /// so the two cannot diverge.
    @Test func privacyLabelsAreListedAndMatchTheManifest() throws {
        // The manifest declares no tracking and no collected data.
        let manifest = try Self.privacyManifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any] ?? []).isEmpty)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any] ?? []).isEmpty)
        let apiTypes = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let categories = apiTypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        #expect(categories == ["NSPrivacyAccessedAPICategoryUserDefaults"])

        // The doc lists the labels and matches them to the manifest.
        let doc = try Self.doc()
        #expect(
            doc.localizedCaseInsensitiveContains("privacy label"),
            "APP-STORE.md must list the App Store privacy labels (CS-062)")
        #expect(
            doc.localizedCaseInsensitiveContains("Data Not Collected"),
            "the overall App Store privacy label must be Data Not Collected, matching the manifest")
        #expect(
            doc.contains("PrivacyInfo.xcprivacy"),
            "APP-STORE.md must tie the labels to PrivacyInfo.xcprivacy")
        // It names the only required-reason API so the label is concrete.
        #expect(doc.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(doc.contains("CA92.1"))
    }

    // MARK: - Acceptance: TestFlight upload path documented (Organizer / Transporter / altool)

    /// The TestFlight upload path must be documented through Xcode Organizer, Transporter,
    /// **or** `xcrun altool`/Transporter CLI. Assert all three are present so the
    /// "any of these" acceptance is genuinely covered, not just one path.
    @Test func documentsTheTestFlightUploadPaths() throws {
        let doc = try Self.doc()
        #expect(doc.localizedCaseInsensitiveContains("TestFlight"))
        // Xcode Organizer path.
        #expect(
            doc.localizedCaseInsensitiveContains("Organizer"),
            "APP-STORE.md must document the Xcode Organizer upload path (CS-062)")
        // Transporter path.
        #expect(
            doc.contains("Transporter"),
            "APP-STORE.md must document the Transporter upload path (CS-062)")
        // altool / command-line path.
        #expect(
            doc.contains("altool"),
            "APP-STORE.md must document the xcrun altool upload path (CS-062)")
        // The upload step itself is named.
        #expect(doc.localizedCaseInsensitiveContains("upload"))
    }

    // MARK: - Acceptance: App Review notes explain clipboard, local rendering, launch-at-login, no telemetry

    /// The App Review notes must explain clipboard usage, local rendering, launch-at-login,
    /// and that there is no telemetry — the four points reviewers need to evaluate a
    /// menu-bar, on-device, account-less app.
    @Test func documentsAppReviewNotesCoveringTheRequiredPoints() throws {
        let doc = try Self.doc()
        #expect(
            doc.localizedCaseInsensitiveContains("App Review"),
            "APP-STORE.md must include App Review notes (CS-062)")
        // Clipboard usage.
        #expect(doc.localizedCaseInsensitiveContains("clipboard"))
        // Local rendering — nothing leaves the Mac.
        #expect(
            doc.localizedCaseInsensitiveContains("on-device")
                || doc.localizedCaseInsensitiveContains("locally"),
            "App Review notes must explain local, on-device rendering")
        #expect(doc.localizedCaseInsensitiveContains("ImageRenderer"))
        // Launch at login.
        #expect(
            doc.localizedCaseInsensitiveContains("launch at login")
                || doc.localizedCaseInsensitiveContains("launch-at-login"),
            "App Review notes must explain launch-at-login")
        // No telemetry.
        #expect(
            doc.localizedCaseInsensitiveContains("no telemetry")
                || doc.localizedCaseInsensitiveContains("no analytics"),
            "App Review notes must state there is no telemetry")
        // Menu-bar agent / no Dock icon, so a reviewer can find the UI.
        #expect(doc.localizedCaseInsensitiveContains("menu-bar"))
    }

    /// The App Review note promises a **menu-bar agent with no Dock icon**, and the metadata
    /// table claims `LSUIElement = true`. Assert the shipped `Info.plist` actually sets it, so
    /// the reviewer-facing "no Dock icon" claim cannot become a lie while the prose-only checks
    /// above still pass. Also assert the doc only states it (it is documented, not invented
    /// here) — the binding here is to the real plist.
    @Test func infoPlistShipsAsAMenuBarAgentMatchingTheReviewNotes() throws {
        let plist = try Self.infoPlist()
        #expect(
            plist["LSUIElement"] as? Bool == true,
            "Info.plist must set LSUIElement = true so the App Review 'no Dock icon' note holds (CS-062)"
        )

        let doc = try Self.doc()
        #expect(
            doc.contains("LSUIElement"),
            "APP-STORE.md must document the LSUIElement agent posture it claims in the review notes"
        )
    }

    /// The App Review notes and the entitlement summary both hinge on clipboard being the
    /// **only** declared usage string (the doc says so at the entitlement section). Assert the
    /// shipped `Info.plist` declares exactly one `…UsageDescription`, and that it is
    /// `NSPasteboardUsageDescription`. A second usage string (e.g. a new TCC prompt) would
    /// expand the App Store review surface and silently invalidate the clipboard-only review
    /// note while the prose-only `documentsAppReviewNotesCoveringTheRequiredPoints` still passed.
    @Test func clipboardIsTheOnlyDeclaredUsageString() throws {
        let plist = try Self.infoPlist()
        let usageKeys = plist.keys.filter { $0.hasSuffix("UsageDescription") }.sorted()
        #expect(
            usageKeys == ["NSPasteboardUsageDescription"],
            """
            Info.plist must declare exactly one usage string (clipboard), matching the App \
            Store review notes (CS-062). Found \(usageKeys). A new usage string expands the \
            review surface — update docs/APP-STORE.md and the review notes in the same change.
            """)
        // The doc names the same single usage string in its entitlement summary.
        #expect(
            try Self.doc().contains("NSPasteboardUsageDescription"),
            "APP-STORE.md must name NSPasteboardUsageDescription as the only declared usage string")
    }

    // MARK: - The optional dry-run workflow

    /// YAML forbids tab characters for indentation; a stray tab is a syntax error the CI
    /// Ruby parse would reject. Guard it here too so the failure is local and fast (mirrors
    /// `WorkflowConfigurationTests.workflowYAMLUsesNoTabIndentation`).
    @Test func workflowUsesNoTabIndentation() throws {
        let body = try Self.workflow()
        for (index, line) in body.components(separatedBy: .newlines).enumerated() {
            let indentation = line.prefix { $0 == " " || $0 == "\t" }
            #expect(
                !indentation.contains("\t"),
                "appstore.yml line \(index + 1) uses a tab for indentation, which is invalid YAML")
        }
    }

    /// The optional workflow is a **dry run**: manually triggered, it archives and validates
    /// but **never** auto-submits or auto-uploads a build. Assert it is `workflow_dispatch`,
    /// runs `validate-app`, and contains **no** `upload-app` step — the property that keeps
    /// it safe to merge on a repo without an Apple account.
    @Test func workflowIsAManualDryRunThatNeverAutoSubmits() throws {
        let workflow = try Self.workflow()
        #expect(
            workflow.contains("workflow_dispatch"),
            "appstore.yml must be manually triggered (workflow_dispatch) (CS-062)")
        #expect(
            workflow.contains("--validate-app"),
            "appstore.yml must run App Store validation as a dry run (CS-062)")
        // The critical safety property: it must never upload/submit a build automatically.
        #expect(
            !workflow.contains("--upload-app"),
            "appstore.yml must NOT upload/submit a build automatically (it is a dry run only, CS-062)"
        )
        #expect(
            workflow.localizedCaseInsensitiveContains("never")
                && workflow.localizedCaseInsensitiveContains("submit"),
            "appstore.yml must document that it never submits a build")
    }

    /// The dry-run validation is gated on the App Store Connect API-key secrets so the
    /// workflow degrades gracefully: with no credentials the archive still builds and the
    /// validation step is skipped, mirroring the signed DMG pipeline (CS-061). Assert the
    /// archive step and the secret gate are both present.
    @Test func workflowGatesValidationOnSecretsAndStillArchivesWithout() throws {
        let workflow = try Self.workflow()
        // The archive always runs (buildable without an Apple Distribution identity).
        #expect(
            workflow.contains("archive"),
            "appstore.yml must archive the app (CS-062)")
        #expect(
            workflow.contains("CODE_SIGNING_ALLOWED=NO"),
            "the dry-run archive must build without a signing identity")
        // Validation is gated on the App Store Connect API-key secret.
        #expect(
            workflow.contains("MACOS_NOTARY_KEY_P8"),
            "appstore.yml must gate validation on the App Store Connect API key (CS-062)")
        let validateMarker = try #require(
            workflow.range(of: "--validate-app"),
            "appstore.yml must contain the validate-app step")
        let beforeValidate = String(workflow[..<validateMarker.lowerBound])
        #expect(
            beforeValidate.contains("MACOS_NOTARY_KEY_ID != ''"),
            "the validate-app step must be gated on the App Store Connect API-key secrets (CS-062)")
    }

    /// The doc must point at the optional workflow and describe it as a credential-gated dry
    /// run that never submits, so the two stay consistent.
    @Test func documentsTheOptionalDryRunWorkflow() throws {
        let doc = try Self.doc()
        #expect(
            doc.contains("appstore.yml"),
            "APP-STORE.md must reference the optional .github/workflows/appstore.yml (CS-062)")
        #expect(doc.localizedCaseInsensitiveContains("dry run"))
        #expect(
            doc.localizedCaseInsensitiveContains("never")
                && (doc.localizedCaseInsensitiveContains("submit")
                    || doc.localizedCaseInsensitiveContains("upload")),
            "APP-STORE.md must say the dry-run workflow never submits/uploads a build")
    }
}
