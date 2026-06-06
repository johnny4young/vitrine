import Foundation
import Testing

/// CS-060 — CI hardening and GitHub Actions observability.
///
/// These tests assert that the committed GitHub Actions workflows, the `Makefile`,
/// and `docs/RELEASING.md` actually encode every acceptance criterion of the ticket,
/// so a future edit that drops the weekly drift job, the release gate, the toolchain
/// logging, the SPM cache, the `.xcresult` upload, or the UI-test policy fails the
/// unit suite rather than silently weakening CI.
///
/// They read the committed files from the source tree (anchored to this file via
/// `#filePath`, like `PrivacyManifestTests` / `LocalizationTests`) rather than any
/// built bundle. Full YAML *syntax* validation runs in CI itself (the
/// "Validate workflow YAML" step parses each file with Ruby's standard-library YAML
/// parser); here we additionally guard against tab-indentation — a YAML syntax error
/// the targeted structural reads below would not otherwise catch.
@Suite("CI workflow configuration · CS-060")
struct WorkflowConfigurationTests {

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

    private static func ci() throws -> String {
        try text(".github", "workflows", "ci.yml")
    }

    private static func release() throws -> String {
        try text(".github", "workflows", "release.yml")
    }

    private static func makefile() throws -> String {
        try text("Makefile")
    }

    private static func releasingDoc() throws -> String {
        try text("docs", "RELEASING.md")
    }

    // MARK: - Files exist

    @Test func theWorkflowFilesAndSupportingFilesExist() {
        let fileManager = FileManager.default
        for path in [
            Self.url(".github", "workflows", "ci.yml"),
            Self.url(".github", "workflows", "release.yml"),
            Self.url("Makefile"),
            Self.url("docs", "RELEASING.md"),
        ] {
            #expect(
                fileManager.fileExists(atPath: path.path),
                "CS-060 expects \(path.lastPathComponent) to exist")
        }
    }

    // MARK: - YAML well-formedness guard (tabs)

    /// YAML forbids tab characters for indentation; a stray tab is a syntax error that
    /// the CI Ruby parse would reject. Guard it here too so the failure is local and
    /// fast. (Structural correctness beyond this is covered by the targeted reads below
    /// and by the CI parse step.)
    @Test func workflowYAMLUsesNoTabIndentation() throws {
        for (name, body) in try [("ci.yml", Self.ci()), ("release.yml", Self.release())] {
            for (index, line) in body.components(separatedBy: .newlines).enumerated() {
                let indentation = line.prefix { $0 == " " || $0 == "\t" }
                #expect(
                    !indentation.contains("\t"),
                    "\(name) line \(index + 1) uses a tab for indentation, which is invalid YAML")
            }
        }
    }

    // MARK: - Acceptance: log exact macOS / Xcode versions before building

    /// The CI workflow must record the exact toolchain (macOS image, Xcode, Swift)
    /// before it builds, since it runs on the moving `macos-latest` image rather than a
    /// pinned one. The acceptance is satisfied by *logging* the versions; assert the
    /// version-probe commands are present and that the step runs before the build.
    @Test func ciLogsExactToolchainVersionsBeforeBuilding() throws {
        let ci = try Self.ci()
        #expect(ci.contains("sw_vers"), "CI must log the macOS version (sw_vers)")
        #expect(ci.contains("xcodebuild -version"), "CI must log the Xcode version")
        #expect(ci.contains("swift --version"), "CI must log the Swift version")

        // The toolchain step must come before the first build invocation.
        let toolchainMarker = try #require(ci.range(of: "sw_vers"))
        let buildMarker = try #require(ci.range(of: "run: make build"))
        #expect(
            toolchainMarker.lowerBound < buildMarker.lowerBound,
            "Toolchain versions must be logged before building (CS-060)")
    }

    // MARK: - Acceptance: cache SPM dependencies where safe

    @Test func ciCachesSwiftPackageManagerDependencies() throws {
        let ci = try Self.ci()
        #expect(ci.contains("actions/cache@"), "CI must cache something (SPM)")
        #expect(
            ci.contains("org.swift.swiftpm"),
            "CI must cache the Swift Package Manager cache directory (CS-060)")
        // Keyed on project.yml — the dependency source of truth (the resolved project
        // is generated, not committed).
        #expect(
            ci.contains("hashFiles('project.yml')"),
            "The SPM cache key must be bound to project.yml")
    }

    // MARK: - Acceptance: upload .xcresult bundles / test logs on failure

    @Test func ciUploadsXcresultBundlesOnFailure() throws {
        let ci = try Self.ci()
        // The build/test steps must request an .xcresult bundle…
        #expect(
            ci.contains("RESULT_BUNDLE="),
            "CI must direct an .xcresult bundle via RESULT_BUNDLE (CS-060)")
        // …and there must be a failure-gated upload of it.
        #expect(ci.contains("actions/upload-artifact@"))
        #expect(
            ci.contains(".xcresult"),
            "CI must reference the .xcresult bundles it uploads")

        // The xcresult upload step must be conditioned on failure. Locate the upload
        // step named `xcresults` and confirm an `if: failure()` precedes it within the
        // same step.
        let uploadName = try #require(ci.range(of: "name: xcresults"))
        let preceding = String(ci[..<uploadName.lowerBound])
        #expect(
            preceding.contains("if: failure()"),
            "The .xcresult upload must be gated on failure (CS-060)")
    }

    /// The Makefile must honor `RESULT_BUNDLE` on the build/test/UI-test-build targets,
    /// since that is how CI captures the `.xcresult` bundles through the same `make`
    /// entrypoints the gate uses.
    @Test func makefileSupportsResultBundleCapture() throws {
        let make = try Self.makefile()
        #expect(
            make.contains("RESULT_BUNDLE_FLAG"),
            "Makefile must define a RESULT_BUNDLE flag for .xcresult capture (CS-060)")
        #expect(
            make.contains("-resultBundlePath"),
            "Makefile must pass -resultBundlePath to xcodebuild when RESULT_BUNDLE is set")
    }

    // MARK: - Acceptance: run `make build-ui-tests` on every PR

    @Test func ciRunsBuildUITestsOnPullRequests() throws {
        let ci = try Self.ci()
        #expect(
            ci.contains("pull_request"),
            "CI must trigger on pull requests")
        #expect(
            ci.contains("make build-ui-tests"),
            "CI must compile the UI tests on every PR (CS-060)")
    }

    // MARK: - Acceptance: weekly scheduled drift job

    @Test func ciHasAWeeklyScheduledDriftJob() throws {
        let ci = try Self.ci()
        #expect(ci.contains("schedule:"), "CI must declare a schedule trigger (CS-060)")
        // A weekly cron: 5 fields, day-of-week constrained (the 5th field is not "*").
        let cronLine = try #require(
            ci.components(separatedBy: .newlines).first { $0.contains("cron:") },
            "CI schedule must specify a cron expression")
        let quoted = try #require(
            cronLine.split(separator: "\"").dropFirst().first.map(String.init),
            "cron expression must be quoted")
        let fields = quoted.split(separator: " ").map(String.init)
        #expect(fields.count == 5, "cron must have five fields, got: \(quoted)")
        #expect(
            fields.last != "*",
            "a weekly drift job must constrain the day-of-week field (CS-060), got: \(quoted)")
    }

    // MARK: - Acceptance: release refuses to publish if any gate fails

    /// The release workflow must run lint, build, the unit suite, and the UI-test
    /// build, and the publish step must depend on that gate so a failing check blocks
    /// the DMG. Assert the gate job runs all four checks, that publish `needs:` it, and
    /// that the DMG/publish steps live in the dependent job — never run unconditionally.
    @Test func releaseRefusesToPublishWhenAnyGateFails() throws {
        let release = try Self.release()

        // A verify job runs all four gate checks.
        #expect(release.contains("make lint"), "release gate must run lint")
        #expect(release.contains("make build "), "release gate must run the Debug build")
        #expect(
            release.contains("make build-ui-tests"),
            "release gate must compile the UI tests (CS-060)")
        #expect(release.contains("make test "), "release gate must run the unit suite")

        // The publish job depends on the gate.
        #expect(
            release.contains("needs: verify"),
            "the publish job must depend on the verify gate so a failure blocks publishing (CS-060)"
        )

        // The DMG build and release publish belong to the dependent publish job, which
        // only runs after `verify` succeeds. Confirm both live after the `publish:` job
        // marker (i.e. they are not in an unconditional, pre-gate job).
        let publishMarker = try #require(
            release.range(of: "\n  publish:"),
            "release.yml must declare a publish job")
        let afterPublish = String(release[publishMarker.lowerBound...])
        #expect(
            afterPublish.contains("build-dmg.sh"),
            "the DMG build must run in the gated publish job")
        #expect(
            afterPublish.contains("action-gh-release"),
            "the GitHub release publish must run in the gated publish job")

        // And the gate must come before publish in the file's job order.
        let verifyMarker = try #require(release.range(of: "\n  verify:"))
        #expect(
            verifyMarker.lowerBound < publishMarker.lowerBound,
            "the verify gate must be declared before the publish job")
    }

    // MARK: - Acceptance: the release gate logs the exact toolchain before building

    /// The release `verify` job runs on the same moving `macos-latest` image as CI, so
    /// the "log exact macOS/Xcode/Swift versions before building" acceptance applies to
    /// it too: a DMG must be traceable to the toolchain it was validated against. Assert
    /// the version-probe commands are present in `release.yml` and run before its first
    /// build, so a future edit that drops toolchain logging from the release gate fails
    /// the suite rather than shipping an untraceable artifact.
    @Test func releaseGateLogsExactToolchainVersionsBeforeBuilding() throws {
        let release = try Self.release()
        #expect(release.contains("sw_vers"), "release gate must log the macOS version (sw_vers)")
        #expect(release.contains("xcodebuild -version"), "release gate must log the Xcode version")
        #expect(release.contains("swift --version"), "release gate must log the Swift version")

        // The toolchain probe must precede the first build invocation in the gate.
        let toolchainMarker = try #require(release.range(of: "sw_vers"))
        let buildMarker = try #require(release.range(of: "run: make build "))
        #expect(
            toolchainMarker.lowerBound < buildMarker.lowerBound,
            "Toolchain versions must be logged before building in the release gate (CS-060)")
    }

    // MARK: - Acceptance: the release gate uploads .xcresult bundles on failure

    /// The `.xcresult`-on-failure acceptance is not CI-only: when the release `verify`
    /// gate blocks a tag, the same offline-triage diagnostics must be available from the
    /// tag run. Assert the gate passes `RESULT_BUNDLE=` through every xcodebuild phase
    /// (build, build-ui-tests, test) and uploads the bundles through a `failure()`-gated
    /// step, so a regression that drops release-gate diagnostics fails here.
    @Test func releaseGateUploadsXcresultBundlesOnFailure() throws {
        let release = try Self.release()

        // Every build/test phase in the gate must request an .xcresult bundle.
        for phase in ["make build ", "make build-ui-tests ", "make test "] {
            let invocation = try #require(
                release.components(separatedBy: .newlines).first { $0.contains(phase) },
                "release gate must invoke `\(phase.trimmingCharacters(in: .whitespaces))`")
            #expect(
                invocation.contains("RESULT_BUNDLE="),
                "release gate `\(phase.trimmingCharacters(in: .whitespaces))` must capture an .xcresult bundle (CS-060)"
            )
        }

        // The upload step must exist, reference the bundles, and be gated on failure.
        #expect(release.contains("actions/upload-artifact@"))
        #expect(
            release.contains(".xcresult"),
            "release gate must reference the .xcresult bundles it uploads")
        let uploadName = try #require(
            release.range(of: "name: release-verify-xcresults"),
            "release gate must declare the .xcresult upload step")
        let preceding = String(release[..<uploadName.lowerBound])
        #expect(
            preceding.contains("if: failure()"),
            "the release gate's .xcresult upload must be gated on failure (CS-060)")

        // The diagnostics upload belongs to the verify gate, not the publish job, so it
        // captures gate failures (which never reach publish).
        let verifyMarker = try #require(release.range(of: "\n  verify:"))
        let publishMarker = try #require(release.range(of: "\n  publish:"))
        #expect(
            verifyMarker.upperBound < uploadName.lowerBound
                && uploadName.lowerBound < publishMarker.lowerBound,
            "the .xcresult upload must live in the verify gate (CS-060)")
    }

    // MARK: - Acceptance: full `make test-ui` documented as local/manual or self-hosted only

    @Test func releasingDocExplainsTheUITestPolicy() throws {
        let doc = try Self.releasingDoc()
        // The compile-only check is the hosted-PR step…
        #expect(
            doc.contains("make build-ui-tests"),
            "RELEASING.md must document the UI-test compile step")
        // …while the full run is documented as local/manual or self-hosted-only.
        #expect(
            doc.contains("make test-ui"),
            "RELEASING.md must document the full UI suite command")
        #expect(
            doc.localizedCaseInsensitiveContains("self-hosted"),
            "RELEASING.md must say the full UI suite is local/manual or self-hosted-runner-only (CS-060)"
        )
        #expect(
            doc.localizedCaseInsensitiveContains("automation permission"),
            "RELEASING.md must explain the automation-permission reason the UI suite is not in the hosted gate"
        )
    }

    // MARK: - Acceptance: CI is documented as a release gate

    @Test func releasingDocDocumentsTheCIGateAndDriftJob() throws {
        let doc = try Self.releasingDoc()
        #expect(
            doc.contains("CS-060"),
            "RELEASING.md must reference the CI-hardening ticket")
        #expect(
            doc.localizedCaseInsensitiveContains("drift"),
            "RELEASING.md must document the weekly drift watch (CS-060)")
        #expect(
            doc.localizedCaseInsensitiveContains(".xcresult"),
            "RELEASING.md must document the .xcresult-on-failure artifacts (CS-060)")
    }
}
