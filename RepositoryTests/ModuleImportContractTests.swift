import Foundation
import Testing

/// App, CLI, rendering and test sources import `VitrineDomain` and `VitrineRendering` by name.
///
/// Two files of compatibility typealiases used to forward 83 names from those modules into
/// the app target, so a file could use a domain or rendering type without importing the
/// module that declares it. That hid every cross-module dependency from review, let files
/// skip the imports `MemberImportVisibility` asks for, and let a module-wide alias shadow
/// SwiftUI's own `BackgroundStyle` without anyone noticing. With the imports explicit the
/// aliases are gone, and this keeps them from quietly coming back: as a file-scope alias,
/// renamed or not, or as an `@_exported import`.
///
/// A `private` or `fileprivate` alias is allowed: it is how a single file names the domain
/// `BackgroundStyle` next to SwiftUI's, and it cannot leak into other files. So is an alias
/// nested in a type, which is reached only through that type.
@Suite("Module imports stay explicit")
struct ModuleImportContractTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func noSourceForwardsATypeFromAnotherVitrineModule() throws {
        // Every type either module declares, so an alias that renames one is caught too.
        let declaration = try Regex(
            #"\b(?:public|open)\s+(?:final\s+)?(?:struct|enum|class|protocol|actor|typealias)\s+(\w+)"#
        )
        var owners: [String: Set<String>] = [:]
        for module in ["VitrineDomain", "VitrineRendering"] {
            for file in Self.swiftFiles(in: module) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for match in source.matches(of: declaration) {
                    guard let name = match.output[1].substring else { continue }
                    owners[String(name), default: []].insert(module)
                }
            }
        }

        let reexport = try Regex(
            #"@_exported\s+import\s+(?:\w+\s+)?(Vitrine(?:Domain|Rendering))\b"#)
        let alias = try Regex(
            #"(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal)\s+)?typealias\s+\w+(?:<[^>]*>)?\s*=\s*(.*)"#
        )
        let target = try Regex(#"(?:(Vitrine(?:Domain|Rendering))\.)?(\w+)"#)
        var scanned = 0
        var offenders: [String] = []
        for directory in [
            "Vitrine", "VitrineCLI", "VitrineMenuBarHelper", "VitrineRendering", "Tests", "UITests",
            "DomainTests", "RenderingTests",
        ] {
            for file in Self.swiftFiles(in: directory) {
                scanned += 1
                let source = try String(contentsOf: file, encoding: .utf8)
                let path = file.path.replacingOccurrences(of: Self.root.path + "/", with: "")
                for match in source.matches(of: reexport)
                where match.output[1].substring.map(String.init) != directory {
                    offenders.append("\(path): @_exported import")
                }
                let lines = source.components(separatedBy: "\n")
                var conditionals = 0
                for (index, line) in lines.enumerated() {
                    let code = line.drop(while: { $0 == " " })
                    if code.hasPrefix("#if") { conditionals += 1 }
                    if code.hasPrefix("#endif") { conditionals -= 1 }
                    // swift-format indents one level per enclosing brace or `#if`, so a line
                    // indented once per `#if` around it is at file scope.
                    guard line.count - code.count == 4 * conditionals,
                        let match = code.wholeMatch(of: alias)
                    else { continue }
                    var right = match.output[1].substring ?? ""
                    if right.isEmpty, index + 1 < lines.count {
                        right = lines[index + 1].drop(while: { $0 == " " })
                    }
                    guard let named = right.prefixMatch(of: target) else { continue }
                    let modules =
                        named.output[1].substring.map { Set([String($0)]) }
                        ?? owners[String(named.output[2].substring ?? ""), default: []]
                    if !modules.subtracting([directory]).isEmpty {
                        offenders.append("\(path):\(index + 1)")
                    }
                }
            }
        }
        #expect(scanned > 300, "the scan must actually reach the app, CLI and test sources")
        #expect(
            offenders.isEmpty,
            "import the module instead of forwarding its types: \(offenders.joined(separator: ", "))"
        )
    }

    private static func swiftFiles(in directory: String) -> [URL] {
        let files = FileManager.default.enumerator(
            at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil)
        return (files?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
    }
}
