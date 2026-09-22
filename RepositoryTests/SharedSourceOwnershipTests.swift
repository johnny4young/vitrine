import Foundation
import Testing

/// Target ownership is a build-time contract, complementary to app/CLI behavior tests.
@Suite("Shared source ownership")
struct SharedSourceOwnershipTests {
    @Test func cliLinksSharedModulesInsteadOfCompilingAppAdapters() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: root.appending(path: "project.yml"), encoding: .utf8)
        let core = try #require(
            project.components(separatedBy: "  VitrineCLICore:\n").last?
                .components(separatedBy: "  VitrineCLI:\n").first)
        let paths = core.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        .filter { $0.hasPrefix("- path:") }
        #expect(Set(paths) == ["- path: Vitrine/CLI", "- path: VitrineCLI"])
        #expect(core.contains("- target: VitrineDomain"))
        #expect(core.contains("- target: VitrineRendering"))
        #expect(!core.contains("- target: Vitrine\n"))
    }
}
