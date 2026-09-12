import Foundation
import Testing

/// App, CLI and test sources import `VitrineDomain` and `VitrineRendering` by name.
///
/// Two files of compatibility typealiases used to forward 83 names from those modules into
/// the app target, so a file could use a domain or rendering type without importing the
/// module that declares it. That hid every cross-module dependency from review, made
/// `MemberImportVisibility` impossible to enable, and let a module-wide alias shadow
/// SwiftUI's own `BackgroundStyle` without anyone noticing. With the imports explicit the
/// aliases are gone, and this keeps one from quietly coming back.
///
/// A `private` or `fileprivate` alias is allowed: it is how a single file names the domain
/// `BackgroundStyle` next to SwiftUI's, and it cannot leak into other files.
@Suite("Module imports stay explicit")
struct ModuleImportContractTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func noSourceForwardsATypeFromAnotherVitrineModule() throws {
        let forwarding = try Regex(
            #"^\s*(?:public\s+|internal\s+)?typealias\s+\w+\s*=\s*Vitrine(?:Domain|Rendering)\.\w+"#
        )
        var scanned = 0
        var offenders: [String] = []
        for directory in ["Vitrine", "VitrineCLI", "VitrineMenuBarHelper", "Tests", "UITests"] {
            let base = Self.root.appendingPathComponent(directory)
            guard
                let files = FileManager.default.enumerator(
                    at: base, includingPropertiesForKeys: nil)
            else { continue }
            for case let file as URL in files where file.pathExtension == "swift" {
                scanned += 1
                let source = try String(contentsOf: file, encoding: .utf8)
                for (index, line) in source.components(separatedBy: .newlines).enumerated()
                where line.firstMatch(of: forwarding) != nil {
                    let path = file.path.replacingOccurrences(of: Self.root.path + "/", with: "")
                    offenders.append("\(path):\(index + 1)")
                }
            }
        }
        #expect(scanned > 300, "the scan must actually reach the app, CLI and test sources")
        #expect(
            offenders.isEmpty,
            "import the module instead of forwarding its types: \(offenders.joined(separator: ", "))"
        )
    }
}
