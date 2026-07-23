import Foundation
import Testing

/// Homebrew cask release automation.
///
/// These tests assert that the committed cask, the release workflow, and
/// `docs/RELEASING.md` actually encode every release requirement,
/// so a future edit that breaks a cask stanza, drops the DMG SHA-256 storage from
/// the release, or removes the documented tap-PR update process fails the unit
/// suite rather than silently shipping a cask that `brew install --cask` cannot
/// install.
///
/// Like `ReleaseSigningTests` and `WorkflowConfigurationTests`,
/// they read the committed files from the source tree (anchored to this file via
/// `#filePath`) rather than any built bundle, because the cask is packaging
/// metadata that no unit-test bundle carries. The actual `brew audit --cask
/// --strict` / `brew install` checks run against the tap on a real Mac (documented
/// in RELEASING.md); this suite is the structural guard that the cask and its
/// release plumbing stay complete and internally consistent.
@Suite("Homebrew cask release automation")
struct HomebrewCaskTests {

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

    private static func cask() throws -> String {
        try text("packaging", "Casks", "vitrine.rb")
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

    @Test func theCaskAndReleaseToolingFilesExist() {
        let fileManager = FileManager.default
        for path in [
            Self.url("packaging", "Casks", "vitrine.rb"),
            Self.url(".github", "workflows", "release.yml"),
            Self.url("docs", "RELEASING.md"),
        ] {
            #expect(
                fileManager.fileExists(atPath: path.path),
                " expects \(path.lastPathComponent) to exist")
        }
    }

    // MARK: - Contract: token, name, desc, homepage, URL, version, sha256, app stanza

    @Test func caskDeclaresTheVitrineToken() throws {
        let cask = try Self.cask()
        #expect(
            cask.contains("cask \"vitrine\" do"),
            "the cask token must be `vitrine` so `brew install --cask vitrine` resolves")
    }

    @Test func caskNameDescAndHomepageAreCorrect() throws {
        let cask = try Self.cask()
        #expect(
            cask.contains("name \"Vitrine\""),
            "the cask must declare its display name")
        #expect(
            cask.contains("desc \"Menu-bar app that turns code into beautiful images\""),
            "the cask must carry the product description")
        #expect(
            cask.contains("homepage \"https://vitrineframe.app/\""),
            "the cask homepage must point at the project site")
    }

    /// The desc must satisfy Homebrew's `brew audit --cask --strict` text rules: it must
    /// not start with an article, must not end with a period, and stays a concise phrase.
    @Test func caskDescriptionFollowsHomebrewStyleRules() throws {
        let cask = try Self.cask()
        let descLine = try #require(
            cask.components(separatedBy: .newlines).first { $0.contains("desc \"") },
            "the cask must declare a desc")
        let value = try #require(
            descLine.split(separator: "\"").dropFirst().first.map(String.init),
            "the desc must be a quoted string")
        for article in ["A ", "An ", "The "] {
            #expect(
                !value.hasPrefix(article),
                "a cask desc must not begin with an article (Homebrew audit): \(value)")
        }
        #expect(
            !value.hasSuffix("."),
            "a cask desc must not end with a period (Homebrew audit): \(value)")
        #expect(value.count <= 80, "a cask desc must stay concise (\(value.count) chars): \(value)")
    }

    @Test func caskVersionAndURLUseTheReleaseTagPattern() throws {
        let cask = try Self.cask()
        // A concrete semantic version, not a `:latest` placeholder (livecheck tracks it).
        let versionLine = try #require(
            cask.components(separatedBy: .newlines).first { $0.contains("version \"") },
            "the cask must declare a version")
        let version = try #require(
            versionLine.split(separator: "\"").dropFirst().first.map(String.init),
            "the version must be a quoted string")
        #expect(
            version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
            "the cask version must be a concrete semantic version, got: \(version)")

        // The download URL must be the versioned GitHub release-asset pattern, built
        // from the interpolated #{version} so a bump only needs the version changed.
        #expect(
            cask.contains(
                "url \"https://github.com/johnny4young/vitrine/releases/download/v#{version}/Vitrine-#{version}.dmg\""
            ),
            "the cask URL must use the versioned GitHub release-asset pattern")
    }

    @Test func caskTemplateVersionMatchesTheProjectRelease() throws {
        let cask = try Self.cask()
        let project = try Self.projectYAML()
        let versionLine = try #require(
            cask.components(separatedBy: .newlines).first { $0.contains("version \"") },
            "the cask must declare a version")
        let caskVersion = try #require(
            versionLine.split(separator: "\"").dropFirst().first.map(String.init),
            "the cask version must be a quoted string")
        let regex = try NSRegularExpression(
            pattern: #"(?m)^\s*MARKETING_VERSION:\s*"?([0-9][0-9A-Za-z.\-]*)"?\s*$"#)
        let match = try #require(
            regex.firstMatch(
                in: project, range: NSRange(project.startIndex..<project.endIndex, in: project)),
            "project.yml must set MARKETING_VERSION")
        let projectVersion = String(
            project[try #require(Range(match.range(at: 1), in: project))])

        #expect(
            caskVersion == projectVersion,
            "the cask template version must match MARKETING_VERSION before release")
    }

    @Test func caskInstallsTheVitrineApp() throws {
        let cask = try Self.cask()
        #expect(
            cask.contains("app \"Vitrine.app\""),
            "the cask must install Vitrine.app via the `app` stanza")
    }

    /// The release workflow pushes the regenerated cask to the tap right after
    /// publishing, so the tap can never silently fall behind a release
    /// again (it sat at 0.1.0 while 0.3.0 shipped). The step must stay wired to
    /// the deploy-key secret and the template, and must degrade to a warning —
    /// never a failed release — when the secret is absent.
    @Test func releaseWorkflowUpdatesTheTapCask() throws {
        let release = try Self.release()
        #expect(
            release.contains("Update the Homebrew tap cask"),
            "release.yml must push the regenerated cask to the tap after publishing")
        #expect(
            release.contains("TAP_DEPLOY_KEY"),
            "the tap update must authenticate with the TAP_DEPLOY_KEY deploy-key secret")
        #expect(
            release.contains("packaging/Casks/vitrine.rb"),
            "the tap update must regenerate the cask from the repo's source template")
        #expect(
            release.contains("::warning::TAP_DEPLOY_KEY is not configured"),
            "a missing deploy key must warn, not fail the release")
    }

    /// The `vitrine` CLI ships embedded in the app bundle under the
    /// collision-safe name `vitrine-cli` (a `vitrine` sibling of the `Vitrine`
    /// executable would clash on case-insensitive APFS); the cask surfaces it on
    /// PATH under its real name via `target:`. The stanza must track the path the
    /// app target's embed script produces, or installs break on a missing file.
    @Test func caskLinksTheEmbeddedCLIOntoPATH() throws {
        let cask = try Self.cask()
        #expect(
            cask.contains(
                "binary \"#{appdir}/Vitrine.app/Contents/MacOS/vitrine-cli\", target: \"vitrine\""
            ),
            "the cask must symlink the embedded CLI onto PATH as `vitrine`")
        let project = try Self.projectYAML()
        #expect(
            project.contains("$(TARGET_BUILD_DIR)/$(EXECUTABLE_FOLDER_PATH)/vitrine-cli"),
            "project.yml must embed the CLI at the path the cask's binary stanza points to")
        #expect(
            project.contains("SKIP_INSTALL: YES"),
            "the embedded CLI must not become a second top-level archive product")
        #expect(
            project.contains("$(UNINSTALLED_PRODUCTS_DIR)/macosx/vitrine-cli"),
            "the sandboxed archive embed phase must be able to follow the skipped-install symlink")
    }

    /// The cask must carry a real 64-hex-digit `sha256`, not `:no_check`. `:no_check`
    /// disables checksum verification (and `brew audit --cask --strict` flags it for a
    /// non-`:latest` version), so the committed template uses a syntactically valid
    /// placeholder that the release process replaces with the published DMG's checksum.
    @Test func caskSHA256IsAValidPlaceholderNotNoCheck() throws {
        let cask = try Self.cask()
        #expect(
            !cask.contains("sha256 :no_check"),
            "the cask must not use `sha256 :no_check` — strict audit rejects it")
        let sha256Line = try #require(
            cask.components(separatedBy: .newlines).first {
                $0.contains("sha256 \"")
            },
            "the cask must declare a quoted sha256")
        let value = try #require(
            sha256Line.split(separator: "\"").dropFirst().first.map(String.init),
            "the sha256 must be a quoted string")
        #expect(
            value.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
            "the cask sha256 must be 64 lowercase hex digits, got: \(value)")
    }

    // MARK: - Contract: depends_on matches the app's minimum macOS

    /// The cask's `depends_on macos:` floor must match the app's deployment target so
    /// Homebrew refuses to install on a macOS the app cannot run on. The app targets
    /// macOS 14 (Sonoma), and Homebrew's canonical minimum-version form is the bare
    /// `:sonoma` symbol.
    @Test func caskDependsOnMatchesTheDeploymentFloor() throws {
        let cask = try Self.cask()
        #expect(
            cask.contains("depends_on macos: :sonoma"),
            "the cask must require at least macOS Sonoma, matching the deployment target")
        let project = try Self.projectYAML()
        #expect(
            project.contains("macOS: \"14.0\""),
            "project.yml must target macOS 14.0 (Sonoma), the cask's depends_on floor")
    }

    // MARK: - Contract: livecheck is configured (a stable release-URL pattern exists)

    @Test func caskConfiguresLivecheck() throws {
        let cask = try Self.cask()
        #expect(
            cask.contains("livecheck do"),
            "the cask must configure livecheck since a stable release-URL pattern exists")
        // Track the GitHub releases page via the canonical strategy.
        #expect(
            cask.contains("strategy :github_latest"),
            "livecheck must use the GitHub-latest strategy to follow release tags")
        // The livecheck block must reference the cask URL, not a hard-coded one.
        let livecheckMarker = try #require(
            cask.range(of: "livecheck do"),
            "the cask must declare a livecheck block")
        let block = String(cask[livecheckMarker.lowerBound...].prefix(200))
        #expect(
            block.contains("url :url"),
            "livecheck should derive its URL from the cask's :url")
    }

    // MARK: - Contract: release workflow prints AND stores the DMG SHA-256

    @Test func releaseWorkflowComputesPrintsAndStoresTheDMGSHA256() throws {
        let release = try Self.release()

        // A dedicated step computes the checksum.
        let stepMarker = try #require(
            release.range(of: "Compute and store DMG SHA-256"),
            "release.yml must declare a step that computes the DMG SHA-256")
        let step = String(release[stepMarker.lowerBound...])

        // Compute: a SHA-256 of the DMG.
        #expect(
            step.contains("shasum -a 256"),
            "the checksum step must compute a SHA-256 with `shasum -a 256`")

        // Print: the value is written to the job summary so it is visible without a download.
        #expect(
            release.contains("GITHUB_STEP_SUMMARY"),
            "the checksum must be printed to the job summary")
        let summaryWrite = step.range(of: "GITHUB_STEP_SUMMARY")
        #expect(
            summaryWrite != nil,
            "the checksum step itself must write the SHA-256 to the job summary")

        // Store: a `.sha256` sidecar is produced and a paste-ready cask-update file too.
        #expect(
            step.contains(".sha256"),
            "the checksum step must write a `.sha256` sidecar")
        #expect(
            step.contains(#"$(basename "${DMG}")"#),
            "the sidecar must name the DMG by basename so it verifies after download")
        #expect(
            step.contains("vitrine-cask-update.txt"),
            "the checksum step must emit a ready-to-paste cask-update file")
    }

    /// Storing the checksum is only durable if the sidecar (and cask-update helper) are
    /// attached to the published release, so a later cask bump can read them off the
    /// release rather than re-downloading the DMG.
    @Test func releaseUploadsTheChecksumSidecarAsAnAsset() throws {
        let release = try Self.release()
        // The publish step must ship the DMG, its sidecar, and the cask-update helper.
        #expect(
            release.contains("dist/*.dmg.sha256"),
            "release.yml must attach the `.sha256` sidecar to the release")
        #expect(
            release.contains("vitrine-cask-update.txt"),
            "release.yml must attach the cask-update helper to the release")
        // These must live in the gated publish job (the one that uploads the DMG), not in
        // an unconditional pre-gate job.
        let publishMarker = try #require(
            release.range(of: "\n  publish:"),
            "release.yml must declare a publish job")
        let afterPublish = String(release[publishMarker.lowerBound...])
        #expect(
            afterPublish.contains("dist/*.dmg.sha256"),
            "the checksum sidecar upload must run in the gated publish job")

        // The checksum is computed before the release is published (order matters: the
        // sidecar must exist when action-gh-release uploads the files).
        let checksumMarker = try #require(release.range(of: "Compute and store DMG SHA-256"))
        let publishStep = try #require(
            release.range(of: "Publish GitHub release"),
            "release.yml must publish the GitHub release")
        #expect(
            checksumMarker.lowerBound < publishStep.lowerBound,
            "the checksum must be computed before the GitHub release is published")

        let qaMarker = try #require(
            release.range(of: "QA the published DMG"),
            "release.yml must run post-publish artifact QA")
        let qa = String(release[qaMarker.lowerBound...])
        #expect(
            qa.contains("*.dmg.sha256"),
            "post-publish QA must download the checksum sidecar")
        #expect(
            qa.contains("shasum -a 256 -c"),
            "post-publish QA must verify the downloaded DMG against its sidecar")
    }

    // MARK: - Contract: the cask update process is documented through a tap PR

    @Test func releasingDocDocumentsTheCaskAndTapUpdateProcess() throws {
        let doc = try Self.releasingDoc()
        // The two-copy model (repo template vs. tap) and the tap install command.
        #expect(
            doc.contains("packaging/Casks/vitrine.rb"),
            "RELEASING.md must point at the cask template")
        #expect(
            doc.contains("johnny4young/homebrew-tap"),
            "RELEASING.md must name the tap that hosts the released cask")
        #expect(
            doc.contains("brew install --cask johnny4young/tap/vitrine"),
            "RELEASING.md must document the user install command")

        // The update is via a tap PR (the contract: documented or automated through a
        // tap PR).
        #expect(
            doc.localizedCaseInsensitiveContains("tap PR"),
            "RELEASING.md must document updating the cask through a tap PR")

        // The audit + install/uninstall smoke checks must be documented.
        #expect(
            doc.contains("brew audit --cask --strict"),
            "RELEASING.md must document `brew audit --cask --strict`")
        #expect(
            doc.contains("brew uninstall --cask"),
            "RELEASING.md must document the uninstall smoke check")
        #expect(
            doc.localizedCaseInsensitiveContains("livecheck"),
            "RELEASING.md must document the livecheck configuration")
    }

    /// The doc must explain that the stored checksum (the `vitrine-cask-update.txt`
    /// helper / job-summary value) feeds the tap bump, closing the loop between the
    /// release workflow's storage and the cask update.
    @Test func releasingDocConnectsTheStoredChecksumToTheTapBump() throws {
        let doc = try Self.releasingDoc()
        #expect(
            doc.contains("vitrine-cask-update.txt"),
            "RELEASING.md must reference the release's cask-update helper")
        #expect(
            doc.localizedCaseInsensitiveContains("sha256")
                || doc.localizedCaseInsensitiveContains("sha-256")
                || doc.localizedCaseInsensitiveContains("checksum"),
            "RELEASING.md must connect the stored checksum to the cask `sha256` bump")
    }
}
