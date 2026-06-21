import AppKit

/// The contract for handing captured content from the `vitrine` CLI to the running
/// app's editor (`vitrine render … --edit`, behind `vgrab -e` / `vlast -e`).
///
/// The CLI is a separate process and the app is sandboxed, so content cannot be passed
/// by temp-file path — the sandbox can't read an arbitrary `/tmp` file the CLI wrote.
/// Instead the CLI stages the raw text on a **private, named pasteboard** (never the
/// general clipboard, so the handoff doesn't clobber what the user has copied) and
/// opens a `vitrine://edit` URL; the app's URL handler reads the text back and seeds
/// the editor. The named pasteboard is reachable from both processes under the sandbox,
/// and `open vitrine://…` launches Vitrine if it isn't already running.
///
/// Both targets compile this file, so the scheme, host, and pasteboard name can never
/// drift between the writer (CLI) and the reader (app).
enum EditorHandoff {
    /// The custom URL scheme the app registers (Info.plist `CFBundleURLTypes`).
    static let scheme = "vitrine"
    /// The URL host that means "open the staged content in the editor".
    static let editHost = "edit"
    /// The query key carrying the language id hint (e.g. `terminal`).
    static let languageKey = "language"
    /// A private pasteboard — deliberately NOT `.general`, so staging the handoff never
    /// overwrites the user's clipboard. Both the CLI and the app address it by this name.
    static let pasteboardName = NSPasteboard.Name("app.vitrine.edit-handoff")

    /// CLI side: stage `content` on the private pasteboard and return the
    /// `vitrine://edit` URL to open. The language hint, when known, rides in the query
    /// so the app can pick the renderer without re-detecting (it still falls back to
    /// content detection when absent).
    static func stage(content: String, language: Language?) -> URL {
        let pasteboard = NSPasteboard(name: pasteboardName)
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        var components = URLComponents()
        components.scheme = scheme
        components.host = editHost
        if let language {
            components.queryItems = [URLQueryItem(name: languageKey, value: language.rawValue)]
        }
        // The components are all well-formed constants, so the URL is always buildable.
        return components.url!
    }

    /// App side: read the content staged for `url` (a `vitrine://edit` URL) and the
    /// language hint if present. Returns `nil` when `url` is not an edit handoff or the
    /// pasteboard is empty. Clears the pasteboard after a successful read so a stale
    /// payload can't seed a later, unrelated open (the handoff is one-shot).
    static func consume(url: URL) -> (content: String, language: Language?)? {
        guard url.scheme == scheme, url.host == editHost else { return nil }
        let pasteboard = NSPasteboard(name: pasteboardName)
        guard let content = pasteboard.string(forType: .string), !content.isEmpty else {
            return nil
        }
        pasteboard.clearContents()

        let languageID =
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == languageKey }?.value
        return (content, languageID.flatMap(Language.init(rawValue:)))
    }
}
