import Foundation
import Testing

/// CI hardening and GitHub Actions observability.
///
/// These tests assert that the committed GitHub Actions workflows, the `Makefile`,
/// and `docs/RELEASING.md` retain the repository's release requirements,
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
@Suite("CI workflow configuration")
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

    private static func deploySite() throws -> String {
        try text(".github", "workflows", "deploy-site.yml")
    }

    private static func freshness() throws -> String {
        try text(".github", "workflows", "dependency-freshness.yml")
    }

    private static func xcode27Preview() throws -> String {
        try text(".github", "workflows", "xcode-27-preview.yml")
    }

    private static func codeql() throws -> String {
        try text(".github", "workflows", "codeql.yml")
    }

    private static func sanitizers() throws -> String {
        try text(".github", "workflows", "sanitizers.yml")
    }

    private static func makefile() throws -> String {
        try text("Makefile")
    }

    private static func releasingDoc() throws -> String {
        try text("docs", "RELEASING.md")
    }

    private static func releasePromotionValidator() throws -> String {
        try text("scripts", "verify-release-promotion.py")
    }

    private static func coverageGuard() throws -> String {
        try text("scripts", "check-coverage.py")
    }

    // MARK: - YAML well-formedness guard (tabs)

    /// YAML forbids tab characters for indentation; a stray tab is a syntax error that
    /// the CI Ruby parse would reject. Guard it here too so the failure is local and
    /// fast. (Structural correctness beyond this is covered by the targeted reads below
    /// and by the CI parse step.)
    @Test func workflowYAMLUsesNoTabIndentation() throws {
        for (name, body) in try [
            ("ci.yml", Self.ci()),
            ("release.yml", Self.release()),
            ("appstore.yml", Self.appstore()),
            ("deploy-site.yml", Self.deploySite()),
            ("dependency-freshness.yml", Self.freshness()),
            ("xcode-27-preview.yml", Self.xcode27Preview()),
            ("codeql.yml", Self.codeql()),
            ("sanitizers.yml", Self.sanitizers()),
        ] {
            for (index, line) in body.components(separatedBy: .newlines).enumerated() {
                let indentation = line.prefix { $0 == " " || $0 == "\t" }
                #expect(
                    !indentation.contains("\t"),
                    "\(name) line \(index + 1) uses a tab for indentation, which is invalid YAML")
            }
        }
    }

    // MARK: - Contract: log exact macOS / Xcode versions before building

    /// The CI workflow must record the exact toolchain (macOS image, Xcode, Swift)
    /// before it builds. The explicit OS labels still receive rolling image/toolchain
    /// updates, so each result must remain traceable to the versions it exercised.
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
            "Toolchain versions must be logged before building")
    }

    // MARK: - Contract: certify Sequoia and Tahoe explicitly

    @Test func ciCertifiesSequoiaAndTahoeAcrossBuildAndUIJobs() throws {
        let ci = try Self.ci()
        let buildMarker = try #require(ci.range(of: "\n  build:"))
        let uiMarker = try #require(ci.range(of: "\n  ui-test:"))
        let buildJob = String(ci[buildMarker.lowerBound..<uiMarker.lowerBound])
        let uiJob = String(ci[uiMarker.lowerBound...])

        for (name, job) in [("build", buildJob), ("UI", uiJob)] {
            #expect(job.contains("runner: macos-15"), "\(name) matrix must exercise Sequoia")
            #expect(job.contains("runner: macos-26"), "\(name) matrix must exercise Tahoe")
            #expect(
                job.contains("runs-on: ${{ matrix.runner }}"),
                "\(name) job must run on its explicit matrix label")
            #expect(
                job.contains("fail-fast: false"),
                "\(name) matrix must finish both OS rows even when one fails")
        }

        #expect(!ci.contains("runs-on: macos-latest"))
        #expect(buildJob.contains("make test-coverage"))
        #expect(buildJob.contains("COVERAGE_PLATFORM=\"${{ matrix.coverage }}\""))
        #expect(buildJob.contains("fetch-depth: 0"))
        #expect(buildJob.contains("make perf"))
        #expect(buildJob.contains("GoldenImageTests"))
        #expect(uiJob.contains("make test-ui RESULT_BUNDLE="))
        #expect(uiJob.contains("make test-visual"))

        // Matrix jobs can upload concurrently. Every artifact name needs an OS suffix,
        // otherwise upload-artifact rejects the second writer for the same name.
        for artifact in [
            "xcresults", "launch-gallery", "golden-diffs", "ui-test-xcresult",
            "screenshot-tour",
        ] {
            #expect(
                ci.contains("name: \(artifact)-${{ matrix.artifact }}"),
                "\(artifact) must be unique per compatibility row")
        }

        let doc = try Self.releasingDoc()
        for term in ["Sequoia", "Tahoe", "macos-15", "macos-26"] {
            #expect(doc.contains(term), "RELEASING.md must document \(term)")
        }
    }

    // MARK: - Contract: fast local tests and explicit CI coverage

    @Test func unitTestLanesSeparateFastFeedbackFromCoverageCollection() throws {
        let make = try Self.makefile()
        let project = try Self.text("project.yml")
        let testMarker = try #require(make.range(of: "\ntest: project"))
        let coverageMarker = try #require(make.range(of: "\ntest-coverage: project"))
        let uiMarker = try #require(make.range(of: "\n## build-ui-tests:"))
        let fastLane = String(make[testMarker.lowerBound..<coverageMarker.lowerBound])
        let coverageLane = String(make[coverageMarker.lowerBound..<uiMarker.lowerBound])

        #expect(fastLane.contains("-enableCodeCoverage NO"))
        #expect(coverageLane.contains("-enableCodeCoverage YES"))
        #expect(fastLane.contains("$(RESULT_BUNDLE_FLAG)"))
        #expect(coverageLane.contains(#"-resultBundlePath "$(COVERAGE_RESULT_BUNDLE)""#))
        #expect(coverageLane.contains("scripts/check-coverage.py"))
        #expect(coverageLane.contains("--baseline \"$(COVERAGE_BASELINE)\""))
        #expect(coverageLane.contains("$(COVERAGE_BASE_REF_FLAG)"))
        #expect(make.contains(#"if [ "$$major" = 15 ]"#))
        #expect(make.contains(#"elif [ "$$major" = 26 ]"#))
        #expect(project.contains("gatherCoverageData: false"))

        let ci = try Self.ci()
        #expect(ci.contains("make test-coverage"))
        #expect(ci.contains("github.event.pull_request.base.sha"))
        #expect(ci.contains("github.event.before"))
        #expect(ci.contains("COVERAGE_BASE_REF=\"$change_base\""))
        #expect(ci.contains("git rev-parse --verify"))
        #expect(!ci.contains("run: make test RESULT_BUNDLE="))
        #expect(ci.contains("xcrun xccov view --report --only-targets"))
        #expect(!ci.contains("xccov could not read the result bundle"))

        let guardScript = try Self.coverageGuard()
        for requirement in [
            "PRODUCTION_TARGETS",
            "--report",
            "--archive",
            "minimum-diff-coverage",
            "maximum-overall-drop-points",
            "NONVISUAL_WEB_FILES",
        ] {
            #expect(guardScript.contains(requirement))
        }
        for platform in ["sequoia", "tahoe"] {
            let baseline = try Self.text("scripts", "coverage-baselines", "\(platform).json")
            #expect(baseline.contains(#""schemaVersion": 1"#))
            #expect(baseline.contains(#""productionLineCoverage""#))
            #expect(baseline.contains(#""sourceRevision""#))
        }
    }

    @Test func swiftWarningsFailEveryAppOwnedTargetBuild() throws {
        let project = try Self.text("project.yml")
        #expect(project.contains("SWIFT_TREAT_WARNINGS_AS_ERRORS: YES"))
    }

    // MARK: - Contract: cache SPM dependencies where safe

    @Test func ciCachesSwiftPackageManagerDependencies() throws {
        let ci = try Self.ci()
        #expect(ci.contains("actions/cache@"), "CI must cache something (SPM)")
        #expect(
            ci.contains("org.swift.swiftpm"),
            "CI must cache the Swift Package Manager cache directory")
        // Keyed on project.yml — the dependency source of truth (the resolved project
        // is generated, not committed).
        #expect(
            ci.contains("hashFiles('project.yml')"),
            "The SPM cache key must be bound to project.yml")
    }

    @Test func workflowsVerifyPinnedXcodeGenAndWatchExternalPins() throws {
        let version = try Self.text("scripts", "xcodegen-version.env")
        let installer = try Self.text("scripts", "install-xcodegen.sh")
        let verifier = try Self.text("scripts", "verify-xcodegen-version.sh")
        #expect(version.contains("XCODEGEN_VERSION=\""))
        #expect(version.contains("XCODEGEN_ARCHIVE_SHA256=\""))
        #expect(installer.contains("releases/download/${XCODEGEN_VERSION}/xcodegen.zip"))
        #expect(installer.contains("XCODEGEN_ARCHIVE_SHA256"))
        #expect(installer.contains("GITHUB_PATH"))
        #expect(verifier.contains("xcodegen-version.env"))
        #expect(verifier.contains(#"[ "$actual" != "$XCODEGEN_VERSION" ]"#))
        #expect(try Self.makefile().contains(#"verify-xcodegen-version.sh "$(XCODEGEN)""#))
        for workflow in try [Self.ci(), Self.release(), Self.appstore()] {
            #expect(workflow.contains("./scripts/install-xcodegen.sh"))
            #expect(!workflow.contains("brew install xcodegen"))
        }
        let freshness = try Self.freshness()
        #expect(freshness.contains("schedule:"))
        #expect(freshness.contains("./scripts/check-dependency-freshness.sh"))
    }

    @Test func failureDiagnosticsRequireGeneratedProject() throws {
        let ci = try Self.ci()
        #expect(
            ci.contains(
                "if: failure() && hashFiles('Vitrine.xcodeproj/project.pbxproj') != ''"))
    }

    @Test func releasePublishesPinnedSpdxInventory() throws {
        let release = try Self.release()
        #expect(release.contains("anchore/sbom-action@e22c389904149dbc22b58101806040fa8d37a610"))
        #expect(release.contains("syft-version: v1.49.0"))
        #expect(release.contains("dist/*.spdx.json"))
    }

    @Test func releaseStagesPrivateMaterialWithRestrictivePermissions() throws {
        let release = try Self.release()
        #expect(release.components(separatedBy: "umask 077").count - 1 >= 2)
    }

    // MARK: - Contract: upload .xcresult bundles / test logs on failure

    @Test func ciUploadsXcresultBundlesOnFailure() throws {
        let ci = try Self.ci()
        // The build/test steps must request an .xcresult bundle…
        #expect(
            ci.contains("RESULT_BUNDLE="),
            "CI must direct an .xcresult bundle via RESULT_BUNDLE")
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
            "The .xcresult upload must be gated on failure")
    }

    /// The Makefile must honor `RESULT_BUNDLE` on the build/test/UI-test-build targets,
    /// since that is how CI captures the `.xcresult` bundles through the same `make`
    /// entrypoints the gate uses.
    @Test func makefileSupportsResultBundleCapture() throws {
        let make = try Self.makefile()
        #expect(
            make.contains("RESULT_BUNDLE_FLAG"),
            "Makefile must define a RESULT_BUNDLE flag for .xcresult capture")
        #expect(
            make.contains("-resultBundlePath"),
            "Makefile must pass -resultBundlePath to xcodebuild when RESULT_BUNDLE is set")
    }

    // MARK: - Contract: compile optimized universal builds before packaging

    @Test func ciAndReleaseCompileAUniversalOptimizedBuild() throws {
        let make = try Self.makefile()
        let releaseMarker = try #require(make.range(of: "\nbuild-release: project"))
        let cliMarker = try #require(make.range(of: "\n## cli:"))
        let lane = String(make[releaseMarker.lowerBound..<cliMarker.lowerBound])
        for required in [
            "-configuration Release",
            "generic/platform=macOS",
            "ONLY_ACTIVE_ARCH=NO",
            "ARCHS='arm64 x86_64'",
            "$(RESULT_BUNDLE_FLAG)",
        ] {
            #expect(lane.contains(required), "universal Release lane must contain \(required)")
        }

        for (name, workflow) in [("CI", try Self.ci()), ("release", try Self.release())] {
            #expect(
                workflow.contains("make build-release RESULT_BUNDLE="),
                "\(name) must compile the optimized universal app")
            #expect(
                workflow.contains("build-release.xcresult"),
                "\(name) must retain optimized-build diagnostics")
        }
    }

    // MARK: - Contract: run `make build-ui-tests` on every PR

    @Test func ciRunsBuildUITestsOnPullRequests() throws {
        let ci = try Self.ci()
        #expect(
            ci.contains("pull_request"),
            "CI must trigger on pull requests")
        #expect(
            ci.contains("make build-ui-tests"),
            "CI must compile the UI tests on every PR")
    }

    // MARK: - Contract: weekly scheduled drift job

    @Test func ciHasAWeeklyScheduledDriftJob() throws {
        let ci = try Self.ci()
        #expect(ci.contains("schedule:"), "CI must declare a schedule trigger")
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
            "a weekly drift job must constrain the day-of-week field, got: \(quoted)")
    }

    @Test func xcode27PreviewIsWeeklyManualAndNeverARequiredRuntimeClaim() throws {
        let workflow = try Self.xcode27Preview()
        #expect(workflow.contains("runs-on: xcode-27"))
        #expect(workflow.contains("schedule:"))
        #expect(workflow.contains("workflow_dispatch:"))
        #expect(!workflow.contains("\n  pull_request:"))
        #expect(!workflow.contains("\n  push:"))
        for command in ["make lint", "make build", "make test"] {
            #expect(workflow.contains(command))
        }
        #expect(!workflow.contains("make test-ui"))
        #expect(workflow.contains("not macOS 27 runtime certification"))

        let doc = try Self.releasingDoc()
        #expect(doc.contains("**Xcode 27 preview**"))
        #expect(doc.contains("not a claim of macOS 27 runtime support"))
    }

    @Test func codeQLAnalyzesSwiftAndJavaScriptWithExtendedSecurityQueries() throws {
        let workflow = try Self.codeql()
        for requirement in [
            "language: swift",
            "language: javascript-typescript",
            "build-mode: manual",
            "build-mode: none",
            "queries: security-extended",
            "security-events: write",
            "github/codeql-action/init@",
            "github/codeql-action/analyze@",
            "run: make build",
        ] {
            #expect(workflow.contains(requirement), "CodeQL must retain `\(requirement)`")
        }
        #expect(workflow.contains("pull_request:"))
        #expect(workflow.contains("branches: [main]"))
        #expect(workflow.contains("runs-on: ${{ matrix.runner }}"))
        #expect(workflow.contains("runner: macos-15"))
        #expect(workflow.contains("runner: ubuntu-latest"))
    }

    @Test func sanitizersAreFocusedWeeklyManualEarlyWarnings() throws {
        let workflow = try Self.sanitizers()
        let make = try Self.makefile()
        let doc = try Self.releasingDoc()
        let sanitizerStart = try #require(make.range(of: "\n# Sanitizers intentionally"))
        let uiStart = try #require(make.range(of: "\n## build-ui-tests:"))
        let sanitizerLanes = String(make[sanitizerStart.lowerBound..<uiStart.lowerBound])

        #expect(workflow.contains("schedule:"))
        #expect(workflow.contains("workflow_dispatch:"))
        #expect(!workflow.contains("\n  pull_request:"))
        #expect(!workflow.contains("\n  push:"))
        #expect(workflow.contains("make ${{ matrix.target }}"))
        #expect(workflow.contains("target: test-asan"))
        #expect(workflow.contains("target: test-tsan"))
        #expect(workflow.contains("if: always()"))
        #expect(workflow.contains(".xcresult"))

        #expect(make.contains("test-asan: project"))
        #expect(make.contains("-enableAddressSanitizer YES"))
        #expect(make.contains("test-tsan: project"))
        #expect(make.contains("-enableThreadSanitizer YES"))
        #expect(make.contains("ItemProviderLoadWaiterTests"))
        #expect(make.contains("MemoryWebSnapshotCycleJourneyTests"))
        #expect(!sanitizerLanes.contains("-only-testing:VitrineUITests"))

        #expect(doc.contains("CodeQL"))
        #expect(doc.contains("make test-asan"))
        #expect(doc.contains("make test-tsan"))
        #expect(doc.contains("non-required"))
    }

    // MARK: - Contract: release candidate and manual promotion are fail-closed

    /// The release workflow must run lint, build, the unit suite, and the UI-test
    /// build, and only the candidate step may depend on that gate. Tag pushes must stop
    /// after uploading + independently QA-checking a private artifact; public release
    /// creation belongs exclusively to a separately confirmed workflow_dispatch run.
    @Test func releaseRefusesToPublishWhenAnyGateFails() throws {
        let release = try Self.release()

        // A verify job runs every gate check, including both build configurations.
        #expect(release.contains("make lint"), "release gate must run lint")
        #expect(release.contains("make build "), "release gate must run the Debug build")
        #expect(
            release.contains("make build-release "),
            "release gate must run the optimized universal build")
        #expect(
            release.contains("make build-ui-tests"),
            "release gate must compile the UI tests")
        #expect(release.contains("make test "), "release gate must run the unit suite")

        // The private candidate build depends on the gate.
        #expect(
            release.contains("needs: verify"),
            "the candidate job must depend on the verify gate so a failure blocks packaging"
        )

        let candidateMarker = try #require(
            release.range(of: "\n  candidate:"),
            "release.yml must declare a private candidate job")
        let publishMarker = try #require(
            release.range(of: "\n  publish:"),
            "release.yml must declare a manual promotion job")
        let candidate = String(release[candidateMarker.lowerBound..<publishMarker.lowerBound])
        let afterPublish = String(release[publishMarker.lowerBound...])
        #expect(
            candidate.contains("build-dmg.sh")
                && candidate.contains("Upload signed release candidate")
                && !candidate.contains("action-gh-release"),
            "tag pushes must build and upload a private candidate without publishing")
        #expect(
            afterPublish.contains("github.event_name == 'workflow_dispatch'")
                && afterPublish.contains("verify-release-promotion.py")
                && afterPublish.contains("action-gh-release"),
            "public release creation must require validated manual candidate promotion")
        #expect(
            release.contains("candidate-qa:")
                && release.contains("QA uploaded release candidate")
                && release.contains("gh run download \"${GITHUB_RUN_ID}\""),
            "the uploaded candidate must pass QA on a fresh runner before its run succeeds")

        // Gate, candidate, and manual promotion remain visibly ordered.
        let verifyMarker = try #require(release.range(of: "\n  verify:"))
        #expect(
            verifyMarker.lowerBound < candidateMarker.lowerBound
                && candidateMarker.lowerBound < publishMarker.lowerBound,
            "verify must precede the candidate, which must precede manual promotion")
    }

    @Test func releasePromotionPinsCandidateProvenanceAndDigest() throws {
        let release = try Self.release()
        let validator = try Self.releasePromotionValidator()
        let makefile = try Self.makefile()

        for input in ["candidate_run_id", "expected_sha256", "qa_confirmation"] {
            #expect(
                release.contains(input),
                "manual promotion must require the \(input) input")
        }
        #expect(
            release.contains("gh api \"repos/${GITHUB_REPOSITORY}/actions/runs/")
                && release.contains("verify-release-promotion.py")
                && release.contains("gh run download \"${CANDIDATE_RUN_ID}\""),
            "promotion must fetch and download the exact declared candidate run")

        for evidence in [
            #"run.get("event") != "push""#,
            #"run.get("status") != "completed""#,
            #"run.get("conclusion") != "success""#,
            #"run.get("head_sha") != tag_commit"#,
            #"run.get("path") != workflow_path"#,
            #"actual_repository != repository"#,
        ] {
            #expect(
                validator.contains(evidence),
                "the promotion validator must reject mismatched provenance: \(evidence)")
        }
        #expect(
            validator.contains("CLEAN-MAC-QA-PASSED")
                && validator.contains("^[0-9a-f]{64}$")
                && validator.contains("run_self_test"),
            "promotion must require exact QA confirmation, digest syntax, and deterministic tests")
        #expect(
            makefile.contains("release-promotion-check")
                && makefile.contains("verify-release-promotion.py --self-test"),
            "make lint must execute the promotion validator self-test")

        let preflight = try #require(release.range(of: "Run final pre-publication QA suite"))
        let publish = try #require(release.range(of: "Publish immutable GitHub release"))
        let publishedQA = try #require(release.range(of: "QA published release artifact"))
        let distribute = try #require(release.range(of: "\n  distribute:"))
        #expect(
            preflight.lowerBound < publish.lowerBound
                && publish.lowerBound < publishedQA.lowerBound
                && publishedQA.lowerBound < distribute.lowerBound,
            "candidate QA must precede immutable publication, then published QA must precede distribution"
        )
    }

    // MARK: - Contract: a published release refreshes the marketing site

    @Test func releaseRefreshesTheMarketingSiteAfterPublishing() throws {
        let release = try Self.release()
        let deploySite = try Self.deploySite()
        let doc = try Self.releasingDoc()
        let normalizedDoc = doc.replacingOccurrences(of: "\n", with: " ")

        let jobMarker = try #require(
            release.range(of: "\n  deploy-site:"),
            "release.yml must declare a marketing-site deployment job")
        let job = String(release[jobMarker.lowerBound...])
        #expect(
            job.contains("needs: distribute"),
            "the marketing site must refresh only after published QA and distribution")
        #expect(
            job.contains("uses: ./.github/workflows/deploy-site.yml")
                && job.contains("release_ref: ${{ inputs.tag }}"),
            "the release must deploy the exact promoted tag through the validated Cloudflare workflow"
        )
        #expect(
            deploySite.contains("workflow_call:")
                && deploySite.contains("release_ref:")
                && deploySite.contains("required: true"),
            "deploy-site.yml must require an explicit release ref from reusable and manual callers"
        )
        #expect(
            !deploySite.contains("\n  release:")
                && deploySite.contains("ref: ${{ inputs.release_ref || github.sha }}")
                && deploySite.contains("fetch-depth: 0")
                && deploySite.contains("Verify exact website release provenance")
                && deploySite.contains("Pushes to main never deploy")
                && deploySite.contains("git cat-file -t \"${REQUESTED_REF}\"")
                && deploySite.contains("TAG_COMMIT=\"$(git rev-list -n 1")
                && deploySite.contains("HEAD_COMMIT=\"$(git rev-parse HEAD)\"")
                && deploySite.contains("releases/tags/v${VERSION}")
                && deploySite.contains("if: steps.release.outputs.published == 'true'"),
            "main pushes must only validate, while production requires exact annotated-tag and stable-release provenance"
        )
        #expect(
            deploySite.contains("Cloudflare Pages secrets are required")
                && !deploySite.contains("secrets not configured; skipping site deployment"),
            "an eligible production deployment must fail closed when Cloudflare credentials are missing"
        )
        #expect(
            normalizedDoc.contains("GITHUB_TOKEN")
                && normalizedDoc.contains("does not emit another workflow run"),
            "the runbook must preserve why an explicit workflow call is required")
    }

    @Test func releasePublishesCuratedChangelogNotes() throws {
        let release = try Self.release()
        let doc = try Self.releasingDoc()

        #expect(
            release.contains("Prepare curated release notes")
                && release.contains("CHANGELOG.md > \"${NOTES_PATH}\"")
                && release.contains("body_path: dist/release-notes.md"),
            "the immutable GitHub release body must come from the reviewed changelog section"
        )
        #expect(
            !release.contains("generate_release_notes: true"),
            "automatic commit notes must not replace the curated changelog narrative")
        #expect(
            release.contains("[ ! -s \"${NOTES_PATH}\" ]")
                && release.contains("grep -q '^### '"),
            "release-note extraction must fail closed when the version section is empty")
        #expect(
            doc.contains("immutable body is extracted")
                && doc.contains("edited after publication"),
            "the release runbook must explain the curated immutable-note boundary")
    }

    // MARK: - Contract: releases originate from durable version tags

    @Test func releaseRequiresAnnotatedStableSemverTags() throws {
        let release = try Self.release()
        let doc = try Self.releasingDoc()

        #expect(
            release.contains("fetch-depth: 0"),
            "the release checkout must fetch the tag object, not only its peeled commit")
        #expect(
            release.contains("git cat-file -t"),
            "the release gate must distinguish annotated tags from lightweight tags")
        #expect(
            release.contains("TAG_OBJECT_TYPE") && release.contains("!= \"tag\""),
            "the release gate must reject lightweight tags")
        #expect(
            release.contains("not a stable v-prefixed SemVer tag"),
            "the release gate must reject malformed or prerelease tag names")
        #expect(
            doc.contains("git tag -a"),
            "the release runbook must create annotated tags")
        #expect(
            doc.localizedCaseInsensitiveContains("immutable releases"),
            "the release runbook must explain immutable release history")
    }

    // MARK: - Contract: the release gate logs the exact toolchain before building

    /// The release `verify` job still runs on the moving `macos-latest` image, so the
    /// "log exact macOS/Xcode/Swift versions before building" contract applies to it:
    /// a DMG must be traceable to the toolchain it was validated against. Assert
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
            "Toolchain versions must be logged before building in the release gate")
    }

    // MARK: - Contract: the release gate uploads .xcresult bundles on failure

    /// The `.xcresult`-on-failure contract is not CI-only: when the release `verify`
    /// gate blocks a tag, the same offline-triage diagnostics must be available from the
    /// tag run. Assert the gate passes `RESULT_BUNDLE=` through every xcodebuild phase
    /// (build, build-ui-tests, test) and uploads the bundles through a `failure()`-gated
    /// step, so a regression that drops release-gate diagnostics fails here.
    @Test func releaseGateUploadsXcresultBundlesOnFailure() throws {
        let release = try Self.release()

        // Every build/test phase in the gate must request an .xcresult bundle.
        for phase in [
            "make build ", "make build-release ", "make build-ui-tests ", "make test ",
        ] {
            let invocation = try #require(
                release.components(separatedBy: .newlines).first { $0.contains(phase) },
                "release gate must invoke `\(phase.trimmingCharacters(in: .whitespaces))`")
            #expect(
                invocation.contains("RESULT_BUNDLE="),
                "release gate `\(phase.trimmingCharacters(in: .whitespaces))` must capture an .xcresult bundle"
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
            "the release gate's .xcresult upload must be gated on failure")

        // The diagnostics upload belongs to the verify gate, before candidate packaging.
        let verifyMarker = try #require(release.range(of: "\n  verify:"))
        let candidateMarker = try #require(release.range(of: "\n  candidate:"))
        #expect(
            verifyMarker.upperBound < uploadName.lowerBound
                && uploadName.lowerBound < candidateMarker.lowerBound,
            "the .xcresult upload must live in the verify gate")
    }

    // MARK: - Contract: CI executes the full UI suite

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
            "the UI-test run must capture an .xcresult bundle")
        #expect(
            uiJob.contains("timeout-minutes:"),
            "the UI-test job must bound its runtime — a blocked automation session hangs rather than fails"
        )
        #expect(
            uiJob.contains("if: failure()"),
            "the UI-test job must upload its .xcresult bundle on failure")

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
            "the test-ui target must pass RESULT_BUNDLE_FLAG so CI can capture an .xcresult bundle"
        )
    }

    /// A second macOS XCUITest runner can steal focus and TestManager ownership,
    /// producing failures that look like product regressions. Both executable UI
    /// lanes must fail before deleting prior evidence or launching xcodebuild, and
    /// the parser must remain covered by the normal lint gate.
    @Test func makefilePreflightsUITestIsolation() throws {
        let make = try Self.makefile()
        let script = try Self.text("scripts", "check-ui-test-environment.py")

        let ordinaryStart = try #require(make.range(of: "\ntest-ui: project"))
        let ordinaryEnd = try #require(make.range(of: "\n## ui-test-preflight-check:"))
        let ordinary = String(make[ordinaryStart.lowerBound..<ordinaryEnd.lowerBound])
        let ordinaryPreflight = try #require(
            ordinary.range(of: "python3 scripts/check-ui-test-environment.py"))
        let ordinaryCleanup = try #require(ordinary.range(of: "rm -rf"))
        #expect(ordinaryPreflight.lowerBound < ordinaryCleanup.lowerBound)

        let visualStart = try #require(make.range(of: "\ntest-visual: project"))
        let visualEnd = try #require(make.range(of: "\n## perf:"))
        let visual = String(make[visualStart.lowerBound..<visualEnd.lowerBound])
        let visualPreflight = try #require(
            visual.range(of: "python3 scripts/check-ui-test-environment.py"))
        let visualCleanup = try #require(visual.range(of: "rm -rf"))
        #expect(visualPreflight.lowerBound < visualCleanup.lowerBound)

        #expect(make.contains("ui-test-preflight-check:"))
        #expect(make.contains("scripts/check-ui-test-environment.py --self-test"))
        #expect(script.contains("ps\", \"-ww\", \"-axo\", \"pid=,command="))
        #expect(script.contains("UITests-Runner.app/Contents/MacOS"))
        #expect(script.contains("does not terminate test processes automatically"))
    }

    // MARK: - Contract: the UI-test execution policy is documented

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
            "RELEASING.md must explain the pre-authorized automation mode that lets hosted runners execute the suite"
        )
        #expect(
            doc.localizedCaseInsensitiveContains("automation permission"),
            "RELEASING.md must explain the automation-permission requirement (interactive locally, pre-authorized in CI)"
        )
        #expect(
            doc.localizedCaseInsensitiveContains("active macOS UI-test runner"),
            "RELEASING.md must explain the foreign-runner isolation preflight")
    }

    // MARK: - Contract: CI is documented as a release gate

    @Test func releasingDocDocumentsTheCIGateAndDriftJob() throws {
        let doc = try Self.releasingDoc()
        #expect(
            doc.localizedCaseInsensitiveContains("drift"),
            "RELEASING.md must document the weekly drift watch")
        #expect(
            doc.localizedCaseInsensitiveContains(".xcresult"),
            "RELEASING.md must document the .xcresult-on-failure artifacts")
    }

    // MARK: - Contract: third-party actions are commit-SHA pinned

    /// Every `uses:` in every workflow must reference a full 40-character commit SHA,
    /// never a mutable `@vN`/`@branch` tag — the release workflow holds the Developer ID
    /// `.p12`, the notary `.p8`, the Sparkle EdDSA key, the license-signing key, and the
    /// tap deploy key, so a hijacked tag on a community action is a direct path to those
    /// secrets (the tj-actions incident pattern).
    /// A trailing `# vX.Y.Z` comment must record the human-readable version the SHA
    /// corresponds to, which is also what Dependabot rewrites when it bumps the pin.
    @Test func thirdPartyActionsArePinnedToCommitSHAs() throws {
        let sha40 = try Regex(#"^[0-9a-f]{40}$"#)
        for (name, yaml) in try [
            ("ci.yml", Self.ci()),
            ("release.yml", Self.release()),
            ("appstore.yml", Self.appstore()),
            ("deploy-site.yml", Self.deploySite()),
            ("codeql.yml", Self.codeql()),
            ("sanitizers.yml", Self.sanitizers()),
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
                    "\(name): `uses: \(value)` must pin a 40-char commit SHA, not the mutable ref `\(ref)`"
                )
                // And the line must carry the version the SHA maps to, for auditability
                // and for Dependabot's bump comment.
                #expect(
                    rawLine.contains("# v"),
                    "\(name): `uses: \(value)` must carry a `# vX.Y.Z` version comment")
            }
        }
    }
}
