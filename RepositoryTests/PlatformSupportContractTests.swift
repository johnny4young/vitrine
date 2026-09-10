import Foundation
import Testing

@Suite("Platform support contract")
struct PlatformSupportContractTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func everyGeneratedTargetAndHomebrewUseTheSequoiaFloor() throws {
        let project = try Self.text("project.yml")
        #expect(project.contains("macOS: \"15.0\""))
        // Assert the property the test is named for — every declared target sits on the
        // Sequoia floor — rather than a target count. A count fails the next time a target
        // is added, which is drift in the test rather than in the contract it guards, and
        // it never noticed a target declared on some *other* floor.
        let declaredFloors =
            project
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            // Only per-target inline declarations; the project-wide default is written as a
            // nested `deploymentTarget:` block and is covered by the `macOS: "15.0"` check
            // above.
            .filter { $0.hasPrefix("deploymentTarget: \"") }
        #expect(!declaredFloors.isEmpty, "project.yml declares no deployment target at all")
        let offenders = Set(declaredFloors.filter { $0 != "deploymentTarget: \"15.0\"" })
        #expect(
            offenders.isEmpty,
            """
            Every generated target must declare the Sequoia floor. Found: \
            \(offenders.sorted().joined(separator: ", "))
            """)

        let cask = try Self.text("packaging/Casks/vitrine.rb")
        #expect(cask.contains("depends_on macos: :sequoia"))
        #expect(!cask.contains("depends_on macos: :sonoma"))
    }

    @Test func publicDocumentationAndWebsiteAgreeOnTheSequoiaFloor() throws {
        let readme = try Self.text("README.md")
        #expect(readme.contains("platform-macOS%2015%2B"))
        #expect(!readme.contains("platform-macOS%2014%2B"))

        let expected: [(String, String)] = [
            ("README.md", "macOS **15.0+** (Sequoia or later)"),
            ("CONTRIBUTING.md", "macOS 15+"),
            ("docs/PROJECT.md", "deployment floor is macOS 15 Sequoia"),
            ("docs/ARCHITECTURE.md", "public binary floor is macOS 15 Sequoia"),
            ("docs/APP-STORE.md", "15.0 (Sequoia)"),
            ("docs/RELEASING.md", "macOS 15.0 Sequoia"),
            ("site/src/components/Hero.astro", "macOS 15+"),
            ("site/public/scripts/site.js", "macOS 15+"),
            (
                "site/src/layouts/BaseLayout.astro",
                "operatingSystem: 'macOS 15 Sequoia or later'"
            ),
        ]

        for (path, phrase) in expected {
            #expect(try Self.text(path).contains(phrase), "\(path) must contain \(phrase)")
        }
    }

    private static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}

/// Keeps the version consolidation from eroding.
///
/// Before this contract, seven places parsed `MARKETING_VERSION` out of `project.yml`
/// in two dialects: a permissive one that accepted `1.3.0-beta.1`, and a strict one
/// that matched nothing on that same input. The release workflow read the permissive
/// dialect while the site build read the strict one, so a prerelease version would have
/// let one proceed and hard-failed the other.
@Suite("Version parser consolidation")
struct VersionParserConsolidationTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The only file allowed to spell out its own extraction. Astro reads `project.yml`
    /// at build time inside Vite, where shelling out to the script is not available, so
    /// it carries the same dialect instead — which the test below pins.
    private static let sanctioned = "site/src/lib/project.ts"

    @Test func onlyTheSanctionedFileSpellsOutAVersionExtraction() throws {
        // Built at runtime so this detector does not match its own source.
        let field = "MARKETING_VERSION" + ":"
        let capture = "(" + "["

        let tracked = try Self.trackedTextFiles()
        var offenders: [String] = []
        for relativePath in tracked where relativePath != Self.sanctioned {
            let contents = try String(
                contentsOf: Self.root.appending(path: relativePath), encoding: .utf8)
            for line in contents.split(separator: "\n", omittingEmptySubsequences: false)
            where line.contains(field) && line.contains(capture) {
                offenders.append("\(relativePath): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(
            offenders.isEmpty,
            """
            Read the version through scripts/project-version.sh (shell, CI) or \
            ProjectVersion (Swift tests) instead of a new regex: \
            \(offenders.sorted().joined(separator: " | "))
            """)
    }

    @Test func theSiteCarriesTheSameDialectAsTheScript() throws {
        let site = try String(
            contentsOf: Self.root.appending(path: Self.sanctioned), encoding: .utf8)
        let script = try String(
            contentsOf: Self.root.appending(path: "scripts/project-version.sh"), encoding: .utf8)

        // Both must reject prereleases and leading zeros, which is the dialect the
        // release tag guard enforces.
        #expect(site.contains("(?:0|[1-9]\\d*)\\.(?:0|[1-9]\\d*)\\.(?:0|[1-9]\\d*)"))
        #expect(script.contains("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))
    }

    private static func trackedTextFiles() throws -> [String] {
        let extensions: Set<String> = ["sh", "py", "yml", "yaml", "swift", "ts", "rb"]
        var files: [String] = ["Makefile"]
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return files }
        for case let url as URL in walker {
            let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
            // Untracked scratch: build output, git internals, agent worktrees, a
            // downloaded release candidate, and vendored packages are not this
            // repository's source.
            if path.hasPrefix("build/") || path.hasPrefix(".git/")
                || path.hasPrefix(".claude/") || path.hasPrefix("release-candidate/")
                || path.contains("/node_modules/")
            {
                continue
            }
            if extensions.contains(url.pathExtension) { files.append(path) }
        }
        return files
    }
}
