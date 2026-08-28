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
        #expect(
            project.components(separatedBy: "deploymentTarget: \"15.0\"").count - 1 == 5)
        #expect(!project.contains("deploymentTarget: \"14.0\""))

        let cask = try Self.text("packaging/Casks/vitrine.rb")
        #expect(cask.contains("depends_on macos: :sequoia"))
        #expect(!cask.contains("depends_on macos: :sonoma"))
    }

    @Test func publicDocumentationAndWebsiteAgreeOnTheSequoiaFloor() throws {
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
