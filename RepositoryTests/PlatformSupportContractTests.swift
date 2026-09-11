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

    /// Files allowed to spell out a version pattern, each for a stated reason.
    ///
    /// `project.ts` is the one *reader*: Astro reads `project.yml` at build time inside
    /// Vite, where shelling out to the script is not available, so it carries the same
    /// dialect instead — which the test below pins. `bump-version.sh` is a *writer*: its
    /// anchored substitutions are the inverse operation, and they must name the keys to
    /// rewrite them.
    private static let sanctioned: Set<String> = [
        "site/src/lib/project.ts",
        "scripts/bump-version.sh",
    ]

    /// Source roots this repository owns, listed rather than excluded: an allowlist
    /// cannot be defeated by a new scratch directory appearing beside them, which an
    /// exclude list can (agent worktrees under `.claude/` did exactly that).
    private static let sourceRoots = [
        "Vitrine", "VitrineDomain", "VitrineRendering", "VitrineCLI", "VitrineMenuBarHelper",
        "Tests", "DomainTests", "RenderingTests", "RepositoryTests", "UITests",
        "scripts", "site/src", ".github", "docs", "packaging",
    ]

    /// Flags a version key followed closely by a regex capture group.
    ///
    /// Deliberately matches the *shape* of an extraction rather than a fixed dialect.
    /// The first version of this test looked for the literal `([`, which is the shape of
    /// the parsers this change deleted — and would therefore have missed a copy of the
    /// dialect it standardised on, `((?:0|[1-9]…`. Swift string interpolation, `\(`, is
    /// not a capture group and is excluded.
    ///
    /// Limits worth knowing: this catches a spelled-out extraction, which is how every
    /// parser here was written and how a copy-paste would arrive. It does not catch one
    /// assembled from pieces at runtime. `releaseAndSiteReadTheVersionThroughOneScript`
    /// covers the other direction, that the real call sites still go through the script.
    private static func extractionOffenders(in line: Substring) -> Bool {
        let keys = ["MARKETING_VERSION" + ":", "CURRENT_PROJECT_VERSION" + ":"]
        let text = String(line)
        for key in keys {
            guard let keyRange = text.range(of: key) else { continue }
            let window = text[keyRange.upperBound...].prefix(40)
            var previous: Character = " "
            for character in window {
                if character == "(" && previous != "\\" { return true }
                previous = character
            }
        }
        return false
    }

    @Test func noFileSpellsOutItsOwnVersionExtraction() throws {
        var offenders: [String] = []
        for relativePath in try Self.sourceFiles()
        where !Self.sanctioned.contains(relativePath) {
            let contents = try String(
                contentsOf: Self.root.appending(path: relativePath), encoding: .utf8)
            for line in contents.split(separator: "\n", omittingEmptySubsequences: false)
            where Self.extractionOffenders(in: line) {
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
            contentsOf: Self.root.appending(path: "site/src/lib/project.ts"), encoding: .utf8)
        let script = try String(
            contentsOf: Self.root.appending(path: "scripts/project-version.sh"), encoding: .utf8)

        // Both must reject prereleases and leading zeros, which is the dialect the
        // release tag guard enforces.
        #expect(site.contains("(?:0|[1-9]\\d*)\\.(?:0|[1-9]\\d*)\\.(?:0|[1-9]\\d*)"))
        #expect(script.contains("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))
    }

    private static func sourceFiles() throws -> [String] {
        let extensions: Set<String> = ["sh", "py", "yml", "yaml", "swift", "ts", "rb", "md"]
        var files: [String] = ["Makefile"]
        for sourceRoot in sourceRoots {
            guard
                let walker = FileManager.default.enumerator(
                    at: root.appending(path: sourceRoot), includingPropertiesForKeys: nil)
            else { continue }
            for case let url as URL in walker where extensions.contains(url.pathExtension) {
                files.append(url.path.replacingOccurrences(of: root.path + "/", with: ""))
            }
        }
        return files
    }
}
