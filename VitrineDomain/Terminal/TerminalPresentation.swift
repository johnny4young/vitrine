import Foundation

/// Which colors a terminal capture's ANSI indexes resolve to.
public enum TerminalPaletteMode: String, CaseIterable, Codable, Hashable, Sendable {
    /// The Style theme's terminal palette.
    case theme
    /// The standard xterm colors, whatever the theme.
    case raw
}

/// How a terminal capture draws its cursor. `hidden` draws nothing.
public enum TerminalCursorStyle: String, CaseIterable, Codable, Hashable, Sendable {
    case hidden, block, bar

    /// The runs that draw this cursor over one cell. A bar is a separate zero-advance glyph,
    /// so it neither replaces the cell nor shifts the row. A cell's own background paints over
    /// a glyph drawn before it, so a bar on a colored cell inverts the cell instead.
    public func runs(over cell: String = " ", style: ANSIStyle = ANSIStyle()) -> [ANSIRun] {
        switch self {
        case .hidden:
            return [ANSIRun(text: cell, style: style)]
        case .bar where style.background == .default && !style.inverse:
            var bar = ANSIStyle()
            bar.isCursorBar = true
            return [ANSIRun(text: "\u{258F}", style: bar), ANSIRun(text: cell, style: style)]
        case .block, .bar:
            var inverted = style
            inverted.inverse.toggle()
            return [ANSIRun(text: cell, style: inverted)]
        }
    }
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
    /// The title without its prompt glyph.
    public private(set) var titleText: String?

    /// Only text behind a prompt glyph is a command: a plain title is just a title.
    public var command: String? { prompt == .none ? nil : titleText }

    public init(filename: String?, title: String?) {
        labels = filename?.components(separatedBy: Self.separator) ?? []
        prompt = .none
        titleText = title
        for glyph in Prompt.allCases where glyph != .none {
            if let title, title.hasPrefix("\(glyph.rawValue) ") {
                prompt = glyph
                titleText = String(title.dropFirst(glyph.rawValue.count + 1))
                break
            }
        }
    }

    public var filename: String? {
        labels.isEmpty ? nil : labels.joined(separator: Self.separator)
    }

    public var title: String? {
        titleText.map { prompt == .none ? $0 : "\(prompt.rawValue) \($0)" }
    }

    public var canRemoveArguments: Bool {
        command.map { Self.commandName(in: $0) != $0 } ?? false
    }

    public mutating func removeArguments() {
        guard let command else { return }
        titleText = Self.commandName(in: command)
    }

    public mutating func removeTitle() {
        titleText = nil
    }

    /// The command's own name, read the way a shell would, or `nil` when the first word
    /// isn't plausibly one. Assignments can hold a token and a directory can name a user.
    private static func commandName(in command: String) -> String? {
        let words = shellWords(command)
        guard let word = words.first(where: { $0.raw.prefixMatch(of: /[A-Za-z_]\w*=/) == nil }),
            word.value.wholeMatch(of: /[A-Za-z0-9._+~\/-]+/) != nil,
            let name = word.value.split(separator: "/").last,
            name.wholeMatch(of: /[A-Za-z0-9_.][A-Za-z0-9._+~-]*/) != nil,
            name.contains(where: { $0.isLetter || $0.isNumber })
        else { return nil }
        return String(name)
    }

    /// The words of the first simple command, honoring quotes and backslashes. An unclosed
    /// quote yields none: where its words end can't be known.
    private static func shellWords(_ text: String) -> [(raw: String, value: String)] {
        var words: [(raw: String, value: String)] = []
        var raw = ""
        var value = ""
        var quote: Character?
        let characters = Array(text)
        var index = 0
        scan: while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            index += 1
            switch (quote, character) {
            case ("'", "'"), ("\"", "\""):
                quote = nil
                raw.append(character)
            case ("'", _):
                raw.append(character)
                value.append(character)
            case (_, "\\"):
                guard let next else { return [] }
                raw += [character, next]
                value.append(next)
                index += 1
            case ("\"", _):
                raw.append(character)
                value.append(character)
            case (nil, "'"), (nil, "\""):
                quote = character
                raw.append(character)
            case (nil, ";"), (nil, "|"), (nil, "&"), (nil, "<"), (nil, ">"), (nil, "`"):
                break scan
            case (nil, "$") where next == "(":
                break scan
            case (nil, _) where character.isWhitespace:
                if !raw.isEmpty { words.append((raw, value)) }
                raw = ""
                value = ""
            default:
                raw.append(character)
                value.append(character)
            }
        }
        if quote != nil { return [] }
        if !raw.isEmpty { words.append((raw, value)) }
        return words
    }
}
