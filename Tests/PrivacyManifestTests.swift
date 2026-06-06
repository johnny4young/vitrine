import Foundation
import Testing

@testable import Vitrine

/// CS-065 — Permission and entitlement matrix.
///
/// These suites are the drift guard for the permission posture documented in
/// `docs/PERMISSIONS.md`. The matrix is only trustworthy if the shipped entitlements,
/// `Info.plist` usage strings, and privacy manifest actually match it, so each check
/// reads the **committed** resource files (anchored to this file via `#filePath`, since
/// those files are not compiled into the test bundle) and fails if they drift from the
/// matrix without an explicit update:
///
/// - The entitlement set stays the Phase 1 set — sandbox + user-selected files — with
///   **no network and no Screen Recording**; every key present is named in the matrix.
/// - The only `Info.plist` usage string is the clipboard one, and **no** Screen Recording
///   usage string is declared.
/// - The privacy manifest declares no tracking and no collected data.
/// - The matrix itself documents every required context (Phase 1, Phase 2 URL, optional
///   screen/window capture, CLI, App Store, direct download) and the specific claims the
///   CS-065 acceptance criteria require.
///
/// This complements `PrivacyManifestTests` (CS-011, in `PrivacyTests.swift`), which
/// asserts the *bundled* manifest from `Bundle.main`; here we tie the *source* files to
/// the matrix document. No SwiftUI `body` is rendered, so the suites stay clear of
/// CoreText under the parallel runner.
enum PermissionMatrix {
    /// The repository root, anchored to this file (`<repo>/Tests/…`), so the checks read
    /// the committed resource files and docs rather than the built bundle. Mirrors
    /// `WebSnapshotPrivacyUXTests` and `ScreenCaptureDecisionTests`, which anchor the same
    /// way.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    static func file(_ components: String...) -> URL {
        components.reduce(repositoryRoot) { $0.appendingPathComponent($1) }
    }

    static func text(_ components: String...) throws -> String {
        try String(
            contentsOf: components.reduce(repositoryRoot) { $0.appendingPathComponent($1) },
            encoding: .utf8)
    }

    /// The committed app-target entitlements, parsed as a property list.
    static func entitlements() throws -> [String: Any] {
        let data = try Data(contentsOf: file("Vitrine", "Resources", "Vitrine.entitlements"))
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Vitrine.entitlements must be a property list")
    }

    /// The committed app-target `Info.plist`, parsed as a property list.
    static func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: file("Vitrine", "Resources", "Info.plist"))
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Info.plist must be a property list")
    }

    /// The committed privacy manifest, parsed as a property list.
    static func privacyManifest() throws -> [String: Any] {
        let data = try Data(contentsOf: file("Vitrine", "Resources", "PrivacyInfo.xcprivacy"))
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "PrivacyInfo.xcprivacy must be a property list")
    }

    /// The permission-matrix document.
    static func matrix() throws -> String {
        try text("docs", "PERMISSIONS.md")
    }

    /// The committed `project.yml` — the source of truth for the generated, git-ignored
    /// `Vitrine.xcodeproj`. The CLI row of the matrix promises its checks read this file
    /// (the `VitrineCLI` target sets no entitlements and excludes the web-rendering
    /// surface), so the suite asserts against it rather than the generated project.
    static func projectYAML() throws -> String {
        try text("project.yml")
    }

    /// The body of the `VitrineCLI` target as declared under the top-level `targets:`
    /// section of `project.yml`, sliced by indentation.
    ///
    /// `project.yml` has no YAML parser linked into the test bundle, and a substring search
    /// for `VitrineCLI:` is ambiguous: the name also appears under `schemes:`. This walks
    /// the file, enters the `targets:` section, and captures the lines from `  VitrineCLI:`
    /// up to the next two-space-indented sibling target (or the next top-level section), so
    /// the returned text is exactly the CLI *target* declaration and never the scheme entry.
    static func cliTargetBlock() throws -> String {
        let yaml = try projectYAML()
        var inTargets = false
        var inCLI = false
        var captured: [String] = []

        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            // A non-indented, non-blank line starts a new top-level section.
            let isTopLevel = !isBlank && !line.hasPrefix(" ")
            // A two-space-indented key (e.g. `  VitrineCLI:`) is a target entry.
            let isTargetEntry = line.hasPrefix("  ") && !line.hasPrefix("   ")

            if !inTargets {
                if isTopLevel && line.hasPrefix("targets:") { inTargets = true }
                continue
            }

            // Leaving the targets section ends the search.
            if isTopLevel { break }

            if isTargetEntry {
                // A sibling target boundary: start capturing at VitrineCLI, stop at the next.
                if inCLI { break }
                if line.hasPrefix("  VitrineCLI:") {
                    inCLI = true
                    captured.append(line)
                }
                continue
            }

            if inCLI { captured.append(line) }
        }

        return captured.joined(separator: "\n")
    }

    /// The exact Phase 1 entitlement set the matrix documents: the App Sandbox plus
    /// user-selected file access, and nothing else. Anything beyond this is a drift that
    /// the suite flags.
    static let phase1EntitlementKeys: Set<String> = [
        "com.apple.security.app-sandbox",
        "com.apple.security.files.user-selected.read-write",
    ]
}

// MARK: - Entitlement plist tests

/// The shipped app-target entitlements must match the Phase 1 row of the matrix exactly:
/// sandbox on, user-selected file access, and **no network, no Screen Recording**. These
/// are the "entitlement plist tests" CS-065 calls for, and the guard that "tests fail if
/// entitlements drift from the matrix without an explicit update."
@Suite("Entitlement matrix · CS-065")
struct EntitlementMatrixTests {

    /// The App Sandbox is on. This is the baseline Phase 1 containment the matrix
    /// documents and the App Store requires.
    @Test func sandboxIsEnabled() throws {
        let entitlements = try PermissionMatrix.entitlements()
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
    }

    /// User-selected file access is granted (for save/open panels and dropped files), and
    /// no *broader* file entitlement is present — the matrix states this single key covers
    /// every file the app touches.
    @Test func grantsOnlyUserSelectedFileAccess() throws {
        let entitlements = try PermissionMatrix.entitlements()
        #expect(
            entitlements["com.apple.security.files.user-selected.read-write"] as? Bool == true)

        // No broader file-access entitlement may be added alongside it.
        let broaderFileKeys = [
            "com.apple.security.files.all",
            "com.apple.security.files.downloads.read-write",
            "com.apple.security.temporary-exception.files.home-relative-path.read-write",
        ]
        for key in broaderFileKeys {
            #expect(
                entitlements[key] == nil, "Phase 1 must not request the broader \(key) entitlement")
        }
    }

    /// Phase 1 must request **no network**: the network-client entitlement is absent, so a
    /// Phase 1 build provably cannot reach the network (`NetworkCapability` reads this same
    /// key at runtime and refuses URL capture). This is the matrix's "Phase 1 says no
    /// network" claim asserted against the real entitlements.
    @Test func phase1RequestsNoNetwork() throws {
        let entitlements = try PermissionMatrix.entitlements()
        #expect(
            entitlements[NetworkCapability.networkClientEntitlement] == nil,
            "Phase 1 must not request \(NetworkCapability.networkClientEntitlement) (no network).")
    }

    /// Phase 1 must request **no Screen Recording**. macOS surfaces that grant at runtime
    /// via TCC rather than one fixed entitlement key, so this matches defensively on any
    /// key naming recording/capture of the screen. None exist today; this fails loudly if
    /// one is added — the matrix's "Phase 1 says no Screen Recording" claim, enforced.
    @Test func phase1RequestsNoScreenRecording() throws {
        let entitlements = try PermissionMatrix.entitlements()
        let screenKeys = entitlements.keys.filter { key in
            let lowered = key.lowercased()
            return lowered.contains("screen")
                && (lowered.contains("record") || lowered.contains("capture"))
        }
        #expect(
            screenKeys.isEmpty,
            "Phase 1 must request no Screen Recording entitlement. Found: \(screenKeys)")
    }

    /// The entitlement set is **exactly** the Phase 1 set — no more, no less. Pinning the
    /// full key set (not just individual presences/absences) means *any* added entitlement,
    /// not only network/screen ones, trips this test and forces a matrix + test update in
    /// the same change. Every key here must also be documented in the matrix (asserted in
    /// `PermissionMatrixDocumentTests`).
    @Test func entitlementSetIsExactlyThePhase1Set() throws {
        let entitlements = try PermissionMatrix.entitlements()
        let keys = Set(entitlements.keys)
        #expect(
            keys == PermissionMatrix.phase1EntitlementKeys,
            """
            Entitlements drifted from the Phase 1 matrix set. Expected exactly \
            \(PermissionMatrix.phase1EntitlementKeys.sorted()), found \(keys.sorted()). \
            Update docs/PERMISSIONS.md and this test in the same change (CS-065).
            """)
    }

    /// Every entitlement key the app actually ships must be named in the matrix document,
    /// so the audit table can never silently omit a live entitlement. (The reverse — the
    /// matrix naming a *deferred* key like the network entitlement that is not yet shipped
    /// — is allowed and expected.)
    @Test func everyShippedEntitlementIsNamedInTheMatrix() throws {
        let entitlements = try PermissionMatrix.entitlements()
        let matrix = try PermissionMatrix.matrix()
        for key in entitlements.keys {
            #expect(
                matrix.contains(key),
                "Shipped entitlement \(key) is not documented in docs/PERMISSIONS.md (CS-065).")
        }
    }
}

// MARK: - Info.plist usage-string tests

/// The "Info.plist usage-string tests" CS-065 calls for: the only declared usage string is
/// the clipboard one, it keeps the Phase 1 promise, and **no** Screen Recording usage
/// string is declared.
@Suite("Info.plist usage strings · CS-065")
struct InfoPlistUsageStringTests {

    /// `NSPasteboardUsageDescription` is present, non-empty, and keeps the Phase 1 promise
    /// ("never leaves your Mac") while naming local-WebKit capture for Phase 2 — the matrix
    /// row for the clipboard usage string.
    @Test func clipboardUsageStringIsPresentAndKeepsThePromise() throws {
        let plist = try PermissionMatrix.infoPlist()
        let usage = try #require(
            plist["NSPasteboardUsageDescription"] as? String,
            "Info.plist must carry the clipboard usage description (CS-065).")
        #expect(!usage.isEmpty)
        #expect(usage.localizedCaseInsensitiveContains("never leaves your Mac"))
        #expect(usage.localizedCaseInsensitiveContains("locally in WebKit"))
    }

    /// No Screen Recording usage string may be declared. A capture feature would require
    /// `NSScreenCaptureUsageDescription`; its absence is part of the matrix's "no Screen
    /// Recording" guarantee for every shipping phase.
    @Test func noScreenRecordingUsageString() throws {
        let plist = try PermissionMatrix.infoPlist()
        #expect(
            plist["NSScreenCaptureUsageDescription"] == nil,
            "Arbitrary screen capture is parked; no Screen Recording usage string may ship (CS-065)."
        )
    }

    /// No other privacy-sensitive usage string (camera, microphone, Accessibility, etc.)
    /// is declared. The matrix lists clipboard as the *only* declared usage; this fails if
    /// any other `NS…UsageDescription` appears, forcing a matrix update.
    @Test func clipboardIsTheOnlyDeclaredUsageString() throws {
        let plist = try PermissionMatrix.infoPlist()
        let usageKeys = plist.keys.filter { $0.hasSuffix("UsageDescription") }
        #expect(
            Set(usageKeys) == ["NSPasteboardUsageDescription"],
            """
            The clipboard usage string must be the only declared usage string. Found \
            \(usageKeys.sorted()). Document any new usage in docs/PERMISSIONS.md and this \
            test in the same change (CS-065).
            """)
    }

    /// The app stays a menu-bar agent (`LSUIElement`) and declares no network exception in
    /// `Info.plist` (App Transport Security is not relaxed) — both consistent with the
    /// matrix's minimal, local-by-default posture.
    @Test func staysAMenuBarAgentWithNoRelaxedTransportSecurity() throws {
        let plist = try PermissionMatrix.infoPlist()
        #expect(plist["LSUIElement"] as? Bool == true)
        // No App Transport Security exceptions: nothing relaxes the network posture.
        #expect(
            plist["NSAppTransportSecurity"] == nil,
            "Phase 1 declares no relaxed App Transport Security (CS-065).")
    }
}

// MARK: - Privacy manifest tests (tied to the matrix)

/// The "privacy manifest tests" CS-065 calls for, asserted against the **committed**
/// `PrivacyInfo.xcprivacy` and tied to the matrix: no tracking, no collected data, and a
/// single UserDefaults required-reason API. (The bundle-loaded counterpart lives in
/// `PrivacyManifestTests` in `PrivacyTests.swift`; this one ties the source file to the
/// matrix's privacy row, including across Phase 2.)
@Suite("Privacy manifest matrix · CS-065")
struct PrivacyManifestMatrixTests {

    @Test func declaresNoTrackingNoDomainsNoCollectedData() throws {
        let plist = try PermissionMatrix.privacyManifest()
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [Any] ?? []).isEmpty)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any] ?? []).isEmpty)
    }

    /// The only required-reason API is UserDefaults (reason `CA92.1`), used for the app's
    /// own settings — exactly what the matrix's privacy row states for both Phase 1 and
    /// Phase 2.
    @Test func theOnlyRequiredReasonAPIIsUserDefaults() throws {
        let plist = try PermissionMatrix.privacyManifest()
        let apiTypes = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let categories = apiTypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        #expect(categories == ["NSPrivacyAccessedAPICategoryUserDefaults"])
        let reasons = apiTypes.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        #expect(reasons == ["CA92.1"])
    }
}

// MARK: - The matrix document itself

/// The matrix is the deliverable; asserting its substantive contents (not merely that the
/// file exists) keeps it from being silently gutted and pins the specific claims the
/// CS-065 acceptance criteria require. Reads the committed `docs/PERMISSIONS.md`.
@Suite("Permission matrix document · CS-065")
struct PermissionMatrixDocumentTests {

    /// The matrix lists every required context: Phase 1, Phase 2 URL, optional
    /// screen/window capture, CLI, App Store, and direct-download builds.
    @Test func listsEveryRequiredContext() throws {
        let matrix = try PermissionMatrix.matrix()
        // Product phases.
        #expect(matrix.localizedCaseInsensitiveContains("Phase 1"))
        #expect(matrix.localizedCaseInsensitiveContains("Product Phase 2"))
        #expect(matrix.localizedCaseInsensitiveContains("URL capture"))
        // Optional arbitrary screen/window capture.
        #expect(
            matrix.localizedCaseInsensitiveContains("screen / window capture")
                || matrix.localizedCaseInsensitiveContains("screen/window capture"))
        // CLI.
        #expect(matrix.localizedCaseInsensitiveContains("CLI"))
        // Distribution channels.
        #expect(matrix.localizedCaseInsensitiveContains("App Store"))
        #expect(
            matrix.localizedCaseInsensitiveContains("direct download")
                || matrix.localizedCaseInsensitiveContains("direct-download"))
    }

    /// Each entitlement in the matrix carries the five required attributes the acceptance
    /// criteria mandate: reason, user-facing behavior, whether it is required, a
    /// test/review check, and App Store impact. The matrix renders these as table column
    /// headers, so their presence proves the schema is in place.
    @Test func documentsTheFiveRequiredAttributesPerEntitlement() throws {
        let matrix = try PermissionMatrix.matrix()
        #expect(matrix.localizedCaseInsensitiveContains("Reason"))
        #expect(matrix.localizedCaseInsensitiveContains("User-facing behavior"))
        #expect(matrix.localizedCaseInsensitiveContains("Required?"))
        #expect(
            matrix.localizedCaseInsensitiveContains("Test / review check")
                || matrix.localizedCaseInsensitiveContains("Test/review check"))
        #expect(matrix.localizedCaseInsensitiveContains("App Store impact"))
    }

    /// The Phase 1 row says **no network and no Screen Recording** — the acceptance
    /// criterion "Phase 1 matrix says no network and no Screen Recording."
    @Test func phase1RowSaysNoNetworkAndNoScreenRecording() throws {
        let matrix = try PermissionMatrix.matrix()
        #expect(matrix.localizedCaseInsensitiveContains("no network"))
        #expect(matrix.localizedCaseInsensitiveContains("no Screen Recording"))
        // It names the network-client entitlement key so the claim is concrete.
        #expect(matrix.contains(NetworkCapability.networkClientEntitlement))
    }

    /// The Phase 2 URL row says the network client is **required only for URL loading** —
    /// the acceptance criterion "Phase 2 URL matrix says network client is required only
    /// for URL loading."
    @Test func phase2RowSaysNetworkClientRequiredOnlyForURLLoading() throws {
        let matrix = try PermissionMatrix.matrix()
        #expect(matrix.localizedCaseInsensitiveContains("required only for URL loading"))
        // And that the page loads locally in WebKit, with no remote service (the privacy
        // posture the network entitlement is scoped to).
        #expect(matrix.localizedCaseInsensitiveContains("locally in WebKit"))
        #expect(matrix.localizedCaseInsensitiveContains("no remote screenshot service"))
    }

    /// The optional screen/window capture row says Screen Recording is **required** and
    /// the capability **must stay out of core until approved** — the acceptance criterion
    /// for arbitrary capture.
    @Test func screenCaptureRowRequiresScreenRecordingAndStaysOutOfCore() throws {
        let matrix = try PermissionMatrix.matrix()
        #expect(matrix.contains("Screen Recording"))
        #expect(matrix.localizedCaseInsensitiveContains("must stay out of core until approved"))
        // It points at the discovery decision that parks it.
        #expect(matrix.contains("SCREEN-CAPTURE-DISCOVERY.md"))
    }

    /// The matrix records the change policy that makes the test the guard — that the
    /// entitlements/usage strings/manifest must not drift from the matrix silently, and
    /// that `PrivacyManifestTests.swift` enforces it.
    @Test func recordsTheNoSilentDriftPolicy() throws {
        let matrix = try PermissionMatrix.matrix()
        #expect(matrix.contains("Tests/PrivacyManifestTests.swift"))
        #expect(
            matrix.localizedCaseInsensitiveContains("minimal and reviewable")
                || matrix.localizedCaseInsensitiveContains("No silent permission additions"))
    }
}

// MARK: - CLI permission posture (tied to project.yml)

/// The CLI row of the matrix promises a *concrete, checkable* posture: the `VitrineCLI`
/// target "sets no `CODE_SIGN_ENTITLEMENTS`" and "excludes `WebRendering`, `AppIntents`,
/// and `Services`", so `NetworkCapability` and `WKWebView` are never compiled into the
/// tool. Without these checks that row is unenforced prose — the CLI target could quietly
/// gain an entitlement or pull in the web-rendering surface (and thus the network client)
/// while the matrix still claimed it had none, exactly the silent drift CS-065 exists to
/// stop. These read the committed `project.yml` (the source of truth for the generated,
/// git-ignored `Vitrine.xcodeproj`), matching how `WorkflowConfigurationTests` (CS-060)
/// asserts against the same file.
@Suite("CLI permission posture · CS-065")
struct CLIPermissionPostureTests {

    /// The `VitrineCLI` target declares **no** `CODE_SIGN_ENTITLEMENTS`: a command-line
    /// tool is not a sandboxed `.app`, so it carries none of the app's entitlements. The
    /// app target *does* set this key, so the assertion is scoped to the CLI block to prove
    /// the CLI specifically opts out — the matrix's "sets no `CODE_SIGN_ENTITLEMENTS`" claim.
    @Test func cliTargetDeclaresNoEntitlements() throws {
        let cli = try PermissionMatrix.cliTargetBlock()
        // Sanity: the slice actually captured the CLI target (guards against a refactor that
        // renames or moves it leaving an empty, vacuously-passing block).
        #expect(cli.contains("type: tool"), "Did not locate the VitrineCLI target in project.yml")
        #expect(
            !cli.contains("CODE_SIGN_ENTITLEMENTS"),
            """
            The VitrineCLI target must declare no CODE_SIGN_ENTITLEMENTS (CS-065): a CLI tool \
            is not a sandboxed app and ships none of the app's entitlements. If this changes, \
            update the CLI row of docs/PERMISSIONS.md and this test in the same change.
            """)
    }

    /// The `VitrineCLI` target **excludes** the web-rendering surface and the automation
    /// surfaces from its sources. Excluding `WebRendering` is what keeps `NetworkCapability`
    /// and `WKWebView` out of the tool entirely, so the CLI provably "cannot load a URL" and
    /// needs no network — the matrix's "excludes `WebRendering`, `AppIntents`, and
    /// `Services`" claim, and the basis for its "Network client — not used" row.
    @Test func cliTargetExcludesWebRenderingAndAutomationSurfaces() throws {
        let cli = try PermissionMatrix.cliTargetBlock()
        #expect(cli.contains("type: tool"), "Did not locate the VitrineCLI target in project.yml")
        for excluded in ["WebRendering", "AppIntents", "Services"] {
            #expect(
                cli.contains("\"\(excluded)\"") || cli.contains("- \(excluded)"),
                """
                The VitrineCLI target must exclude \(excluded) (CS-065). Excluding WebRendering \
                in particular keeps NetworkCapability and WKWebView out of the CLI, which is why \
                the matrix can say the CLI uses no network. Update the CLI row of \
                docs/PERMISSIONS.md and this test together if this changes.
                """)
        }
    }

    /// The matrix's CLI row documents the same posture in prose: no `CODE_SIGN_ENTITLEMENTS`
    /// and the specific excluded surfaces. Pinning the doc text (not just the build config)
    /// stops the row from being silently gutted while the build still happens to comply, so
    /// the two can only ever change together.
    @Test func matrixCLIRowDocumentsTheProjectYAMLPosture() throws {
        let matrix = try PermissionMatrix.matrix()
        #expect(matrix.contains("CODE_SIGN_ENTITLEMENTS"))
        #expect(matrix.contains("WebRendering"))
        #expect(matrix.contains("AppIntents"))
        #expect(matrix.contains("Services"))
        // It names the artifacts the exclusion keeps out, so the claim is concrete.
        #expect(matrix.contains("NetworkCapability"))
        #expect(matrix.contains("WKWebView"))
    }
}
