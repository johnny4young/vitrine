import Foundation

/// A portable, reproducible snapshot: the content (code, language, annotations, header)
/// plus the style, encoded into a `vitrine://open` URL so a snapshot can be shared as a
/// link and reopened exactly as the sender styled it (analysis §14.1, WOW #1).
///
/// This is the *content-and-style* whole, distinct from `StyleSnapshot` (style only, for
/// reusable presets). It deliberately carries **no file references**: a beautified
/// foreground image or an image background points at this machine's container and would
/// not exist on the receiver's, so image backgrounds fall back to the gradient (via
/// `StyleSnapshot`) and a foreground image is simply not part of a shared snapshot.
///
/// Decoding treats the payload as **untrusted input**: every field re-validates
/// (`StyleSnapshot`'s tolerant decode, `Language` id lookup, annotation coordinate
/// clamps), nothing references the filesystem, and nothing executes — so opening a
/// hostile link can only ever produce a styled code image, never reach outside the
/// render. Pure and Foundation-only so the round-trip is unit-testable.
struct SharedSnapshot: Codable, Equatable {
    /// The payload schema. Bumped only on a breaking change; an unknown version is
    /// refused rather than misread.
    static let schemaVersion = 1

    var version: Int
    var code: String
    var languageID: String
    var style: StyleSnapshot
    var annotations: [Annotation]
    var windowTitle: String
    var highlightedLineRanges: [ClosedRange<Int>]

    /// Captures the shareable whole of `config`. The style half goes through
    /// `StyleSnapshot` (which drops a non-portable image background); the content half
    /// (code, language, annotations, header title, highlighted lines) is carried by
    /// value. A foreground "beautify" image is intentionally omitted — it is a local
    /// file, not shareable text.
    init(capturing config: SnapshotConfig) {
        self.version = Self.schemaVersion
        self.code = config.code
        self.languageID = config.language.rawValue
        self.style = StyleSnapshot(capturing: config)
        self.annotations = config.annotations
        self.windowTitle = config.windowTitle
        self.highlightedLineRanges = config.highlightedLineRanges
    }

    /// Applies this shared snapshot onto `config`, replacing its content and style.
    /// Content-bound marks that this snapshot does not carry (redactions) are cleared
    /// so a stale blur can't linger over unrelated code.
    func apply(to config: inout SnapshotConfig) {
        config.clearContentMarks()
        config.code = code
        config.language = Language(rawValue: languageID) ?? .plaintext
        style.apply(to: &config)
        config.annotations = annotations
        config.windowTitle = windowTitle
        config.highlightedLineRanges = highlightedLineRanges
    }
}

/// Encodes and decodes a `SharedSnapshot` as a `vitrine://open` URL (analysis §14.1).
///
/// The payload is JSON, zlib-compressed (a code snippet compresses well), then
/// base64url-encoded into the `d` query item — so the link is a single self-contained
/// string with no server, exactly like the rest of Vitrine. Decoding reverses each
/// step defensively and is bounded by `maxEncodedLength`, so a truncated, oversized, or
/// hostile link fails cleanly rather than allocating unboundedly or crashing.
enum SnapshotShareLink {
    /// The URL scheme + host that mean "open this shared snapshot".
    static let scheme = "vitrine"
    static let host = "open"
    /// The query item carrying the base64url payload.
    static let payloadKey = "d"

    /// The largest encoded payload accepted, in characters. Comfortably fits a large
    /// snippet after compression while bounding a decode of hostile input; a snapshot
    /// past it is refused at encode time so the app never emits an unusable link.
    static let maxEncodedLength = 64 * 1024

    /// Why a share link could not be built or read.
    enum ShareLinkError: Error, Equatable {
        /// The snapshot encodes to a payload larger than `maxEncodedLength`.
        case tooLarge
        /// The URL is not a well-formed `vitrine://open?d=…` link.
        case malformed
        /// The payload decoded but is not a snapshot this build understands.
        case unsupported
    }

    /// Builds the `vitrine://open` URL for `snapshot`, or throws when the compressed
    /// payload would exceed `maxEncodedLength` (a snippet too large to share as a link).
    static func url(for snapshot: SharedSnapshot) throws -> URL {
        let json = try JSONEncoder().encode(snapshot)
        let compressed = try Zlib.compress(json)
        let encoded = Base64URL.encode(compressed)
        guard encoded.count <= maxEncodedLength else { throw ShareLinkError.tooLarge }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: payloadKey, value: encoded)]
        guard let url = components.url else { throw ShareLinkError.malformed }
        return url
    }

    /// Decodes the `SharedSnapshot` from a `vitrine://open?d=…` URL, treating the
    /// payload as untrusted: the scheme/host/query must match, the payload must be a
    /// bounded, valid base64url → zlib → JSON chain, and the schema version must be one
    /// this build understands. Any deviation throws rather than producing a partial or
    /// surprising snapshot.
    static func snapshot(from url: URL) throws -> SharedSnapshot {
        guard url.scheme == scheme, url.host == host,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let encoded = components.queryItems?.first(where: { $0.name == payloadKey })?.value,
            !encoded.isEmpty, encoded.count <= maxEncodedLength
        else { throw ShareLinkError.malformed }

        guard let compressed = Base64URL.decode(encoded),
            let json = try? Zlib.decompress(compressed),
            let snapshot = try? JSONDecoder().decode(SharedSnapshot.self, from: json)
        else { throw ShareLinkError.malformed }

        guard snapshot.version == SharedSnapshot.schemaVersion else {
            throw ShareLinkError.unsupported
        }
        return snapshot
    }
}
