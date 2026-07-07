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

    private static func appstore() throws -> String {
        try text(".github", "workflows", "appstore.yml")
    }

    private static func makefile() throws -> String {
        try text("Makefile")
    }

    private static func releasingDoc() throws -> String {
        try text("docs", "RELEASING.md")
    }

    private static func verificationWorkflow() throws -> String {
        try text("tools", "verify-cs.workflow.js")
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

    /// The CS verification workflow is only useful when its "likely files" hints point
    /// at current source locations. This catches stale paths after large mechanical
    /// splits (for example, the removed SettingsPanes.swift file) before a reviewer
    /// agent wastes time on dead evidence.
    @Test func csVerificationWorkflowReferencesCurrentFiles() throws {
        let workflow = try Self.verificationWorkflow()
        #expect(
            !workflow.contains("SettingsPanes.swift"),
            "verify-cs.workflow.js must not point reviewers at the removed SettingsPanes.swift")

        let fileManager = FileManager.default
        let hints = workflow.components(separatedBy: .newlines)
            .compactMap(Self.fileHintList)
            .flatMap(Self.concreteFileHints)

        #expect(!hints.isEmpty, "Expected CS workflow to contain likely-file hints")
        for hint in hints {
            let url = hint.split(separator: "/").reduce(Self.repositoryRoot) {
                $0.appendingPathComponent(String($1))
            }
            #expect(
                fileManager.fileExists(atPath: url.path),
                "verify-cs.workflow.js references a missing file hint: \(hint)")
        }
    }

    private static func fileHintList(from line: String) -> String? {
        guard let marker = line.range(of: #"files: ""#) else { return nil }
        let rest = line[marker.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private static func concreteFileHints(from list: String) -> [String] {
        list.split(separator: ",")
            .map { raw in
                var hint = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if let annotation = hint.range(of: " (") {
                    hint = String(hint[..<annotation.lowerBound])
                }
                return hint
            }
            .filter { hint in
                hint.hasSuffix(".swift") || hint.hasSuffix(".yml") || hint.hasSuffix(".md")
                    || hint.hasSuffix(".rb") || hint.hasSuffix(".sh")
                    || hint == "Makefile" || hint == "project.yml"
                    || hint.hasSuffix(".xcprivacy")
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

    // MARK: - Acceptance: CI executes the full UI suite

    /// Compile-only `build-ui-tests` let UI-test failures accumulate silently on
    /// `main`; CI must actually execute the XCUITest suite. Assert `ci.yml` declares
    /// a dedicated job that probes the image's pre-authorized automation mode before
    /// running, executes `make test-ui` with `.xcresult` capture, bounds the job with
    /// a timeout (a blocked automation session hangs rather than fails), and uploads
    /// the bundle on failure.
    @Test func ciExecutesTheFullUITestSuite() throws {
        let ci = try Self.ci()

        let uiJobMarker = try #require(
            ci.range(of: "\n  ui-test:"),
            "ci.yml must declare the dedicated UI-test job")
        let uiJob = String(ci[uiJobMarker.lowerBound...])

        #expect(
            uiJob.contains("automationmodetool"),
            "the UI-test job must probe the image's automation authorization before the suite"
        )
        let invocation = try #require(
            uiJob.components(separatedBy: .newlines).first {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("make test-ui")
            },
            "the UI-test job must run `make test-ui`")
        #expect(
            invocation.contains("RESULT_BUNDLE="),
            "the UI-test run must capture an .xcresult bundle (CS-060)")
        #expect(
            uiJob.contains("timeout-minutes:"),
            "the UI-test job must bound its runtime — a blocked automation session hangs rather than fails"
        )
        #expect(
            uiJob.contains("if: failure()"),
            "the UI-test job must upload its .xcresult bundle on failure (CS-060)")

        // Skips must never be silent: if the job excludes tests (the
        // display-geometry-sensitive set), every run must annotate them, mirroring
        // the GOLDEN SKIP discipline of the golden-image suite.
        if uiJob.contains("TEST_UI_SKIP") {
            #expect(
                uiJob.contains("::warning"),
                "CI-skipped UI tests must be surfaced as warning annotations on every run")
        }
    }

    /// The `test-ui` Makefile target must honor `RESULT_BUNDLE` like the other
    /// xcodebuild targets, since that is how the CI UI-test job captures its bundle.
    @Test func makefileSupportsResultBundleCaptureForUITests() throws {
        let make = try Self.makefile()
        let target = try #require(
            make.range(of: "test-ui: project"),
            "Makefile must define the test-ui target")
        let body = String(make[target.lowerBound...])
        #expect(
            body.contains("$(RESULT_BUNDLE_FLAG)"),
            "the test-ui target must pass RESULT_BUNDLE_FLAG so CI can capture an .xcresult bundle (CS-060)"
        )
    }

    // MARK: - Acceptance: the UI-test execution policy is documented

    @Test func releasingDocExplainsTheUITestPolicy() throws {
        let doc = try Self.releasingDoc()
        // The compile-only check still runs in the build job and the release gate…
        #expect(
            doc.contains("make build-ui-tests"),
            "RELEASING.md must document the UI-test compile step")
        // …and the full suite executes in CI on the hosted runners.
        #expect(
            doc.contains("make test-ui"),
            "RELEASING.md must document the full UI suite command")
        #expect(
            doc.contains("automationmodetool"),
            "RELEASING.md must explain the pre-authorized automation mode that lets hosted runners execute the suite (CS-060)"
        )
        #expect(
            doc.localizedCaseInsensitiveContains("automation permission"),
            "RELEASING.md must explain the automation-permission requirement (interactive locally, pre-authorized in CI)"
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

    // MARK: - Acceptance: third-party actions are commit-SHA pinned (S2)

    /// Every `uses:` in every workflow must reference a full 40-character commit SHA,
    /// never a mutable `@vN`/`@branch` tag — the release workflow holds the Developer ID
    /// `.p12`, the notary `.p8`, the Sparkle EdDSA key, the license-signing key, and the
    /// tap deploy key, so a hijacked tag on a community action is a direct path to those
    /// secrets (the tj-actions incident pattern; see docs/DEEP-REVIEW-2026-07.md, S2).
    /// A trailing `# vX.Y.Z` comment must record the human-readable version the SHA
    /// corresponds to, which is also what Dependabot rewrites when it bumps the pin.
    @Test func thirdPartyActionsArePinnedToCommitSHAs() throws {
        let sha40 = try Regex(#"^[0-9a-f]{40}$"#)
        for (name, yaml) in try [
            ("ci.yml", Self.ci()),
            ("release.yml", Self.release()),
            ("appstore.yml", Self.appstore()),
        ] {
            for rawLine in yaml.components(separatedBy: .newlines) {
                guard let usesRange = rawLine.range(of: "uses:") else { continue }
                // The reference value: everything after `uses:` up to an inline comment.
                let afterUses = rawLine[usesRange.upperBound...]
                let value = afterUses.split(separator: "#", maxSplits: 1)[0]
                    .trimmingCharacters(in: .whitespaces)
                // Local (`./…`) and container (`docker://…`) actions are not tag-pinnable.
                guard !value.hasPrefix("./"), !value.hasPrefix("docker://") else { continue }
                guard let atIndex = value.lastIndex(of: "@") else {
                    Issue.record("\(name): `uses: \(value)` has no `@<sha>` pin")
                    continue
                }
                let ref = String(value[value.index(after: atIndex)...])
                #expect(
                    ref.wholeMatch(of: sha40) != nil,
                    "\(name): `uses: \(value)` must pin a 40-char commit SHA, not the mutable ref `\(ref)` (S2)"
                )
                // And the line must carry the version the SHA maps to, for auditability
                // and for Dependabot's bump comment.
                #expect(
                    rawLine.contains("# v"),
                    "\(name): `uses: \(value)` must carry a `# vX.Y.Z` version comment (S2)")
            }
        }
    }
}
