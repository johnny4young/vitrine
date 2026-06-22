import AppKit

/// The contract for handing captured content from the `vitrine` CLI to the running
/// app's editor (`vitrine render … --edit`, behind `vgrab -e` / `vlast -e`).
///
/// The CLI is a separate process and the app is sandboxed, so content cannot be passed
/// by temp-file path — the sandbox can't read an arbitrary `/tmp` file the CLI wrote.
/// Instead the CLI stages the raw text on a **named pasteboard** (separate from the
/// general clipboard, so the handoff doesn't clobber what the user has copied) and opens
/// a `vitrine://edit` URL; the app's URL handler reads the text back and seeds the editor.
///
/// Each handoff uses a **fresh, random pasteboard name** (a per-call UUID token, carried
/// in the URL) rather than one well-known name. A named pasteboard is *not* confidential —
/// any process that knows the name can read it — so the random token keeps a fixed,
/// guessable name from being readable by other local processes and stops a later, stale
/// `vitrine://edit` open from consuming an unrelated payload: only the matching URL can
/// reach its pasteboard, and the read clears it. Still, this is local IPC, not a secure
/// channel — it carries terminal output the user is already choosing to share, nothing
/// more sensitive.
///
/// Both targets compile this file, so the scheme, host, query keys, and pasteboard naming
/// can never drift between the writer (CLI) and the reader (app).
enum EditorHandoff {
    /// The custom URL scheme the app registers (Info.plist `CFBundleURLTypes`).
    static let scheme = "vitrine"
    /// The URL host that means "open the staged content in the editor".
    static let editHost = "edit"
    /// The query key carrying the language id hint (e.g. `terminal`).
    static let languageKey = "language"
    /// The query key carrying the per-handoff random token that names the pasteboard.
    static let tokenKey = "token"
    /// The prefix the per-handoff token is appended to, to form a unique pasteboard name.
    private static let pasteboardPrefix = "app.vitrine.edit-handoff"

    /// CLI side: stage `content` on a fresh per-handoff pasteboard and return the
    /// `vitrine://edit` URL to open. The URL carries the random token (so only this open
    /// can consume the payload) and, when known, the language hint (so the app can pick
    /// the renderer without re-detecting; it still falls back to content detection).
    static func stage(content: String, language: Language?) -> URL {
        let token = UUID().uuidString
        let pasteboard = NSPasteboard(name: pasteboardName(for: token))
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        var components = URLComponents()
        components.scheme = scheme
        components.host = editHost
        var queryItems = [URLQueryItem(name: tokenKey, value: token)]
        if let language {
            queryItems.append(URLQueryItem(name: languageKey, value: language.rawValue))
        }
        components.queryItems = queryItems
        // The components are all well-formed, so the URL is always buildable.
        return components.url!
    }

    /// App side: read the content staged for `url` (a `vitrine://edit?token=…` URL) and
    /// the language hint if present. Returns `nil` when `url` is not an edit handoff, the
    /// token is missing/malformed, or its pasteboard is empty. Clears the pasteboard after
    /// a successful read so the handoff is one-shot and a stale open can never re-seed.
    static func consume(url: URL) -> (content: String, language: Language?)? {
        guard url.scheme == scheme, url.host == editHost,
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let token = queryItems.first(where: { $0.name == tokenKey })?.value,
            isValidToken(token)
        else { return nil }

        let pasteboard = NSPasteboard(name: pasteboardName(for: token))
        guard let content = pasteboard.string(forType: .string), !content.isEmpty else {
            return nil
        }
        pasteboard.clearContents()

        let languageID = queryItems.first { $0.name == languageKey }?.value
        return (content, languageID.flatMap(Language.init(rawValue:)))
    }

    /// The pasteboard name for a handoff `token`.
    private static func pasteboardName(for token: String) -> NSPasteboard.Name {
        NSPasteboard.Name("\(pasteboardPrefix).\(token)")
    }

    /// Whether `token` is a well-formed handoff token (a UUID string — hex digits and
    /// hyphens only). Rejecting anything else keeps a hostile `vitrine://edit?token=…`
    /// from steering the pasteboard name to an arbitrary string.
    private static func isValidToken(_ token: String) -> Bool {
        !token.isEmpty && token.count <= 36 && token.allSatisfy { $0.isHexDigit || $0 == "-" }
    }
}
