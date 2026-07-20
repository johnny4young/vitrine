import Foundation
import Testing

/// Release artifact QA checklist.
///
/// These tests assert that the committed QA tooling — `scripts/qa-release.sh` and
/// the `docs/RELEASING.md` section that documents it — actually encodes every
/// release requirement, so a future edit that drops a checklist
/// item, the environment record, the self-contained property, or the
/// app-bug-vs-signing-failure distinction fails the unit suite rather than
/// silently shipping a QA process that misses a release blocker.
///
/// Like `ReleaseSigningTests`, `HomebrewCaskTests`, and
/// `WorkflowConfigurationTests`, they read the committed files from the
/// source tree (anchored to this file via `#filePath`) rather than any built
/// bundle, because the QA script is run by a human against a *published* artifact
/// on a clean Mac — something no hosted unit test can reproduce (it has no
/// Developer ID-signed DMG, no second machine). This suite is the structural guard
/// that the checklist and its automated checks stay complete and internally
/// consistent.
@Suite("Release artifact QA checklist")
struct ReleaseQAChecklistTests {

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

    private static func script() throws -> String {
        try text("scripts", "qa-release.sh")
    }

    private static func releasingDoc() throws -> String {
        try text("docs", "RELEASING.md")
    }

    /// The interactive checklist items the checklist enumerates. Both the script
    /// (which prints the checklist) and `RELEASING.md` (which documents it) must
    /// cover every one of them. Each entry is a list of acceptable substrings —
    /// any one matching counts — so wording can evolve without making the guard
    /// brittle, while still failing if an item disappears entirely.
    private static let checklistItems: [(label: String, needles: [String])] = [
        ("DMG open", ["DMG open", "DMG opens", ".dmg"]),
        ("drag-to-Applications", ["Applications"]),
        ("first launch", ["First launch", "first launch"]),
        ("Gatekeeper", ["Gatekeeper"]),
        ("menu-bar icon", ["Menu-bar icon", "menu-bar icon", "menu bar"]),
        ("no Dock icon", ["No Dock icon", "no Dock icon", "LSUIElement"]),
        ("quick capture", ["Quick capture", "Quick Capture", "quick capture"]),
        ("editor export", ["Editor export", "editor export", "export a PNG", "exports a PNG"]),
        ("settings", ["Settings"]),
        ("launch-at-login", ["Launch at login", "launch at login", "login item"]),
        ("uninstall", ["Uninstall", "uninstall"]),
    ]

    // MARK: - Files exist

    @Test func theQAToolingFilesExist() {
        let fileManager = FileManager.default
        for path in [
            Self.url("scripts", "qa-release.sh"),
            Self.url("docs", "RELEASING.md"),
        ] {
            #expect(
                fileManager.fileExists(atPath: path.path),
                " expects \(path.lastPathComponent) to exist")
        }
    }

    /// The QA script must be executable so it can be invoked directly
    /// (`./qa-release.sh …`) on the clean Mac without a shell prefix.
    @Test func theQAScriptIsExecutable() throws {
        let path = Self.url("scripts", "qa-release.sh").path
        #expect(
            FileManager.default.isExecutableFile(atPath: path),
            "scripts/qa-release.sh must be executable")
    }

    /// Basic shell hygiene matching the repo's other release scripts: a bash
    /// shebang and strict mode, so a failed command aborts the run rather than
    /// silently reporting a false pass.
    @Test func theQAScriptUsesStrictBash() throws {
        let script = try Self.script()
        #expect(
            script.hasPrefix("#!/usr/bin/env bash") || script.hasPrefix("#!/bin/bash"),
            "qa-release.sh must start with a bash shebang")
        #expect(
            script.contains("set -euo pipefail"),
            "qa-release.sh must use strict bash mode (set -euo pipefail)")
    }

    // MARK: - Contract: the checklist covers every required item

    /// The printed checklist in the script must cover all eleven interactive items.
    @Test func scriptChecklistCoversEveryRequiredItem() throws {
        let script = try Self.script()
        for item in Self.checklistItems {
            #expect(
                item.needles.contains(where: script.contains),
                "qa-release.sh checklist must cover \(item.label)")
        }
    }

    /// The documented checklist in `RELEASING.md` must cover the same items, so the
    /// process is captured even before someone runs the script.
    @Test func releasingDocChecklistCoversEveryRequiredItem() throws {
        let doc = try Self.releasingDoc()
        for item in Self.checklistItems {
            #expect(
                item.needles.contains(where: doc.contains),
                "RELEASING.md QA section must cover \(item.label)")
        }
    }

    // MARK: - Contract: runs on a clean Mac without the repo or DerivedData

    /// The script must be self-contained — it cannot depend on the repository
    /// build tooling, because it runs on a machine that has neither the checkout
    /// nor any DerivedData. Guard against the obvious leaks: it must not *invoke*
    /// the build toolchain (regenerate or build the project). The strings are
    /// matched as commands so the header comment, which may legitimately mention
    /// that the script avoids `project.yml` / DerivedData, does not trip the guard.
    @Test func scriptIsSelfContainedAndDoesNotDependOnTheRepo() throws {
        let script = try Self.script()
        // Strip comment lines so we only inspect executable shell; the header
        // explains the self-contained design in prose and must not be penalized.
        let executableLines =
            script
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
        for command in ["xcodebuild", "xcodegen", "make build", "make project"] {
            #expect(
                !executableLines.contains(command),
                "qa-release.sh must not invoke `\(command)`; it runs on a clean Mac")
        }
        // It must rely only on stock macOS tools that are present without the repo.
        for tool in ["codesign", "spctl", "plutil", "sw_vers", "hdiutil"] {
            #expect(
                script.contains(tool),
                "qa-release.sh should use the stock macOS tool `\(tool)`")
        }
    }

    /// The documentation must state the clean-Mac requirement explicitly so the QA
    /// is run where it is meaningful (not on the build machine).
    @Test func releasingDocRequiresACleanMac() throws {
        let doc = try Self.releasingDoc()
        #expect(
            doc.localizedCaseInsensitiveContains("clean")
                && doc.localizedCaseInsensitiveContains("Mac"),
            "RELEASING.md must require running QA on a clean Mac")
        #expect(
            doc.contains("DerivedData"),
            "RELEASING.md must note the clean Mac has no DerivedData")
        #expect(
            doc.contains("scripts/qa-release.sh"),
            "RELEASING.md must point at scripts/qa-release.sh")
    }

    // MARK: - Contract: records macOS version, architecture, app version, signing identity

    /// Every QA run must record where it ran and what it tested. The script reads
    /// each fact with a stock tool: the macOS version (`sw_vers`), the architecture
    /// (`uname -m`), the app version (`CFBundleShortVersionString` via `plutil`),
    /// and the signing identity (the `codesign` authority).
    @Test func scriptRecordsTheQAEnvironment() throws {
        let script = try Self.script()
        #expect(
            script.contains("sw_vers"),
            "qa-release.sh must record the macOS version (sw_vers)")
        #expect(
            script.contains("uname -m"),
            "qa-release.sh must record the hardware architecture (uname -m)")
        #expect(
            script.contains("CFBundleShortVersionString"),
            "qa-release.sh must record the app version (CFBundleShortVersionString)")
        // The signing identity comes from the codesign authority line.
        #expect(
            script.contains("codesign") && script.localizedCaseInsensitiveContains("Authority"),
            "qa-release.sh must record the signing identity (codesign Authority)")
    }

    /// The documentation must list the same recorded fields, so the QA log captures
    /// them every release.
    @Test func releasingDocListsTheRecordedFields() throws {
        let doc = try Self.releasingDoc()
        #expect(
            doc.localizedCaseInsensitiveContains("macOS version"),
            "RELEASING.md must say QA records the macOS version")
        #expect(
            doc.localizedCaseInsensitiveContains("architecture"),
            "RELEASING.md must say QA records the architecture")
        #expect(
            doc.localizedCaseInsensitiveContains("app version")
                || doc.contains("CFBundleShortVersionString"),
            "RELEASING.md must say QA records the app version")
        #expect(
            doc.localizedCaseInsensitiveContains("signing identity"),
            "RELEASING.md must say QA records the signing identity")
    }

    // MARK: - Contract: scriptable codesign / spctl / plutil / stapler checks

    /// The automated half must run exactly the assessment a user's Gatekeeper runs,
    /// plus an Info.plist sanity check covering
    /// codesign/spctl/plutil".
    @Test func scriptRunsTheGatekeeperAndPlistChecks() throws {
        let script = try Self.script()
        #expect(
            script.contains("codesign --verify"),
            "qa-release.sh must verify the code signature (codesign --verify)")
        #expect(
            script.contains("spctl -a"),
            "qa-release.sh must run a Gatekeeper assessment (spctl -a)")
        #expect(
            script.contains("plutil"),
            "qa-release.sh must validate the Info.plist with plutil")
        #expect(
            script.contains("stapler validate"),
            "qa-release.sh must check the notarization staple (stapler validate)")
    }

    /// The checks must cover the DMG container the user actually downloads, not only
    /// the app inside it.
    @Test func scriptAssessesTheDMGContainerToo() throws {
        let script = try Self.script()
        #expect(
            script.contains("hdiutil attach"),
            "qa-release.sh must mount the DMG to inspect it")
        // Both the app and the DMG variables are assessed (the `$DMG` checks live in
        // the signing section).
        #expect(
            script.contains("\"$DMG\""),
            "qa-release.sh must assess the DMG container, not just the app")
    }

    // MARK: - Contract: failures distinguish app bugs from signing/notarization failures

    /// A failed check must say which CLASS of failure it is, because an app bug and
    /// a signing/notarization failure have different owners and fixes. The script
    /// encodes this two ways that must both hold: distinct labels in the output, and
    /// distinct exit codes a wrapper can branch on without parsing text.
    @Test func scriptDistinguishesAppBugsFromSigningFailures() throws {
        let script = try Self.script()
        // Distinct, machine-checkable failure classes in the output.
        #expect(
            script.contains("[APP]"),
            "qa-release.sh must label app/packaging failures distinctly")
        #expect(
            script.contains("[SIGNING]"),
            "qa-release.sh must label signing/notarization failures distinctly")
        // Separate accounting for the two classes.
        #expect(
            script.contains("APP_FAILURES") && script.contains("SIGNING_FAILURES"),
            "qa-release.sh must track app vs. signing failures separately")
        // Distinct exit codes: an app/packaging failure and a signing failure must
        // not collapse to the same status.
        #expect(
            script.contains("exit 3"),
            "qa-release.sh must exit with a distinct code for an app/packaging failure")
        #expect(
            script.contains("exit 2"),
            "qa-release.sh must exit with a distinct code for a signing/notarization failure"
        )
        // The unsigned dev artifact must fail release QA, never produce a green run.
        #expect(
            script.localizedCaseInsensitiveContains("not production-ready"),
            "qa-release.sh must flag an unsigned artifact as not production-ready")
        #expect(
            script.contains(#"fail_signing "App is UNSIGNED or ad-hoc"#),
            "qa-release.sh must classify an unsigned artifact as a signing failure")
    }

    /// Under strict pipefail mode, piping a verbose producer into `grep -q` can
    /// report failure when grep exits after its first match and the producer receives
    /// SIGPIPE. Signature and Gatekeeper classification must inspect captured output
    /// instead, or a valid published artifact can be reported as unsigned.
    @Test func scriptDoesNotShortCircuitSecurityToolOutputThroughGrep() throws {
        let script = try Self.script()
        for producer in ["codesign --display", "spctl -a"] {
            let unsafeLines = script.components(separatedBy: .newlines).filter {
                $0.contains(producer) && $0.contains("| grep -q")
            }
            #expect(
                unsafeLines.isEmpty,
                "qa-release.sh must capture \(producer) output before matching it under pipefail")
        }
        #expect(
            script.contains("CODESIGN_DETAILS=") && script.contains("SPCTL_APP="),
            "qa-release.sh must capture security-tool output before classifying it")
    }

    /// The documentation must explain the same app-bug-vs-signing distinction so a
    /// failing run is triaged to the right owner.
    @Test func releasingDocExplainsTheFailureClassification() throws {
        let doc = try Self.releasingDoc()
        #expect(
            doc.localizedCaseInsensitiveContains("app bug")
                || doc.localizedCaseInsensitiveContains("app / packaging")
                || doc.localizedCaseInsensitiveContains("app/packaging"),
            "RELEASING.md must describe the app-bug failure class")
        #expect(
            doc.localizedCaseInsensitiveContains("notariz")
                && doc.localizedCaseInsensitiveContains("signing"),
            "RELEASING.md must describe the signing/notarization failure class")
    }

    // MARK: - Internal consistency

    /// Tabs are the indentation in the other release scripts; keep qa-release.sh
    /// consistent so `swift-format`-style review of the surrounding tooling and any
    /// shell linting see one style. (No spaces-indented block bodies.)
    @Test func scriptUsesTabIndentationLikeTheOtherReleaseScripts() throws {
        let script = try Self.script()
        // A here-doc body (the printed checklist) is intentionally space-aligned for
        // readable output; ignore lines inside the `<<` … `CHECKLIST` block when
        // checking indentation style.
        var insideHeredoc = false
        for line in script.components(separatedBy: .newlines) {
            if line.contains("<<'CHECKLIST'") || line.contains("<<\"CHECKLIST\"")
                || line.contains("<<CHECKLIST")
            {
                insideHeredoc = true
                continue
            }
            if insideHeredoc {
                if line == "CHECKLIST" { insideHeredoc = false }
                continue
            }
            // Any leading whitespace must be a tab, not spaces.
            if let first = line.first, first == " " {
                Issue.record(
                    "qa-release.sh must indent with tabs, found space-indented line: \(line)")
            }
        }
    }
}
