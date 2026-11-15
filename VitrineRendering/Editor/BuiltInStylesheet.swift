import AppKit

/// A bundled stylesheet applied in source order, unlike Highlightr's per-launch dictionary
/// order. Descendant selectors style only inside their ancestors; otherwise it matches
/// Highlightr, including one key per `class` attribute, so compound selectors never match.
struct BuiltInStylesheet {
    /// The card background, from the `.hljs` rule.
    let background: NSColor?

    private struct Rule {
        let ancestors: [String]
        let target: String
        let declarations: [(property: String, value: String)]
    }

    private let rules: [Rule]
    private let rulesByTarget: [String: [Int]]

    init(css: String) {
        var rules: [Rule] = []
        let stripped = css.replacing(/\/\*[\s\S]*?\*\//, with: "")
        for match in stripped.matches(of: /([^{}]+)\{([^}]*)\}/) {
            let declarations = Self.declarations(String(match.output.2))
            guard !declarations.isEmpty else { continue }
            for selector in match.output.1.split(separator: ",") {
                guard let (ancestors, target) = Self.parse(selector) else { continue }
                rules.append(
                    Rule(ancestors: ancestors, target: target, declarations: declarations))
            }
        }
        self.rules = rules
        self.rulesByTarget = Dictionary(grouping: rules.indices, by: { rules[$0].target })

        var background: String?
        for index in rulesByTarget["hljs"] ?? [] where rules[index].ancestors.isEmpty {
            for (property, value) in rules[index].declarations
            where property == "background" || property == "background-color" {
                background = value
            }
        }
        self.background = background.map(Self.color)
    }

    /// Paints Highlight.js `html` in `font`, with bold and italic tokens in the same
    /// family's variants.
    func attributedString(html: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var stack = ["hljs"]
        var cache: [[String]: [NSAttributedString.Key: Any]] = [:]
        var fonts: [FontStyle: NSFont] = [:]

        func append(_ text: Substring) {
            guard !text.isEmpty else { return }
            let styled: [NSAttributedString.Key: Any]
            if let cached = cache[stack] {
                styled = cached
            } else {
                styled = attributes(for: stack, font: font, fonts: &fonts)
                cache[stack] = styled
            }
            result.append(
                NSAttributedString(string: Self.decodingEntities(text), attributes: styled))
        }

        var rest = html[...]
        while let open = rest.firstIndex(of: "<") {
            append(rest[..<open])
            let tag = rest[open...]
            if tag.hasPrefix("</span>") {
                if stack.count > 1 { stack.removeLast() }
                rest = tag.dropFirst("</span>".count)
            } else if tag.hasPrefix("<span class=\""),
                let close = tag.firstRange(of: "\">")
            {
                stack.append(String(tag[tag.index(open, offsetBy: 13)..<close.lowerBound]))
                rest = tag[close.upperBound...]
            } else {
                append("<")
                rest = tag.dropFirst()
            }
        }
        append(rest)
        return result
    }

    private enum FontStyle { case regular, bold, italic }

    private func attributes(
        for stack: [String], font: NSFont, fonts: inout [FontStyle: NSFont]
    ) -> [NSAttributedString.Key: Any] {
        var color: NSColor?
        var backgroundColor: NSColor?
        var style = FontStyle.regular
        for (depth, key) in stack.enumerated() {
            let matching = (rulesByTarget[key] ?? []).filter {
                rules[$0].ancestors.isEmpty
                    || Self.contains(stack[..<depth], inOrder: rules[$0].ancestors)
            }
            // Contextual rules are more specific than a plain class, so they apply last.
            let ordered =
                matching.filter { rules[$0].ancestors.isEmpty }
                + matching.filter { !rules[$0].ancestors.isEmpty }
            for index in ordered {
                for (property, value) in rules[index].declarations {
                    switch property {
                    case "color": color = Self.color(value)
                    case "background-color": backgroundColor = Self.color(value)
                    case "font-weight", "font-style": style = Self.fontStyle(value)
                    default: break
                    }
                }
            }
        }
        var attributes: [NSAttributedString.Key: Any] = [:]
        attributes[.font] =
            fonts[style]
            ?? {
                let resolved =
                    switch style {
                    case .regular: font
                    case .bold: CodeFont.styled(font, bold: true, italic: false)
                    case .italic: CodeFont.styled(font, bold: false, italic: true)
                    }
                fonts[style] = resolved
                return resolved
            }()
        if let color { attributes[.foregroundColor] = color }
        if let backgroundColor { attributes[.backgroundColor] = backgroundColor }
        return attributes
    }

    /// Splits `.a .b.c` into ancestor classes and the target, or `nil` for a selector
    /// Highlight.js output cannot match as one class key (a compound class or a pseudo-element).
    /// Element names are dropped, so `pre code.hljs` styles `.hljs`.
    private static func parse(_ selector: Substring) -> (ancestors: [String], target: String)? {
        var classes: [String] = []
        for part in selector.split(whereSeparator: \.isWhitespace) {
            guard !part.contains(":") else { return nil }
            let names = part.split(separator: ".", omittingEmptySubsequences: false).dropFirst()
            guard names.count <= 1 else { return nil }
            if let name = names.first, !name.isEmpty { classes.append(String(name)) }
        }
        guard let target = classes.popLast() else { return nil }
        return (classes, target)
    }

    private static func declarations(_ body: String) -> [(property: String, value: String)] {
        body.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (
                parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func contains(
        _ stack: ArraySlice<String>, inOrder ancestors: [String]
    )
        -> Bool
    {
        var remaining = ancestors[...]
        for key in stack where key == remaining.first {
            remaining.removeFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    private static func fontStyle(_ value: String) -> FontStyle {
        switch value {
        case "bold", "bolder", "600", "700", "800", "900": .bold
        case "italic", "oblique": .italic
        default: .regular
        }
    }

    /// Reads a color the way Highlightr does: three- or six-digit hex, five color
    /// names, and gray for anything else.
    private static func color(_ value: String) -> NSColor {
        guard value.hasPrefix("#") else {
            return switch value {
            case "white": NSColor(white: 1, alpha: 1)
            case "black": NSColor(white: 0, alpha: 1)
            case "red": NSColor(red: 1, green: 0, blue: 0, alpha: 1)
            case "green": NSColor(red: 0, green: 1, blue: 0, alpha: 1)
            case "blue": NSColor(red: 0, green: 0, blue: 1, alpha: 1)
            default: .gray
            }
        }
        let hex = Array(value.dropFirst())
        guard hex.count == 6 || hex.count == 3 else { return .gray }
        let width = hex.count / 3
        let divisor: CGFloat = width == 2 ? 255 : 15
        let channels = (0..<3).map { index in
            CGFloat(UInt64(String(hex[(index * width)..<((index + 1) * width)]), radix: 16) ?? 0)
                / divisor
        }
        return NSColor(red: channels[0], green: channels[1], blue: channels[2], alpha: 1)
    }

    /// Decodes the entities Highlight.js escapes, plus numeric references.
    private static func decodingEntities(_ text: Substring) -> String {
        guard text.contains("&") else { return String(text) }
        return String(text).replacing(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/) { match in
            let entity = match.output.1
            let scalar: UInt32? =
                switch entity {
                case "amp": 0x26
                case "lt": 0x3C
                case "gt": 0x3E
                case "quot": 0x22
                case "apos": 0x27
                default:
                    entity.hasPrefix("#x")
                        ? UInt32(entity.dropFirst(2), radix: 16)
                        : entity.hasPrefix("#") ? UInt32(entity.dropFirst()) : nil
                }
            return scalar.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                ?? String(match.output.0)
        }
    }
}
