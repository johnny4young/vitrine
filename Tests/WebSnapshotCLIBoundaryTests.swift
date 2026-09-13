import Foundation
import Testing

/// The CLI links no WebKit, and after the presenter seam was removed nothing stands
/// between the command surfaces and the WebKit-backed window: they name
/// `WebSnapshotWindowController.shared` directly. What keeps the headless tool clean is
/// therefore a property of the CLI's source list — no file that names the controller is
/// compiled into `VitrineCLI` or the `VitrineCLICore` library it links.
///
/// A comment cannot enforce that, and an earlier comment proved the point by naming a
/// directory that does not call the controller while omitting two that do. This derives
/// the calling files from the sources instead, so adding a caller to a directory the CLI
/// compiles, or naming a caller in the CLI's source list, fails here rather than silently
/// linking WebKit into the tool.
@Suite("Web Snapshot CLI boundary")
struct WebSnapshotCLIBoundaryTests {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Files under `Vitrine/` that name the WebKit-backed window, relative to the repository.
    private static func callingFiles() throws -> [String] {
        let appRoot = repositoryRoot.appendingPathComponent("Vitrine", isDirectory: true)
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: appRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))
        var files: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard
                sourceCodeWithoutLineComments(source).contains("WebSnapshotWindowController.shared")
            else { continue }
            files.append(url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: ""))
        }
        return files.sorted()
    }

    @Test func noFileNamingTheWebKitWindowCompilesIntoTheCLI() throws {
        let callers = try Self.callingFiles()
        #expect(
            !callers.isEmpty, "the controller must be named somewhere, or this guard is vacuous")

        let sources = try PermissionMatrix.cliSourcePaths()
        #expect(sources.contains("Vitrine/CLI"), "Did not locate the CLI sources in project.yml")
        #expect(
            !sources.contains { $0 == "Vitrine" || $0.hasPrefix("Vitrine/WebRendering") },
            "the CLI must compile neither the whole app tree nor the WebKit renderers: \(sources)")

        for caller in callers {
            let compiledBy = sources.filter { caller == $0 || caller.hasPrefix($0 + "/") }
            #expect(
                compiledBy.isEmpty,
                "\(caller) names WebSnapshotWindowController, so the CLI must not compile it (\(compiledBy))"
            )
        }
    }
}
