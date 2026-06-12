import Foundation
import Testing

/// CS-061 — Signing, notarization, and Gatekeeper validation.
///
/// These tests assert that the committed release tooling actually encodes every
/// acceptance criterion of the ticket, so a future edit that drops Developer ID
/// signing, the hardened runtime, notarization, stapling, the `codesign --verify`
/// pass, the `spctl` Gatekeeper assessment, or the "unsigned is not production-ready"
/// guarantee fails the unit suite rather than silently shipping an untrusted artifact.
///
/// Like `WorkflowConfigurationTests` (CS-060) and `PrivacyManifestTests`, they read
/// the committed files from the source tree (anchored to this file via `#filePath`)
/// rather than any built bundle, because the signing pipeline itself cannot run in a
/// hosted unit test without Developer ID secrets. CI runs an unsigned local dry run of
/// `build-dmg.sh`; this suite is the structural guard that the *signed* path stays
/// complete.
@Suite("Release signing & notarization · CS-061")
struct ReleaseSigningTests {

    // MARK: - Repository anchoring

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

    private static func script() throws -> String {
        try text("scripts", "build-dmg.sh")
    }

    private static func release() throws -> String {
        try text(".github", "workflows", "release.yml")
    }

    private static func releasingDoc() throws -> String {
        try text("docs", "RELEASING.md")
    }

    private static func projectYAML() throws -> String {
        try text("project.yml")
    }

    // MARK: - Files exist

    @Test func theReleaseToolingFilesExist() {
        let fileManager = FileManager.default
        for path in [
            Self.url("scripts", "build-dmg.sh"),
            Self.url(".github", "workflows", "release.yml"),
            Self.url("docs", "RELEASING.md"),
        ] {
            #expect(
                fileManager.fileExists(atPath: path.path),
                "CS-061 expects \(path.lastPathComponent) to exist")
        }
    }

    /// The packaging script must be executable so the release workflow can invoke it
    /// directly (`./scripts/build-dmg.sh`).
    @Test func theBuildScriptIsExecutable() throws {
        let path = Self.url("scripts", "build-dmg.sh").path
        #expect(
            FileManager.default.isExecutableFile(atPath: path),
            "scripts/build-dmg.sh must be executable")
    }

    // MARK: - Acceptance: sign with a Developer ID Application certificate when secrets exist

    @Test func scriptSignsWithDeveloperIDWhenAnIdentityIsProvided() throws {
        let script = try Self.script()
        // The identity comes from CODE_SIGN_IDENTITY, and a real identity is anything
        // other than the ad-hoc "-" sentinel.
        #expect(
            script.contains("CODE_SIGN_IDENTITY"),
            "build-dmg.sh must read the signing identity from CODE_SIGN_IDENTITY (CS-061)")
        #expect(
            script.contains("CODE_SIGN_STYLE=Manual"),
            "build-dmg.sh must use manual signing so the Developer ID identity is honored")
        // It must branch on whether a real identity was supplied (vs. unsigned).
        #expect(
            script.contains("!= \"-\""),
            "build-dmg.sh must distinguish a real Developer ID identity from the ad-hoc sentinel")
    }

    /// The release workflow must supply the Developer ID identity and import the
    /// signing certificate into the runner keychain, gated on the certificate secret.
    @Test func releaseWorkflowImportsTheDeveloperIDCertificateWhenPresent() throws {
        let release = try Self.release()
        #expect(
            release.contains("MACOS_CODE_SIGN_IDENTITY"),
            "release.yml must pass the Developer ID identity secret to the build")
        #expect(
            release.contains("security create-keychain") && release.contains("security import"),
            "release.yml must import the signing certificate into a runner keychain (CS-061)")
        #expect(
            release.contains("security set-key-partition-list"),
            "release.yml must authorize codesign to use the imported key non-interactively")
        // The import step must be gated on the certificate secret so an unsigned
        // fallback build still works when it is absent.
        let importMarker = try #require(
            release.range(of: "Import Developer ID certificate"),
            "release.yml must declare a certificate-import step")
        let stepRegion = String(release[importMarker.lowerBound...].prefix(400))
        #expect(
            stepRegion.contains("MACOS_CERTIFICATE_P12 != ''"),
            "the certificate-import step must be gated on the certificate secret (CS-061)")
    }

    // MARK: - Acceptance: hardened runtime remains enabled for distributable builds

    @Test func hardenedRuntimeStaysEnabledForSignedBuilds() throws {
        // The app target enables the hardened runtime in the source of truth…
        let project = try Self.projectYAML()
        #expect(
            project.contains("ENABLE_HARDENED_RUNTIME: YES"),
            "project.yml must enable the hardened runtime on the app target (CS-061)")
        // …and the signed build path re-asserts it so a Developer ID build can never
        // ship without it.
        let script = try Self.script()
        #expect(
            script.contains("ENABLE_HARDENED_RUNTIME=YES"),
            "build-dmg.sh must pass ENABLE_HARDENED_RUNTIME=YES on the signed build (CS-061)")
    }

    /// Apple notarization requires a secure timestamp on Developer ID signatures.
    /// Xcode's headless build path can otherwise emit `--timestamp=none`, which
    /// still passes local `codesign --verify` but comes back from notarytool as
    /// Invalid. Pin the explicit flag in the signed xcodebuild invocation so every
    /// nested code-sign step (the app, Sparkle, helpers, and Swift libraries) gets
    /// a timestamp before submission.
    @Test func signedBuildRequestsSecureTimestampForNotarization() throws {
        let script = try Self.script()
        #expect(
            script.contains("OTHER_CODE_SIGN_FLAGS=\"--timestamp\""),
            "Developer ID release builds must request secure timestamps before notarization (CS-061)"
        )
        #expect(
            script.localizedCaseInsensitiveContains("secure timestamp"),
            "build-dmg.sh should explain why the timestamp flag is required")
    }

    /// The embedded `vitrine` CLI (Contents/MacOS/vitrine-cli) is copied into the
    /// bundle by a build phase, so Xcode's signing pass leaves it with its
    /// build-time signature. Notarization requires every nested Mach-O to carry a
    /// Developer ID signature with the hardened runtime, so the signed path must
    /// re-sign it explicitly — and before the outer app is re-sealed.
    @Test func signedBuildSignsTheEmbeddedCLI() throws {
        let script = try Self.script()
        #expect(
            script.contains("sign_embedded_cli_for_distribution"),
            "build-dmg.sh must sign the embedded vitrine CLI for notarization (CS-033/CS-061)")
        #expect(
            script.contains("Contents/MacOS/vitrine-cli"),
            "build-dmg.sh must sign the CLI at the path the embed build phase produces")
        let cliSign = try #require(
            script.range(of: "sign_embedded_cli_for_distribution\n"),
            "the signed path must invoke the CLI signing step")
        let sparkleReseal = try #require(
            script.range(of: "resign_sparkle_for_distribution\n"),
            "the signed path must invoke the Sparkle re-signing step")
        #expect(
            cliSign.lowerBound < sparkleReseal.lowerBound,
            "the CLI must be signed before the Sparkle step's final app re-seal (CS-061)")
    }

    /// The tag workflow builds and packages directly instead of using Xcode's
    /// Archive/Export path. In that mode Xcode can leak development entitlements
    /// into the signed app and can leave Sparkle's nested helpers ad-hoc signed, so
    /// the script must explicitly perform the distribution-only repair before
    /// submitting to Apple.
    @Test func signedBuildReSignsSparkleHelpersAndRejectsDevelopmentEntitlements() throws {
        let script = try Self.script()
        #expect(
            script.contains("CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO"),
            "Developer ID builds must not inject get-task-allow into distribution entitlements"
        )
        #expect(
            script.contains("com.apple.security.get-task-allow"),
            "build-dmg.sh must fail fast if get-task-allow leaks into a notarized app")
        for helper in [
            "XPCServices/Installer.xpc",
            "XPCServices/Downloader.xpc",
            "Versions/B/Autoupdate",
            "Versions/B/Updater.app",
            "Sparkle.framework",
        ] {
            #expect(
                script.contains(helper),
                "build-dmg.sh must re-sign Sparkle helper \(helper) for Developer ID notarization")
        }
        #expect(
            script.contains("--preserve-metadata=entitlements"),
            "Sparkle's Downloader.xpc and the app must preserve their expanded entitlements when re-signed"
        )
        let signingLines = script.components(separatedBy: .newlines).filter {
            $0.contains("codesign") && $0.contains("--sign")
        }
        #expect(
            signingLines.allSatisfy { !$0.contains("--deep") },
            "Sparkle's nested helpers must be signed explicitly; --deep would smear entitlements across helpers"
        )
    }

    // MARK: - Acceptance: notarization with notarytool or App Store Connect API credentials

    @Test func notarizationUsesNotarytoolWithEitherCredentialStyle() throws {
        let script = try Self.script()
        #expect(
            script.contains("notarytool submit"),
            "build-dmg.sh must notarize with `notarytool submit` (CS-061)")
        #expect(
            script.contains("--wait"),
            "notarization must wait for the result before stapling")

        // Apple ID credential style.
        for cred in ["MACOS_NOTARY_APPLE_ID", "MACOS_NOTARY_PASSWORD", "MACOS_NOTARY_TEAM_ID"] {
            #expect(
                script.contains(cred),
                "build-dmg.sh must support the Apple ID notarization credential \(cred)")
        }
        // App Store Connect API key style.
        for cred in ["MACOS_NOTARY_KEY_ID", "MACOS_NOTARY_KEY_ISSUER_ID", "MACOS_NOTARY_KEY_P8"] {
            #expect(
                script.contains(cred),
                "build-dmg.sh must support the App Store Connect API credential \(cred)")
        }
        // The API key must be wired to notarytool's --key / --issuer flags.
        #expect(
            script.contains("--key ") && script.contains("--issuer"),
            "build-dmg.sh must pass the App Store Connect API key to notarytool (CS-061)")
    }

    /// A rejected notary submission is not staplable; the script must parse the
    /// `notarytool submit --output-format plist` result, fetch the detailed notary
    /// log, and stop before attempting `stapler`. Otherwise GitHub Actions only
    /// shows "Record not found" from stapler and hides the real signing issue.
    @Test func scriptSurfacesRejectedNotarySubmissionsBeforeStapling() throws {
        let script = try Self.script()
        #expect(
            script.contains("--output-format plist"),
            "build-dmg.sh must capture structured notarytool output (CS-061)")
        #expect(
            script.contains("notarytool log"),
            "build-dmg.sh must fetch the notary log when Apple rejects a submission")
        #expect(
            script.contains("status") && script.contains("Accepted"),
            "build-dmg.sh must parse and require an Accepted notarization status before stapling")
        #expect(
            script.contains("submit_for_notarization \"$ZIP\" \"app\"")
                && script.contains("xcrun stapler staple \"$APP\""),
            "app stapling must happen only after the accepted-submission helper returns")
    }

    /// The release workflow must thread both credential styles through to the script
    /// and stage the App Store Connect `.p8` key when that secret is present.
    @Test func releaseWorkflowPassesNotarizationCredentials() throws {
        let release = try Self.release()
        for secret in [
            "MACOS_NOTARY_APPLE_ID", "MACOS_NOTARY_PASSWORD", "MACOS_NOTARY_TEAM_ID",
            "MACOS_NOTARY_KEY_ID", "MACOS_NOTARY_KEY_ISSUER_ID", "MACOS_NOTARY_KEY_P8",
        ] {
            #expect(
                release.contains(secret),
                "release.yml must forward the notarization secret \(secret) (CS-061)")
        }
        // The .p8 staging step must be gated on its secret.
        let stageMarker = try #require(
            release.range(of: "Stage App Store Connect API key"),
            "release.yml must declare the App Store Connect key staging step")
        let stepRegion = String(release[stageMarker.lowerBound...].prefix(400))
        #expect(
            stepRegion.contains("MACOS_NOTARY_KEY_P8 != ''"),
            "the key-staging step must be gated on the .p8 secret (CS-061)")
    }

    // MARK: - Acceptance: stapling succeeds for the app and/or DMG

    @Test func staplingRunsForTheAppAndDMG() throws {
        let script = try Self.script()
        #expect(
            script.contains("stapler staple"),
            "build-dmg.sh must staple the notarization ticket (CS-061)")
        // Stapling must target both the app and the DMG container.
        #expect(
            script.contains("stapler staple \"$APP\""),
            "build-dmg.sh must staple the app bundle")
        #expect(
            script.contains("stapler staple \"$DMG\""),
            "build-dmg.sh must staple the DMG")
    }

    // MARK: - Acceptance: codesign --verify --deep --strict --verbose=2 on the app

    @Test func scriptVerifiesTheSignatureStrictly() throws {
        let script = try Self.script()
        #expect(
            script.contains("codesign --verify --deep --strict --verbose=2 \"$APP\""),
            "build-dmg.sh must run `codesign --verify --deep --strict --verbose=2` on the app (CS-061)"
        )
    }

    // MARK: - Acceptance: spctl -a -vv on the final artifact

    @Test func scriptAssessesGatekeeperOnTheFinalArtifact() throws {
        let script = try Self.script()
        #expect(
            script.contains("spctl -a -vv"),
            "build-dmg.sh must run a Gatekeeper assessment with `spctl -a -vv` (CS-061)")
        // The assessment must cover the DMG (the downloaded artifact) and the app.
        #expect(
            script.contains("spctl -a -vv \"$APP\""),
            "build-dmg.sh must assess the app bundle with spctl")
        #expect(
            script.contains("\"$DMG\""),
            "build-dmg.sh must assess the final DMG artifact with spctl")
    }

    // MARK: - Acceptance: unsigned local DMG path remains available but never production-ready

    @Test func unsignedPathRemainsAvailableButIsNeverLabeledProductionReady() throws {
        let script = try Self.script()
        // An unsigned build must still produce a DMG (the dev path is preserved): the
        // hdiutil create step is unconditional.
        #expect(
            script.contains("hdiutil create"),
            "build-dmg.sh must still build a DMG on the unsigned path (CS-061)")
        // And the unsigned build must be explicitly flagged as not production-ready.
        #expect(
            script.localizedCaseInsensitiveContains("not production-ready")
                || script.localizedCaseInsensitiveContains("NOT production-ready"),
            "build-dmg.sh must label the unsigned build as not production-ready (CS-061)")
        #expect(
            script.localizedCaseInsensitiveContains("unsigned"),
            "build-dmg.sh must describe the unsigned development path")
    }

    /// The packaged DMG path and verification must not run unconditionally on an
    /// unsigned build: the verify/notarize/sign steps are guarded by the SIGNED flag,
    /// so `set -euo pipefail` cannot abort an unsigned dev build on a missing identity.
    @Test func signingStepsAreGuardedSoUnsignedBuildsDoNotFail() throws {
        let script = try Self.script()
        #expect(
            script.contains("set -euo pipefail"),
            "build-dmg.sh must use strict bash mode")
        #expect(
            script.contains("SIGNED=1") && script.contains("SIGNED=0"),
            "build-dmg.sh must track whether the build is signed so unsigned runs skip signing")
        // The codesign --verify command must live behind the SIGNED guard, not at top
        // level, so an unsigned build does not try to verify a non-existent signature.
        // Anchor on the full command line (with its `"$APP"` argument) so the
        // header-comment mentions of the same flags are not matched — only the
        // executable line is. The command must be (a) preceded by a SIGNED guard and
        // (b) indented, proving it runs inside that block rather than unconditionally.
        let verifyCommand = "codesign --verify --deep --strict --verbose=2 \"$APP\""
        let commandLine = try #require(
            script.components(separatedBy: .newlines).first { $0.contains(verifyCommand) },
            "build-dmg.sh must contain the codesign verify command")
        #expect(
            commandLine.first == "\t" || commandLine.first == " ",
            "the codesign verify command must be indented inside a guard block (CS-061)")
        let verifyMarker = try #require(script.range(of: verifyCommand))
        let beforeVerify = String(script[..<verifyMarker.lowerBound])
        let lastGuard = beforeVerify.range(
            of: "if [ \"$SIGNED\" -eq 1 ]", options: .backwards)
        #expect(
            lastGuard != nil,
            "the strict codesign verification must be guarded by the SIGNED flag (CS-061)")
    }

    /// Notarization and stapling must also live behind the SIGNED guard. Under
    /// `set -euo pipefail`, an unsigned dev build would abort if `notarytool submit`
    /// or `stapler staple "$APP"` ran unconditionally (there is no signature to
    /// notarize and no ticket to staple). This complements the `codesign --verify`
    /// guard check and pins the property that the unsigned path stays buildable even
    /// as the signed path grows new steps.
    @Test func notarizationAndStaplingAreGuardedSoUnsignedBuildsDoNotFail() throws {
        let script = try Self.script()
        // Each command must be preceded by a SIGNED guard (so it runs inside the
        // signed branch) rather than appearing at the top level of the script.
        for command in ["xcrun notarytool submit", "xcrun stapler staple \"$APP\""] {
            let marker = try #require(
                script.range(of: command),
                "build-dmg.sh must contain `\(command)`")
            let preceding = String(script[..<marker.lowerBound])
            #expect(
                preceding.range(of: "if [ \"$SIGNED\" -eq 1 ]", options: .backwards) != nil,
                "`\(command)` must be guarded by the SIGNED flag so unsigned builds skip it (CS-061)"
            )
        }
    }

    /// CS-061 (and both `build-dmg.sh`'s header and `RELEASING.md`) promise the App
    /// Store Connect API key takes precedence over the Apple-ID credentials when both
    /// are configured. This asserts the credential selection is an ordered if/elif
    /// whose API-key branch is evaluated first, so a future reorder that silently
    /// flips the precedence fails the suite.
    @Test func appStoreConnectKeyTakesPrecedenceOverAppleID() throws {
        let script = try Self.script()
        // The API-key key id must be tested before the Apple-ID is tested, and the
        // Apple-ID branch must be an `elif` (not a second independent `if`), proving a
        // single ordered selection where the key wins when both are present.
        let apiKeyTest = try #require(
            script.range(of: "if [ -n \"${MACOS_NOTARY_KEY_ID:-}\" ]"),
            "build-dmg.sh must test the App Store Connect key id first")
        let appleIDTest = try #require(
            script.range(of: "elif [ -n \"${MACOS_NOTARY_APPLE_ID:-}\" ]"),
            "the Apple-ID branch must be an `elif`, making the API key win when both are set (CS-061)"
        )
        #expect(
            apiKeyTest.lowerBound < appleIDTest.lowerBound,
            "the App Store Connect API-key branch must precede the Apple-ID branch (CS-061)")
    }

    // MARK: - Acceptance: documentation

    @Test func releasingDocDocumentsSigningNotarizationAndGatekeeper() throws {
        let doc = try Self.releasingDoc()
        #expect(
            doc.contains("CS-061"),
            "RELEASING.md must reference the signing/notarization ticket")
        #expect(
            doc.localizedCaseInsensitiveContains("Developer ID"),
            "RELEASING.md must document Developer ID signing")
        #expect(
            doc.localizedCaseInsensitiveContains("notariz"),
            "RELEASING.md must document notarization")
        #expect(
            doc.localizedCaseInsensitiveContains("hardened runtime"),
            "RELEASING.md must note the hardened runtime requirement")
        #expect(
            doc.localizedCaseInsensitiveContains("secure timestamp"),
            "RELEASING.md must document the secure timestamp requirement for notarization")
        #expect(
            doc.contains("notarytool log"),
            "RELEASING.md must document that rejected submissions are diagnosed with the notary log"
        )
        #expect(
            doc.contains("codesign --verify --deep --strict --verbose=2"),
            "RELEASING.md must document the codesign verification command (CS-061)")
        #expect(
            doc.contains("spctl -a -vv"),
            "RELEASING.md must document the Gatekeeper assessment command (CS-061)")
        #expect(
            doc.localizedCaseInsensitiveContains("not production-ready"),
            "RELEASING.md must say the unsigned build is not production-ready (CS-061)")
        // Both notarization credential styles must be documented.
        #expect(
            doc.contains("MACOS_NOTARY_KEY_P8") && doc.contains("MACOS_NOTARY_APPLE_ID"),
            "RELEASING.md must document both notarization credential styles (CS-061)")
    }
}
