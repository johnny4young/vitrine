import Foundation
import Testing

@testable import Vitrine

/// Mac App Store distribution readiness.
///
/// These tests assert that the committed App Store documentation, the shipped resources,
/// and the optional dry-run workflow actually encode every contract criterion of the
/// release contract, so a future edit that drops the documented metadata, weakens the sandbox/
/// entitlement posture, lets the App Store privacy labels drift from `PrivacyInfo.xcprivacy`,
/// removes the TestFlight upload path, strips the App Review notes, or turns the dry-run
/// workflow into an auto-submitting one fails the unit suite rather than silently breaking
/// App Store review.
///
/// Like `WorkflowConfigurationTests`, `ReleaseSigningTests`, and the
/// permission-matrix suites, they read the **committed** files from the source
/// tree (anchored to this file via `#filePath`) rather than any built bundle — a real App
/// Store archive/validation cannot run in a hosted unit test without an Apple account, so
/// this suite is the structural guard that the documented readiness stays complete. The
/// archive itself is validated manually in Xcode Organizer (or via the dry-run workflow
/// once App Store Connect credentials exist).
@Suite("App Store distribution readiness")
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

    /// The body of a top-level `## <name>` Markdown section, from its heading up to
    /// the next `## ` heading (or end of file). Returns `nil` if the heading is absent.
    private static func section(named name: String, in markdown: String) -> String? {
        guard let start = markdown.range(of: "## \(name)") else { return nil }
        let rest = markdown[start.upperBound...]
        if let next = rest.range(of: "\n## ") {
            return String(rest[..<next.lowerBound])
        }
        return String(rest)
    }

    /// `MARKETING_VERSION` as `project.yml` actually sets it — the single source of
    /// truth the version-sync guards below all compare against.
    private static func marketingVersion() throws -> String {
        let project = try projectYAML()
        let regex = try NSRegularExpression(
            pattern: #"(?m)^\s*MARKETING_VERSION:\s*"?([0-9][0-9A-Za-z.\-]*)"?\s*$"#)
        let match = try #require(
            regex.firstMatch(
                in: project, range: NSRange(project.startIndex..<project.endIndex, in: project)),
            "project.yml must set MARKETING_VERSION")
        return String(project[try #require(Range(match.range(at: 1), in: project))])
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
                " expects \(path.lastPathComponent) to exist")
        }
    }

    // MARK: - Contract: bundle identifier, category, versioning, copyright, metadata documented

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
        #expect(
            doc.contains("com.johnny4young.vitrine"),
            "APP-STORE.md must document the bundle identifier")
        #expect(
            project.contains("PRODUCT_BUNDLE_IDENTIFIER: com.johnny4young.vitrine"),
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

    /// The changelog's newest released entry stays in lockstep with the shipped version:
    /// the top `## [x.y.z]` in `CHANGELOG.md`, the `MARKETING_VERSION` in `project.yml`, and
    /// the bundled `ReleaseNotes.latest` must all name the same version, and an
    /// `## [Unreleased]` section must exist to collect the next release. A bump that forgets
    /// the changelog (or a changelog edit that forgets the bump) fails the suite rather than
    /// shipping a stale history.
    @Test func changelogNewestEntryMatchesTheShippedVersion() throws {
        let changelog = try Self.text("CHANGELOG.md")
        let project = try Self.projectYAML()

        // MARKETING_VERSION from project.yml — the same source of truth the version-doc
        // test reads.
        let mvRegex = try NSRegularExpression(
            pattern: #"(?m)^\s*MARKETING_VERSION:\s*"?([0-9][0-9A-Za-z.\-]*)"?\s*$"#)
        let mvMatch = try #require(
            mvRegex.firstMatch(
                in: project, range: NSRange(project.startIndex..<project.endIndex, in: project)),
            "project.yml must set MARKETING_VERSION")
        let marketingVersion = String(
            project[try #require(Range(mvMatch.range(at: 1), in: project))])

        // The newest *released* heading — `## [1.2.3]` — skipping the `## [Unreleased]`
        // collector, which carries no version number.
        let headingRegex = try NSRegularExpression(
            pattern: #"(?m)^##\s*\[([0-9]+\.[0-9]+\.[0-9]+)\]"#)
        let topMatch = try #require(
            headingRegex.firstMatch(
                in: changelog,
                range: NSRange(changelog.startIndex..<changelog.endIndex, in: changelog)),
            "CHANGELOG.md must list at least one released version as `## [x.y.z]`")
        let topVersion = String(
            changelog[try #require(Range(topMatch.range(at: 1), in: changelog))])

        #expect(
            changelog.contains("## [Unreleased]"),
            "CHANGELOG.md must keep an `## [Unreleased]` section for the next release")
        #expect(
            topVersion == marketingVersion,
            "CHANGELOG.md's newest version must match MARKETING_VERSION in project.yml")
        #expect(
            topVersion == ReleaseNotes.latestVersion,
            "CHANGELOG.md's newest version must match the bundled ReleaseNotes.latest")
    }

    @Test func changelogKeepsReleaseNotesAndCompareLinksTraceable() throws {
        let changelog = try Self.text("CHANGELOG.md")
        let fullRange = NSRange(changelog.startIndex..<changelog.endIndex, in: changelog)
        let headingRegex = try NSRegularExpression(
            pattern: #"(?m)^##\s*\[([0-9]+\.[0-9]+\.[0-9]+)\]"#)
        let linkRegex = try NSRegularExpression(
            pattern: #"(?m)^\[([0-9]+\.[0-9]+\.[0-9]+)\]:\s+https://"#)

        func versions(matching regex: NSRegularExpression) -> Set<String> {
            Set(
                regex.matches(in: changelog, range: fullRange).compactMap { match in
                    Range(match.range(at: 1), in: changelog).map { String(changelog[$0]) }
                })
        }

        let headings = versions(matching: headingRegex)
        let links = versions(matching: linkRegex)
        let releaseNoteVersions = Set(ReleaseNotes.all.map(\.version))

        #expect(
            releaseNoteVersions.isSubset(of: headings),
            "every bundled release note must have a matching changelog section")
        #expect(
            headings == links,
            "changelog release headings and compare links must cover the same versions")
        let latestVersion = try #require(ReleaseNotes.latestVersion)
        #expect(
            changelog.contains(
                "[Unreleased]: https://github.com/johnny4young/vitrine/compare/v"
                    + "\(latestVersion)...HEAD"
            ),
            "the Unreleased section must link from the latest release to HEAD")
    }

    /// The README — the project's front page — keeps its release-status badge and its
    /// `## Status` section in lockstep with `MARKETING_VERSION`. The badge encodes the
    /// version in its shields.io URL (`status-vX.Y.Z…`) and the section prose names it
    /// in the current release-status line; a version bump that forgets either would greet
    /// every visitor with a stale release number. This fails the bump until the README
    /// is updated, exactly like the CHANGELOG and APP-STORE guards above, so the README
    /// can never silently drift behind a release again.
    @Test func readmeStatusMatchesTheProjectVersion() throws {
        let readme = try Self.text("README.md")
        let marketingVersion = try Self.marketingVersion()

        #expect(
            readme.contains("status-v\(marketingVersion)"),
            "README.md status badge must name project version v\(marketingVersion) (stale badge — bump it with the release)"
        )

        let statusSection = try #require(
            Self.section(named: "Status", in: readme),
            "README.md must keep a `## Status` section")
        #expect(
            statusSection.contains("v\(marketingVersion)"),
            "README.md `## Status` section must name project version v\(marketingVersion)")
    }

    // MARK: - Contract: App Sandbox remains enabled; entitlements minimal and justified

    /// The App Sandbox stays enabled and the entitlement set is the minimal minimal set —
    /// the App Store-compatible posture. Asserted against the real entitlements so the App
    /// Store readiness claim is concrete: the App Store requires the sandbox, and nothing
    /// broader than user-selected file access may appear.
    @Test func appSandboxStaysEnabledAndEntitlementsStayMinimal() throws {
        let entitlements = try Self.entitlements()
        #expect(
            entitlements["com.apple.security.app-sandbox"] as? Bool == true,
            "App Store builds must keep the App Sandbox enabled")
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
            App Store entitlement set drifted from the documented minimal set. \
            Found \(keys.sorted()). Update docs/APP-STORE.md, docs/PERMISSIONS.md, and the \
            tests in the same change.
            """)
    }

    /// The doc must state that the App Sandbox remains enabled and that the entitlement set
    /// is minimal and justified — the contract criterion in prose, beside the entitlement
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

    // MARK: - Contract: network entitlement absent for local rendering App Store builds

    /// local rendering App Store builds request **no network**: the network-client entitlement is
    /// absent from the shipped entitlements (so a network-free build provably cannot reach the
    /// network), and the doc states this for the App Store channel.
    @Test func appStoreBuildsRequestNoNetwork() throws {
        let entitlements = try Self.entitlements()
        #expect(
            entitlements[NetworkCapability.networkClientEntitlement] == nil,
            "local rendering App Store builds must not request \(NetworkCapability.networkClientEntitlement)"
        )

        let doc = try Self.doc()
        #expect(doc.localizedCaseInsensitiveContains("no network"))
        #expect(
            doc.contains(NetworkCapability.networkClientEntitlement),
            "APP-STORE.md must name the network-client entitlement it says is absent")
    }

    // MARK: - URL capture channel boundary

    /// URL capture ships in the direct-download channel while the App Store channel stays
    /// network-free. The doc must state the local WebKit posture, capability gate, disclosure,
    /// and drift guard without presenting unshipped App Store work as current behavior.
    @Test func documentsTheURLCaptureChannelBoundary() throws {
        let doc = try Self.doc()
        let prose = doc.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(prose.localizedCaseInsensitiveContains("web capture"))
        #expect(prose.localizedCaseInsensitiveContains("URL capture"))
        // The page loads locally in WebKit — no remote screenshot service.
        #expect(prose.localizedCaseInsensitiveContains("locally in WebKit"))
        #expect(prose.localizedCaseInsensitiveContains("no remote screenshot service"))
        #expect(doc.contains(NetworkCapability.networkClientEntitlement))
        #expect(prose.localizedCaseInsensitiveContains("direct-download channel"))
        #expect(prose.localizedCaseInsensitiveContains("App Store channel"))
        #expect(doc.contains("NetworkCapability"))
        #expect(prose.localizedCaseInsensitiveContains("first-use disclosure"))
        #expect(doc.contains("Tests/PrivacyManifestTests.swift"))
    }

    // MARK: - Contract: App Store privacy labels listed and match PrivacyInfo.xcprivacy

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
            "APP-STORE.md must list the App Store privacy labels")
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

    // MARK: - Contract: supported TestFlight delivery paths are documented

    /// The TestFlight upload path must be documented through Xcode Organizer, Transporter,
    /// or authenticated `xcodebuild`. Assert all three are present so the
    /// "any of these" contract is genuinely covered, not just one path.
    @Test func documentsTheTestFlightUploadPaths() throws {
        let doc = try Self.doc()
        #expect(doc.localizedCaseInsensitiveContains("TestFlight"))
        // Xcode Organizer path.
        #expect(
            doc.localizedCaseInsensitiveContains("Organizer"),
            "APP-STORE.md must document the Xcode Organizer upload path")
        // Transporter path.
        #expect(
            doc.contains("Transporter"),
            "APP-STORE.md must document the Transporter upload path")
        // Supported command-line path.
        #expect(
            doc.contains("xcodebuild -exportArchive"),
            "APP-STORE.md must document the Xcode command-line delivery path")
        #expect(!doc.contains("xcrun altool"), "APP-STORE.md must not recommend deprecated altool")
        // The upload step itself is named.
        #expect(doc.localizedCaseInsensitiveContains("upload"))
    }

    // MARK: - Contract: App Review notes explain clipboard, local rendering, launch-at-login, no telemetry

    /// The App Review notes must explain clipboard usage, local rendering, launch-at-login,
    /// and that there is no telemetry — the four points reviewers need to evaluate a
    /// menu-bar, on-device, account-less app.
    @Test func documentsAppReviewNotesCoveringTheRequiredPoints() throws {
        let doc = try Self.doc()
        #expect(
            doc.localizedCaseInsensitiveContains("App Review"),
            "APP-STORE.md must include App Review notes")
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
            "Info.plist must set LSUIElement = true so the App Review 'no Dock icon' note holds"
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
            Store review notes. Found \(usageKeys). A new usage string expands the \
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
    /// uses Xcode's validation export and contains no upload destination — the property that keeps
    /// it safe to merge on a repo without an Apple account.
    @Test func workflowIsAManualDryRunThatNeverAutoSubmits() throws {
        let workflow = try Self.workflow()
        #expect(
            workflow.contains("workflow_dispatch"),
            "appstore.yml must be manually triggered (workflow_dispatch)")
        #expect(
            workflow.contains("<string>validation</string>"),
            "appstore.yml must run Xcode validation export as a dry run")
        // The critical safety property: it must never upload/submit a build automatically.
        #expect(
            !workflow.contains("<string>upload</string>"),
            "appstore.yml must NOT upload/submit a build automatically (it is a dry run only)"
        )
        #expect(
            workflow.localizedCaseInsensitiveContains("never")
                && workflow.localizedCaseInsensitiveContains("submit"),
            "appstore.yml must document that it never submits a build")
    }

    /// The dry-run validation is gated on the App Store Connect API-key secrets so the
    /// workflow degrades gracefully: with no credentials the archive still builds and the
    /// validation step is skipped, mirroring the signed DMG pipeline. Assert the
    /// archive step and the secret gate are both present.
    @Test func workflowGatesValidationOnSecretsAndStillArchivesWithout() throws {
        let workflow = try Self.workflow()
        let fetchSparkle = try #require(
            workflow.range(of: "./scripts/fetch-sparkle.sh"),
            "the clean App Store runner must stage the local Sparkle framework before linking")
        let archive = try #require(
            workflow.range(of: "Archive (App Store dry run)"),
            "appstore.yml must contain the App Store archive step")
        #expect(
            fetchSparkle.lowerBound < archive.lowerBound,
            "the local Sparkle framework must be staged before the App Store archive links")
        // The archive always runs (buildable without an Apple Distribution identity).
        #expect(
            workflow.contains("archive"),
            "appstore.yml must archive the app")
        #expect(
            workflow.contains("CODE_SIGNING_ALLOWED=NO"),
            "the dry-run archive must retain a credential-free unsigned fallback")
        #expect(
            workflow.contains(#"if [ "${HAS_APPSTORE_CREDENTIALS}" = "true" ]"#),
            "the dry run must create a signed archive when App Store credentials are complete")
        #expect(
            workflow.contains(#"DEVELOPMENT_TEAM="${MACOS_SIGN_TEAM_ID}""#),
            "the signed archive must use the configured App Store team")
        #expect(
            workflow.contains("-allowProvisioningUpdates"),
            "the signed archive must allow Xcode to provision through App Store credentials")
        // Validation is gated on the App Store Connect API-key secret.
        #expect(
            workflow.contains("MACOS_NOTARY_KEY_P8"),
            "appstore.yml must gate validation on the App Store Connect API key")
        _ = try #require(
            workflow.range(of: "<string>validation</string>"),
            "appstore.yml must contain the Xcode validation export")
        #expect(
            workflow.contains(#"[ "${HAS_APPSTORE_CREDENTIALS}" != "true" ]"#),
            "the validation export must be gated on the complete App Store credential set")
        #expect(
            workflow.contains(#"[ -z "${MACOS_SIGN_TEAM_ID:-}" ]"#),
            "credential preparation must require the signing Team ID")
        #expect(
            workflow.contains(#"-authenticationKeyPath "${APPSTORE_KEY_P8}""#),
            "the validation export must pass Xcode the staged App Store Connect private key file")
        #expect(workflow.contains("umask 077"), "the staged private key must not be world-readable")
        #expect(
            workflow.contains("HAS_APPSTORE_CREDENTIALS"),
            "the workflow summary must reflect the complete credential set")
        #expect(!workflow.contains("altool"), "the workflow must not use deprecated altool")
    }

    /// The doc must point at the optional workflow and describe it as a credential-gated dry
    /// run that never submits, so the two stay consistent.
    @Test func documentsTheOptionalDryRunWorkflow() throws {
        let doc = try Self.doc()
        #expect(
            doc.contains("appstore.yml"),
            "APP-STORE.md must reference the optional .github/workflows/appstore.yml")
        #expect(doc.localizedCaseInsensitiveContains("dry run"))
        #expect(
            doc.localizedCaseInsensitiveContains("never")
                && (doc.localizedCaseInsensitiveContains("submit")
                    || doc.localizedCaseInsensitiveContains("upload")),
            "APP-STORE.md must say the dry-run workflow never submits/uploads a build")
    }
}
