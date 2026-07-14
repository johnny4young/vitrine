import Foundation

/// Loads dropped or opened source files into editor-ready text + a language hint
/// (CS-028).
///
/// The editor lets users drop code text or a source file onto it. Turning a
/// file's bytes into something safe to render takes three guarantees, all of
/// which live here so they can be unit-tested without AppKit or a real drop:
///
/// 1. **User-selected access only.** A dropped file's URL is treated as a
///    security-scoped resource (`load(from:)` brackets the read with
///    `startAccessingSecurityScopedResource()`), so the read works under the App
///    Sandbox using the existing `files.user-selected.read-write` entitlement.
///    Nothing here widens the sandbox: there is no broad file entitlement and no
///    directory traversal — only the one file the user dropped is read.
/// 2. **Text only.** The bytes are decoded as text and a binary file is rejected
///    with a clear, user-facing error rather than dumping mojibake into the
///    editor. Detection is content-based (a NUL byte or undecodable bytes),
///    never the extension alone.
/// 3. **A language hint.** The language is inferred from the filename extension
///    first (reusing the CS-027 extension table, which also knows
///    `Dockerfile`), falling back to weighted content detection when the
///    extension is unknown — so a `.swift` file opens as Swift and a `LICENSE`
///    full of SQL still gets a reasonable guess.
///
/// Loading a file deliberately **does not** touch Recents: a load only fills the
/// editor. The filename is carried into `SnapshotConfig.metadata.filename`
/// (CS-022) so that if — and only if — the user later captures or exports, the
/// recorded snapshot reflects where the code came from. That keeps the CS-028
/// promise that "Recents record loaded file metadata only when the user
/// captures/exports."
enum FileInputLoader {
    /// A successfully loaded file: the decoded text, an inferred language, and the
    /// source file's display name (its last path component) for the metadata
    /// header.
    struct LoadedFile: Equatable {
        /// The decoded file contents, ready to drop into the editor.
        var text: String
        /// The language inferred from the extension, or from the content when the
        /// extension is unknown.
        var language: Language
        /// The source file's name (last path component), e.g. `ContentView.swift`.
        var filename: String

        /// Writes this loaded drop into `config` in place — the same mutation the
        /// editor performs once the user resolves the replace/append choice
        /// (CS-028). Kept here, free of AppKit and SwiftUI, so the policy is
        /// unit-testable rather than buried in a view's private method.
        ///
        /// - Replacing swaps the whole document and adopts the inferred language;
        ///   the filename is recorded in `metadata.filename` **only when it is
        ///   non-empty** (a dropped text payload has none), so a later
        ///   capture/export reflects the source. This is the sole Recents-facing
        ///   side effect of a load: filling `metadata` honors "Recents record
        ///   loaded file metadata only when the user captures/exports" without the
        ///   load itself ever enqueuing a Recent.
        /// - Appending keeps the current language (the existing code defines it)
        ///   and only grows the text, inserting a single newline separator just
        ///   when the current content does not already end with one.
        func apply(to config: inout SnapshotConfig, replacing: Bool) {
            if replacing {
                // Swapping the whole document is a new capture: drop content-bound marks
                // (annotations, highlighted lines) positioned over the previous code.
                config.clearContentMarks()
                config.code = text
                config.language = language
                if !filename.isEmpty {
                    config.metadata.filename = filename
                }
            } else {
                let separator = config.code.hasSuffix("\n") ? "" : "\n"
                config.code += separator + text
            }
        }
    }

    /// Why a file could not be loaded, each mapped to a clear user-facing message
    /// via `message`.
    enum LoadError: Error, Equatable {
        /// The file's bytes are not decodable text (a NUL byte was found or no
        /// supported text encoding applied) — almost certainly a binary file.
        case binaryFile
        /// The file is larger than `maximumByteCount`; refused so a huge or runaway
        /// file never freezes the editor.
        case tooLarge
        /// The bytes could not be read (permissions, a vanished file, an I/O error).
        case unreadable

        /// A short, plain-language explanation suitable for an alert body.
        /// Localized through the String Catalog (CS-047).
        var message: String {
            switch self {
            case .binaryFile:
                String(
                    localized:
                        "That file doesn't look like text. Vitrine renders source code, so binary files like images or archives can't be loaded."
                )
            case .tooLarge:
                String(
                    localized:
                        "That file is too large to load. Try a smaller source file (up to 5 MB)."
                )
            case .unreadable:
                String(
                    localized:
                        "That file couldn't be read. Check that it still exists and that you have permission to open it."
                )
            }
        }
    }

    /// The largest file the loader will accept (5 MB). A source file this big is
    /// already far past anything that renders to a usable image; the cap mainly
    /// guards against accidentally dropping a giant or binary file.
    static let maximumByteCount = 5 * 1024 * 1024

    // MARK: - File loading

    /// Loads a user-selected file at `url` into editor-ready text + a language
    /// hint (CS-028).
    ///
    /// `url` is a file the user dropped or opened, so access is bracketed by
    /// `startAccessingSecurityScopedResource()`: the read succeeds under the
    /// sandbox using only the existing user-selected entitlement, and the scope is
    /// released immediately afterward. The size cap is checked against the bytes
    /// actually read. Throws a `LoadError` the caller can present verbatim.
    static func load(from url: URL) throws -> LoadedFile {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            // Collapse any low-level I/O error into one clear message; never echo
            // the path or the system error (CS-048 privacy rule).
            Log.capture.error("File input: read failed")
            throw LoadError.unreadable
        }

        return try decode(data: data, filename: url.lastPathComponent)
    }

    // MARK: - Pure decoding (unit-testable)

    /// Turns raw file bytes + a filename into a `LoadedFile`, applying the size
    /// cap, binary rejection, text decoding, and language inference — with no
    /// filesystem or AppKit dependency, so the whole policy is unit-testable from
    /// fixtures (CS-028 tests).
    static func decode(data: Data, filename: String) throws -> LoadedFile {
        guard data.count <= maximumByteCount else { throw LoadError.tooLarge }

        guard let text = decodeText(from: data) else { throw LoadError.binaryFile }

        // An asciinema recording replays into the terminal renderer: the `.cast`
        // JSONL output events concatenate to the exact bytes the recorded session
        // wrote, which the ANSI/terminal pipeline renders as-is. A `.cast`-named
        // file that is not a real recording falls through to the ordinary path.
        if AsciinemaCast.isCastFilename(filename),
            let replay = AsciinemaCast.terminalText(from: text)
        {
            return LoadedFile(text: replay, language: .terminal, filename: filename)
        }

        let language = inferLanguage(forFilename: filename, content: text)
        return LoadedFile(text: text, language: language, filename: filename)
    }

    /// Decodes file bytes to a `String`, or `nil` when the bytes are not text.
    ///
    /// Order matters and is deliberate:
    ///
    /// 1. **A leading Unicode BOM** (UTF-16 LE/BE or UTF-8) is honored first.
    ///    UTF-16 text legitimately contains NUL bytes — every ASCII character has
    ///    a `0x00` high byte — so it must be recognized before the NUL-based binary
    ///    check below would wrongly reject it.
    /// 2. **A NUL byte** in BOM-less data is the strongest, cheapest binary tell
    ///    (text files do not contain one), so such data is rejected as binary.
    /// 3. **UTF-8** covers essentially every modern source file.
    /// 4. **Single-byte fallbacks** (Windows-1252, then ISO Latin-1) recover the
    ///    occasional legacy file without corrupting it. These always succeed for
    ///    any byte sequence, so they are tried last and only after the binary
    ///    check has already excluded NUL-containing data.
    ///
    /// Empty input is valid text (an empty file loads as an empty document).
    static func decodeText(from data: Data) -> String? {
        if data.isEmpty { return "" }

        // 1. Explicit Unicode BOM — decode by it before the NUL heuristic runs.
        if let text = decodeBOMText(from: data) { return text }

        // 2. BOM-less data with a NUL byte is binary.
        if data.contains(0) { return nil }

        // 3. UTF-8, then 4. single-byte fallbacks.
        let encodings: [String.Encoding] = [.utf8, .windowsCP1252, .isoLatin1]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return nil
    }

    /// Decodes data that begins with a UTF-16 (LE/BE) or UTF-8 byte-order mark
    /// using that encoding, or `nil` when there is no recognized BOM. Handled
    /// separately because UTF-16 text contains NUL bytes and so must bypass the
    /// NUL-based binary check.
    private static func decodeBOMText(from data: Data) -> String? {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            // Drop the BOM bytes: unlike the .utf16 decode above, .utf8 keeps a
            // leading U+FEFF in the string, and the invisible scalar would leak
            // into the editor, detection, and sidecar text.
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        return nil
    }

    /// Infers the language from the filename extension first (reusing the CS-027
    /// reverse extension table, which also recognizes the extensionless
    /// `Dockerfile`), then falls back to weighted content detection when the
    /// extension is unknown or absent.
    static func inferLanguage(forFilename filename: String, content: String) -> Language {
        // ANSI escape codes are a definitive "terminal output" signal that overrides
        // the extension — a `.txt` or `.log` of colored output renders as a terminal.
        if ANSIParser.containsANSI(content) { return .terminal }
        if let byFilename = languageHint(forFilename: filename) {
            return byFilename
        }
        return LanguageDetector.detect(content)
    }

    /// Extracts a language hint from a known filename context. Unlike quick-capture
    /// path detection, this accepts spaces because callers pass an explicit filename
    /// (a real loaded file or `--stdin-name`), not arbitrary clipboard prose.
    private static func languageHint(forFilename filename: String) -> Language? {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lastComponent: String
        if let url = URL(string: trimmed), url.isFileURL {
            lastComponent = url.lastPathComponent
        } else {
            lastComponent = (trimmed as NSString).lastPathComponent
        }

        if lastComponent.caseInsensitiveCompare("Dockerfile") == .orderedSame {
            return .dockerfile
        }
        return LanguageDetector.language(
            forFileExtension: (lastComponent as NSString).pathExtension)
    }
}
