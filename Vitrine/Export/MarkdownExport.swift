import Foundation

/// Builds a portable Markdown document that pairs a rendered snapshot with the
/// copyable source shown in it.
///
/// The image source may be a neighboring filename (CLI sidecars) or a self-contained
/// data URI (clipboard export). User-controlled labels and destinations are escaped,
/// and the code fence always outgrows every backtick run in the source.
enum MarkdownExport {
    static func document(for config: SnapshotConfig, imageSource: String) -> String {
        let body = config.sidecarText
        let fenceLanguage = config.language == .terminal ? "text" : config.language.rawValue
        let fence = codeFence(for: body)
        let alt = altText(config.metadata.filename ?? "Code rendered with Vitrine")
        let destination = imageDestination(imageSource)
        let trailingNewline = body.hasSuffix("\n") ? "" : "\n"
        return """
            ![\(alt)](\(destination))

            \(fence)\(fenceLanguage)
            \(body)\(trailingNewline)\(fence)
            """ + "\n"
    }

    private static func codeFence(for body: String) -> String {
        var longestBacktickRun = 0
        var currentRun = 0
        for character in body {
            currentRun = character == "`" ? currentRun + 1 : 0
            longestBacktickRun = max(longestBacktickRun, currentRun)
        }
        return String(repeating: "`", count: max(3, longestBacktickRun + 1))
    }

    /// Escapes Markdown image alt text so a source filename cannot break the image
    /// syntax or inject a new line into the generated document.
    private static func altText(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "\\":
                escaped += "\\\\"
            case "[", "]":
                escaped += "\\\(character)"
            case "\n", "\r":
                escaped += " "
            default:
                escaped.append(character)
            }
        }
        return escaped
    }

    /// Keeps plain filenames readable, but switches to an angle-bracket destination
    /// for data URIs and paths containing Markdown-significant characters.
    private static func imageDestination(_ source: String) -> String {
        let plainSafeCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~/"))
        if source.unicodeScalars.allSatisfy({ plainSafeCharacters.contains($0) }) {
            return source
        }
        let escaped = source.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "<", with: "\\<")
            .replacingOccurrences(of: ">", with: "\\>")
            .replacingOccurrences(of: "\n", with: "%0A")
            .replacingOccurrences(of: "\r", with: "%0D")
        return "<\(escaped)>"
    }
}
