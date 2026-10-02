import Foundation
import VitrineDomain

/// Static, escaped markup shared by documentation packages and CLI sidecars.
public enum HTMLExport {
    public static func document(for config: SnapshotConfig, imageSource: String) -> String {
        let title = escape(
            config.metadata.title ?? config.metadata.filename ?? "Vitrine render",
            flattenLines: false)
        let alt = escape(
            config.altText?.text ?? config.metadata.filename
                ?? (config.usesImageContent
                    ? "Image styled with Vitrine" : "Code rendered with Vitrine"))
        let language = config.language == .terminal ? "text" : config.language.rawValue
        let transcript =
            config.usesImageContent
            ? ""
            : "\n    <pre><code class=\"language-\(escape(language))\">\(escape(config.sidecarText, flattenLines: false))</code></pre>"
        return """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <title>\(title)</title>
            </head>
            <body>
              <figure>
                <img src="\(escape(imageSource))" alt="\(alt)">\(transcript)
              </figure>
            </body>
            </html>
            """ + "\n"
    }

    private static func escape(_ input: String, flattenLines: Bool = true) -> String {
        let escaped = input.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return flattenLines
            ? escaped.replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(
                of: "'", with: "&#39;"
            ).replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(
                    of: "\n", with: " ") : escaped
    }
}
