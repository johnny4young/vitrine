import Foundation

/// The one place a Swift test reads the app's version out of `project.yml`.
///
/// Three suites used to carry their own copy of this regex in a dialect that accepts
/// `1.3.0-beta.1`, which the release tag guard rejects outright
/// (`^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`). This mirrors
/// `scripts/project-version.sh` — same field, same strict dialect — so the shell and
/// Swift halves of the release gates cannot read the same file differently.
///
/// Listed in both the app-hosted and repository test targets, because the suites that
/// need it now live in different bundles.
enum ProjectVersion {
    /// The repository root, derived from this file's own location rather than a
    /// per-suite constant, so both bundles resolve the same path.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    /// `MARKETING_VERSION` as `project.yml` sets it, rejecting any form the release
    /// workflow would refuse to tag.
    static func marketing() throws -> String {
        try read(
            "MARKETING_VERSION", matching: #"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"#)
    }

    /// `CURRENT_PROJECT_VERSION`, the build number Sparkle compares.
    static func build() throws -> String {
        try read("CURRENT_PROJECT_VERSION", matching: #"[1-9][0-9]*"#)
    }

    private static func read(_ field: String, matching value: String) throws -> String {
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"(?m)^\s*\#(field):\s*"?(\#(value))"?\s*$"#)
        guard
            let match = regex.firstMatch(
                in: project, range: NSRange(project.startIndex..<project.endIndex, in: project)),
            let range = Range(match.range(at: 1), in: project)
        else {
            throw ProjectVersionError.unreadable(field)
        }
        return String(project[range])
    }

    enum ProjectVersionError: Error, CustomStringConvertible {
        case unreadable(String)

        var description: String {
            switch self {
            case .unreadable(let field):
                "project.yml does not set \(field) in the form the release gates require"
            }
        }
    }
}
