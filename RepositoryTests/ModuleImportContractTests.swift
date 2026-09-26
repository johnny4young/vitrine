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
                let path = file.relativePath(from: Self.root) ?? file.path
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

    /// With `MemberImportVisibility` on, a file that calls a member declared in another
    /// module's extension must import that module itself. Without it, one import anywhere
    /// in a target made those members visible in every file, which is how 84 imports were
    /// missing when it was first enabled.
    ///
    /// The project's base settings turn it on for every target. Anywhere else that sets it may
    /// only repeat `YES`, and no compiler flag may disable the feature. That covers a target or
    /// configuration in `project.yml` (bare or quoted key); every xcconfig the project names, a
    /// command line passes with `-xcconfig` or `XCODE_XCCONFIG_FILE`, or one of those includes;
    /// and the `xcodebuild` command lines in the Makefile, workflows, and scripts, whose
    /// overrides beat every project setting. `scripts/check-swift-features.py` checks the same
    /// thing on CI from what the compiler was actually invoked with.
    @Test func memberImportVisibilityStaysOnForEveryTarget() throws {
        let project = try String(
            contentsOf: Self.root.appendingPathComponent("project.yml"), encoding: .utf8)
        let base = Self.memberImportVisibility(
            in: Self.projectBaseSettings(of: project), comments: ["#"])
        #expect(
            base.values == ["YES"],
            "set MemberImportVisibility to YES in the project's base settings: \(base.values)")

        var sources = [("project.yml", project)]
        for file in [Self.root.appendingPathComponent("Makefile")]
            + Self.files(in: ".github", withExtensions: ["yml", "yaml"])
            + Self.files(in: "scripts", withExtensions: ["sh", "py", "rb", "swift"])
        {
            sources.append((file.lastPathComponent, try String(contentsOf: file, encoding: .utf8)))
        }

        // Every xcconfig the project names, plus any a command line passes.
        var pending: [URL] = []
        for line in project.components(separatedBy: .newlines) {
            var value = Self.withoutComment(line, markers: ["#"])
                .trimmingCharacters(in: Self.quotesAndSpaces)
            if value.hasPrefix("- ") { value = String(value.dropFirst(2)) }
            guard value.hasSuffix(".xcconfig") else { continue }
            let path = value.split(separator: ":", maxSplits: 1).last ?? Substring(value)
            pending.append(
                Self.root.appendingPathComponent(path.trimmingCharacters(in: Self.quotesAndSpaces)))
        }
        let passed = try Regex(#"(?:-xcconfig\s+|XCODE_XCCONFIG_FILE=)["']?([^\s"']+\.xcconfig)"#)
        for (_, text) in sources {
            for match in text.matches(of: passed) {
                if let path = match.output[1].substring {
                    pending.append(Self.root.appendingPathComponent(String(path)))
                }
            }
        }
        var visited: Set<URL> = []
        while let xcconfig = pending.popLast()?.standardizedFileURL {
            guard visited.insert(xcconfig).inserted else { continue }
            guard FileManager.default.fileExists(atPath: xcconfig.path) else {
                Issue.record("a named xcconfig does not exist: \(xcconfig.path)")
                continue
            }
            let text = try String(contentsOf: xcconfig, encoding: .utf8)
            sources.append((xcconfig.lastPathComponent, text))
            for line in text.components(separatedBy: .newlines) {
                let directive = line.trimmingCharacters(in: .whitespaces)
                guard directive.hasPrefix("#include"),
                    let open = directive.firstIndex(of: "\""),
                    let close = directive.lastIndex(of: "\""), open < close
                else { continue }
                let included = xcconfig.deletingLastPathComponent()
                    .appendingPathComponent(String(directive[directive.index(after: open)..<close]))
                // `#include?` names an optional file; a plain `#include` must exist.
                if directive.hasPrefix("#include?"),
                    !FileManager.default.fileExists(atPath: included.path)
                {
                    continue
                }
                pending.append(included)
            }
        }

        for (name, text) in sources {
            let markers: Set<String> =
                name.hasSuffix(".xcconfig") || name.hasSuffix(".swift") ? ["//"] : ["#"]
            let found = Self.memberImportVisibility(in: text, comments: markers)
            #expect(
                found.values.allSatisfy { $0 == "YES" },
                "\(name) sets MemberImportVisibility to something other than YES: \(found.values)")
            #expect(
                found.compilerFlags.isEmpty,
                "\(name) disables MemberImportVisibility with a compiler flag: \(found.compilerFlags)"
            )
        }
    }

    /// Every value `text` gives `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`, bare or quoted,
    /// with or without xcconfig conditions such as `[config=Release]`, and written as `key: value`
    /// (YAML) or `key = value` (xcconfig and command lines). Also every `-disable-upcoming-feature`
    /// flag that names the feature, on the same line or, for a YAML list, on the next one.
    private static func memberImportVisibility(
        in text: String, comments: Set<String>
    ) -> (values: [String], compilerFlags: [String]) {
        var values: [String] = []
        var compilerFlags: [String] = []
        var previous: Substring = ""
        for rawLine in text.components(separatedBy: .newlines) {
            let line = Self.withoutComment(rawLine, markers: comments)
            defer { previous = line }
            if line.contains("MemberImportVisibility"),
                line.contains("disable-upcoming-feature")
                    || previous.contains("disable-upcoming-feature")
            {
                compilerFlags.append(line.trimmingCharacters(in: .whitespaces))
            }
            guard let key = line.range(of: "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY") else {
                continue
            }
            var rest = line[key.upperBound...]
            while let first = rest.first,
                first == "[" || first == "\"" || first == "'" || first == " "
            {
                if first == "[", let close = rest.firstIndex(of: "]") {
                    rest = rest[rest.index(after: close)...]
                } else {
                    rest = rest.dropFirst()
                }
            }
            guard rest.first == ":" || rest.first == "=" else { continue }
            values.append(rest.dropFirst().trimmingCharacters(in: Self.quotesAndSpaces))
        }
        return (values, compilerFlags)
    }

    /// The project's own `settings.base` block: the lines under the top-level `settings:` and its
    /// `  base:` key, up to the next key at that depth (`  configs:`) or the next section.
    /// Comments and blank lines neither start nor end a block.
    private static func projectBaseSettings(of project: String) -> String {
        var inSettings = false
        var inBase = false
        var lines: [String] = []
        for rawLine in project.components(separatedBy: .newlines) {
            let line = Self.withoutComment(rawLine, markers: ["#"])
            let key = line.trimmingCharacters(in: .whitespaces)
            if key.isEmpty { continue }
            if !inSettings {
                inSettings = !line.hasPrefix(" ") && key == "settings:"
                continue
            }
            if inBase {
                if !line.hasPrefix("    ") { break }
                lines.append(String(line))
            } else if line.hasPrefix("  ") && !line.hasPrefix("   ") && key == "base:" {
                inBase = true
            } else if !line.hasPrefix(" ") {
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    /// `line` up to its first comment marker. `#` starts a comment in YAML, make, shell and
    /// Python; `//` does so in xcconfig and Swift, where a `#` would also cut `#include`, and in
    /// the other files it is usually part of a URL.
    private static func withoutComment(_ line: String, markers: Set<String>) -> Substring {
        var code = Substring(line)
        for marker in markers {
            if let comment = code.range(of: marker) { code = code[..<comment.lowerBound] }
        }
        return code
    }

    private static let quotesAndSpaces = CharacterSet(charactersIn: " \"'")

    private static func files(in directory: String, withExtensions extensions: Set<String>) -> [URL]
    {
        let files = FileManager.default.enumerator(
            at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil)
        return (files?.allObjects as? [URL] ?? []).filter { extensions.contains($0.pathExtension) }
    }

    private static func swiftFiles(in directory: String) -> [URL] {
        files(in: directory, withExtensions: ["swift"])
    }
}
