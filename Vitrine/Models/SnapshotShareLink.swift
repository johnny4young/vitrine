import Foundation

/// A portable, reproducible snapshot: the content, annotations, header, and style,
/// encoded into a `vitrine://open` URL so a snapshot can be shared as a link and
/// reopened as the sender styled it.
///
/// This is the *content-and-style* whole, distinct from `StyleSnapshot` (style only, for
/// reusable presets). It deliberately carries **no file references**: a beautified
/// foreground image or an image background points at this machine's container and would
/// not exist on the receiver's, so image backgrounds fall back to the gradient (via
/// `StyleSnapshot`) and a foreground image is simply not part of a shared snapshot.
///
/// Decoding treats the payload as **untrusted input**: rendering values are bounded,
/// annotations and line ranges are normalized, nothing references the filesystem, and
/// nothing executes.
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
    var metadata: SnapshotMetadata
    var shadowRadius: Double
    var highlightedLineRanges: [ClosedRange<Int>]
    var focusHighlightedLines: Bool
    var diffDecorations: Bool
    var terminalColumns: Int?

    private static let maxAnnotations = 256
    private static let maxAnnotationTextLength = 4_096
    private static let maxHighlightedRanges = 256
    private static let maxCounterNumber = 9_999

    /// Captures the shareable whole of `config`. The style half goes through
    /// `StyleSnapshot` (which drops a non-portable image background); the content half
    /// value. Redacted source lines are replaced before encoding, so a visual redaction
    /// cannot leak through the link. A foreground image is intentionally omitted — it
    /// is a local file, not shareable text.
    init(capturing config: SnapshotConfig) {
        self.version = Self.schemaVersion
        self.code = config.richClipboardText
        self.languageID = config.language.rawValue
        self.style = StyleSnapshot(capturing: config)
        self.annotations = Self.sanitizedAnnotations(config.annotations)
        self.windowTitle = config.windowTitle
        self.metadata = config.metadata
        self.shadowRadius = SettingsDefaults.clampShadowRadius(config.shadowRadius)
        self.highlightedLineRanges = Self.sanitizedLineRanges(
            config.highlightedLineRanges, lineCount: Self.lineCount(in: code))
        self.focusHighlightedLines = config.focusHighlightedLines
        self.diffDecorations = config.diffDecorations
        self.terminalColumns = config.terminalColumns.map { min(max($0, 1), 1_000) }
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
        config.metadata = metadata
        config.shadowRadius = SettingsDefaults.clampShadowRadius(shadowRadius)
        config.highlightedLineRanges = highlightedLineRanges
        config.focusHighlightedLines = focusHighlightedLines
        config.diffDecorations = diffDecorations
        config.terminalColumns = terminalColumns
    }

    private enum CodingKeys: String, CodingKey {
        case version, code, languageID, style, annotations, windowTitle, metadata
        case shadowRadius, highlightedLineRanges, focusHighlightedLines, diffDecorations
        case terminalColumns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        code = try container.decode(String.self, forKey: .code)
        languageID = try container.decode(String.self, forKey: .languageID)
        style = try container.decode(StyleSnapshot.self, forKey: .style)
        annotations = Self.sanitizedAnnotations(
            (try? container.decode([Annotation].self, forKey: .annotations)) ?? [])
        windowTitle = (try? container.decode(String.self, forKey: .windowTitle)) ?? ""
        metadata =
            (try? container.decode(SnapshotMetadata.self, forKey: .metadata))
            ?? SnapshotMetadata()
        shadowRadius = SettingsDefaults.clampShadowRadius(
            (try? container.decode(Double.self, forKey: .shadowRadius))
                ?? SnapshotConfig().shadowRadius)
        highlightedLineRanges = Self.sanitizedLineRanges(
            (try? container.decode([ClosedRange<Int>].self, forKey: .highlightedLineRanges)) ?? [],
            lineCount: Self.lineCount(in: code))
        focusHighlightedLines =
            (try? container.decode(Bool.self, forKey: .focusHighlightedLines)) ?? false
        diffDecorations =
            (try? container.decode(Bool.self, forKey: .diffDecorations)) ?? false
        terminalColumns =
            (try? container.decode(Int.self, forKey: .terminalColumns)).map {
                min(max($0, 1), 1_000)
            }
    }

    private static func sanitizedAnnotations(_ annotations: [Annotation]) -> [Annotation] {
        annotations.prefix(maxAnnotations).map { annotation in
            var sanitized = annotation
            sanitized.start = finiteNormalized(annotation.start)
            sanitized.end = finiteNormalized(annotation.end)
            sanitized.text = String(annotation.text.prefix(maxAnnotationTextLength))
            sanitized.thickness = min(
                max(
                    annotation.thickness.isFinite
                        ? annotation.thickness : Annotation.defaultThickness,
                    Annotation.thicknessRange.lowerBound),
                Annotation.thicknessRange.upperBound)
            sanitized.number = min(max(annotation.number, 0), maxCounterNumber)
            return sanitized
        }
    }

    private static func finiteNormalized(_ point: CGPoint) -> CGPoint {
        func component(_ value: Double) -> Double {
            guard value.isFinite else { return 0.5 }
            return min(max(value, 0), 1)
        }
        return CGPoint(x: component(point.x), y: component(point.y))
    }

    private static func sanitizedLineRanges(
        _ ranges: [ClosedRange<Int>], lineCount: Int
    ) -> [ClosedRange<Int>] {
        guard lineCount > 0 else { return [] }
        let bounded = ranges.prefix(maxHighlightedRanges).compactMap { range in
            let lower = min(max(range.lowerBound, 1), lineCount)
            let upper = min(max(range.upperBound, 1), lineCount)
            return min(lower, upper)...max(lower, upper)
        }
        return LineHighlight.normalize(bounded)
    }

    private static func lineCount(in code: String) -> Int {
        code.isEmpty ? 0 : code.components(separatedBy: "\n").count
    }
}

/// Encodes and decodes a `SharedSnapshot` as a `vitrine://open` URL.
///
/// The payload is JSON, zlib-compressed (a code snippet compresses well), then
/// base64url-encoded into the `d` query item — so the link is a single self-contained
/// string with no server, exactly like the rest of Vitrine. Decoding reverses each
/// step defensively and bounds both compressed input and decompressed JSON.
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
    /// The largest decoded JSON document accepted. This prevents a small compressed
    /// payload from expanding into an unexpectedly large allocation.
    static let maxDecodedLength = 1 * 1024 * 1024

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
        guard json.count <= maxDecodedLength else { throw ShareLinkError.tooLarge }
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
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == scheme,
            components.host?.lowercased() == host,
            components.user == nil, components.password == nil, components.port == nil,
            components.path.isEmpty, components.fragment == nil,
            let queryItems = components.queryItems, queryItems.count == 1,
            queryItems[0].name == payloadKey,
            let encoded = queryItems[0].value,
            !encoded.isEmpty, encoded.count <= maxEncodedLength
        else { throw ShareLinkError.malformed }

        guard let compressed = Base64URL.decode(encoded) else { throw ShareLinkError.malformed }
        let json: Data
        do {
            json = try Zlib.decompress(compressed, maxOutputBytes: maxDecodedLength)
        } catch {
            throw ShareLinkError.malformed
        }
        guard let snapshot = try? JSONDecoder().decode(SharedSnapshot.self, from: json) else {
            throw ShareLinkError.malformed
        }

        guard snapshot.version == SharedSnapshot.schemaVersion else {
            throw ShareLinkError.unsupported
        }
        return snapshot
    }
}
