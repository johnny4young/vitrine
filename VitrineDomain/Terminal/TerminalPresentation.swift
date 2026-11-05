import Foundation

/// Which colors a terminal capture's ANSI indexes resolve to.
public enum TerminalPaletteMode: String, CaseIterable, Codable, Hashable, Sendable {
    /// The Style theme's terminal palette.
    case theme
    /// The standard xterm colors, whatever the theme.
    case raw
}

/// The project, branch and command a terminal header shows, parsed from the header's own
/// filename and title. It never reads the transcript, so it can't surface a redacted row.
public struct TerminalHeaderContext: Equatable, Sendable {
    public enum Prompt: String, CaseIterable, Sendable {
        case dollar = "$"
        case chevron = "›"
        case none = ""
    }

    /// The separator `vgrab` writes between project and branch.
    private static let separator = " · "

    public var labels: [String]
    public var prompt: Prompt
    public var command: String?

    public init(filename: String?, title: String?) {
        labels = filename?.components(separatedBy: Self.separator) ?? []
        prompt = .none
        command = title
        for glyph in Prompt.allCases where glyph != .none {
            if let title, title.hasPrefix("\(glyph.rawValue) ") {
                prompt = glyph
                command = String(title.dropFirst(glyph.rawValue.count + 1))
                break
            }
        }
    }

    public var filename: String? {
        labels.isEmpty ? nil : labels.joined(separator: Self.separator)
    }

    public var title: String? {
        command.map { prompt == .none ? $0 : "\(prompt.rawValue) \($0)" }
    }

    public var canHideArguments: Bool {
        command.map { Self.withoutArguments($0) != $0 } ?? false
    }

    public mutating func hideArguments() {
        command = command.flatMap(Self.withoutArguments)
    }

    /// The command's own name. A leading `VAR=value` can hold a token and a command's
    /// directory can name a user, so neither survives.
    private static func withoutArguments(_ command: String) -> String? {
        let words = command.split(whereSeparator: \.isWhitespace)
        guard let word = words.first(where: { !$0.contains("=") }) else { return nil }
        let name = word.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init)
    }
}
