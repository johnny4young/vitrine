import Foundation

/// Where the CLI got a diff it handed to the editor. It holds only what the refresh
/// command needs: the range, root-relative pathspecs and the repository folder's name,
/// never an absolute path or a remote. Every initializer validates, because a value can
/// arrive from a restored window or a share link.
public struct DiffSource: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case range, staged
    }

    public private(set) var kind: Kind
    public private(set) var range: String?
    public private(set) var repository: String?
    public private(set) var paths: [String]
    /// `nil` for Git's default context, so the command stays short.
    public private(set) var contextLines: Int?
    /// Share links carry the source only after the user turns this on.
    public var sharesInLinks = false
    /// Arrived in a share link, so its repository name is someone else's text.
    public var isReceived = false
    /// Tells two loads of the same range apart, so an edit that only carries the source
    /// forward can drop it. Never encoded or compared.
    public var loadID: UUID?

    /// Limits count UTF-8 bytes, so combining marks can't stretch a field.
    static let maxRangeBytes = 256
    static let maxNameBytes = 64
    static let maxPaths = 32
    static let maxPathBytes = 1_024
    static let contextLinesRange = 0...100
    private static let rangePunctuation = Set("._/-~^@{}!".unicodeScalars)
    private static let namePunctuation = Set("._-".unicodeScalars)

    public init?(
        kind: Kind, range: String? = nil, repository: String? = nil, paths: [String] = [],
        contextLines: Int? = nil
    ) {
        switch kind {
        case .range: guard let range, Self.isValidRange(range) else { return nil }
        case .staged: guard range == nil else { return nil }
        }
        guard repository.map(Self.isValidRepository) ?? true, paths.count <= Self.maxPaths,
            paths.allSatisfy(Self.isValidPath),
            contextLines.map(Self.contextLinesRange.contains) ?? true
        else { return nil }
        self.kind = kind
        self.range = range
        self.repository = repository
        self.paths = paths
        self.contextLines = contextLines
    }

    /// ASCII letters, digits and the revision punctuation Git uses (`main...topic`,
    /// `HEAD~2^`, `@{u}`). No spaces, quotes, `$`, `;` or `:`, so no shell or URL fits.
    static func isValidRange(_ range: String) -> Bool {
        (1...maxRangeBytes).contains(range.utf8.count) && !range.hasPrefix("-")
            && range.unicodeScalars.allSatisfy {
                isASCIIAlphanumeric($0) || rangePunctuation.contains($0)
            }
    }

    /// A folder name only, so the confirmation can't be made to read like an instruction.
    public static func isValidRepository(_ name: String) -> Bool {
        (1...maxNameBytes).contains(name.utf8.count) && name != "." && name != ".."
            && name.unicodeScalars.allSatisfy {
                isASCIIAlphanumeric($0) || namePunctuation.contains($0)
            }
    }

    /// Relative to the repository root and inside it.
    static func isValidPath(_ path: String) -> Bool {
        (1...maxPathBytes).contains(path.utf8.count) && !path.hasPrefix("/")
            && !path.hasPrefix("~") && !containsControlCharacter(path)
            && !path.split(separator: "/").contains("..")
    }

    private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII
            && (scalar.properties.isAlphabetic || scalar.properties.numericType == .decimal)
    }

    private static func containsControlCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format
        }
    }

    /// The `vitrine` arguments that hand the same diff to the editor again, run from the
    /// repository root. Shell quoting is the caller's job.
    public var refreshArguments: [String] {
        var arguments = ["vitrine", "render"]
        switch kind {
        case .range: arguments += ["--git-diff", range ?? ""]
        case .staged: arguments.append("--git-staged")
        }
        for path in paths { arguments += ["--git-path", path] }
        if let contextLines { arguments += ["--git-context", String(contextLines)] }
        return arguments + ["--edit"]
    }

    /// The Git side of the source for the chip, such as `git diff main...topic`.
    public var gitSummary: String {
        var parts = ["git diff", kind == .range ? range ?? "" : "--cached"]
        if !paths.isEmpty { parts += ["--"] + paths }
        return parts.joined(separator: " ")
    }

    /// The text a share link would carry beyond the kind of source.
    public var linkDetails: [String] {
        [range, repository].compactMap { $0 } + paths
    }

    public static func == (lhs: DiffSource, rhs: DiffSource) -> Bool {
        (lhs.kind, lhs.range, lhs.repository, lhs.paths, lhs.contextLines)
            == (rhs.kind, rhs.range, rhs.repository, rhs.paths, rhs.contextLines)
            && (lhs.sharesInLinks, lhs.isReceived) == (rhs.sharesInLinks, rhs.isReceived)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, range, repository, paths, contextLines, sharesInLinks, isReceived
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard
            var source = try DiffSource(
                kind: container.decode(Kind.self, forKey: .kind),
                range: container.decodeIfPresent(String.self, forKey: .range),
                repository: container.decodeIfPresent(String.self, forKey: .repository),
                paths: container.decodeIfPresent([String].self, forKey: .paths) ?? [],
                contextLines: container.decodeIfPresent(Int.self, forKey: .contextLines))
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "Invalid diff source")
        }
        source.sharesInLinks =
            (try? container.decodeIfPresent(Bool.self, forKey: .sharesInLinks)) ?? false
        source.isReceived =
            (try? container.decodeIfPresent(Bool.self, forKey: .isReceived)) ?? false
        self = source
    }
}
