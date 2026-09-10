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
