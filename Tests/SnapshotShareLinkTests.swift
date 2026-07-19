import Foundation
import Testing

@testable import Vitrine

/// A `vitrine://open` URL that round-trips content and style, decodes untrusted input
/// defensively, and never carries a local file reference.
@Suite("Snapshot share link")
struct SnapshotShareLinkTests {
    private func sampleConfig() -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "func greet(_ name: String) -> String { \"Hi, \\(name)\" }"
        config.language = .swift
        config.theme = .dracula
        config.fontName = "Fira Code"
        config.fontSize = 18
        config.padding = 56
        config.background = .gradient(.sunset)
        config.showLineNumbers = true
        config.windowTitle = "Greeter.swift"
        config.metadata = SnapshotMetadata(
            filename: "Greeter.swift", title: "Greeting", caption: "Example",
            showLanguageBadge: true)
        config.shadowRadius = 34
        config.highlightedLineRanges = [1...1]
        config.focusHighlightedLines = true
        config.diffDecorations = true
        config.terminalColumns = 96
        config.annotations = [
            Annotation(kind: .arrow, start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.6, y: 0.5))
        ]
        return config
    }

    // MARK: - Round trip

    @Test func aSnapshotSurvivesTheFullURLRoundTrip() throws {
        let original = SharedSnapshot(capturing: sampleConfig())
        let url = try SnapshotShareLink.url(for: original)
        #expect(url.scheme == "vitrine")
        #expect(url.host == "open")

        let decoded = try SnapshotShareLink.snapshot(from: url)
        #expect(decoded == original)
    }

    @Test func applyingADecodedSnapshotReproducesTheStyledContent() throws {
        let source = sampleConfig()
        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: source))
        let decoded = try SnapshotShareLink.snapshot(from: url)

        var target = SnapshotConfig()  // a different starting point
        decoded.apply(to: &target)
        #expect(target.code == source.code)
        #expect(target.language == source.language)
        #expect(target.theme.id == source.theme.id)
        #expect(target.fontName == source.fontName)
        #expect(target.padding == source.padding)
        #expect(target.background == source.background)
        #expect(target.windowTitle == source.windowTitle)
        #expect(target.metadata == source.metadata)
        #expect(target.shadowRadius == source.shadowRadius)
        #expect(target.highlightedLineRanges == source.highlightedLineRanges)
        #expect(target.focusHighlightedLines == source.focusHighlightedLines)
        #expect(target.diffDecorations == source.diffDecorations)
        #expect(target.terminalColumns == source.terminalColumns)
        #expect(target.annotations == source.annotations)
    }

    @Test func redactedSourceNeverTravelsInTheLink() throws {
        var config = sampleConfig()
        config.code = "let visible = true\nlet apiKey = \"secret-value\"\nprint(visible)"
        config.redactedLineRanges = [2...2]

        let snapshot = SharedSnapshot(capturing: config)
        #expect(!snapshot.code.contains("secret-value"))
        #expect(snapshot.code.contains(SnapshotConfig.redactedLinePlaceholder))

        let decoded = try SnapshotShareLink.snapshot(from: SnapshotShareLink.url(for: snapshot))
        #expect(!decoded.code.contains("secret-value"))
        #expect(decoded.code.split(separator: "\n").count == 3)
    }

    // MARK: - Portability (no local file references)

    @Test func anImageBackgroundFallsBackToTheGradientNotAFileReference() throws {
        var config = sampleConfig()
        config.background = .image(
            ImageBackground(reference: ImageReference(fileName: "local.png")))
        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: config))
        let decoded = try SnapshotShareLink.snapshot(from: url)
        // The link never carries a container file path; the image degrades to a gradient.
        if case .image = decoded.style.background {
            Issue.record("a shared snapshot must not carry an image-file background")
        }
    }

    @Test func aForegroundBeautifyImageIsNotPartOfTheSharedSnapshot() throws {
        var config = sampleConfig()
        config.foregroundImage = ImageReference(fileName: "shot.png")
        // SharedSnapshot has no field for it, so a round trip simply drops it — the
        // receiver opens the code snapshot, never a dangling file reference.
        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: config))
        var target = SnapshotConfig()
        try SnapshotShareLink.snapshot(from: url).apply(to: &target)
        #expect(target.foregroundImage == nil)
    }

    // MARK: - Size bound

    @Test func anOversizedSnapshotIsRefusedRatherThanEmittingAnUnusableLink() {
        var config = SnapshotConfig()
        // High-entropy text (a well-mixed LCG mapped to 62 printable chars) so zlib
        // can't shrink it under the cap — the worst case for the size bound.
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        var scalars = [UnicodeScalar]()
        scalars.reserveCapacity(300_000)
        for _ in 0..<300_000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let value = Int((state >> 33) % 62)
            let code = value < 26 ? 65 + value : (value < 52 ? 97 + value - 26 : 48 + value - 52)
            scalars.append(UnicodeScalar(code)!)
        }
        config.code = String(String.UnicodeScalarView(scalars))
        #expect(throws: SnapshotShareLink.ShareLinkError.tooLarge) {
            try SnapshotShareLink.url(for: SharedSnapshot(capturing: config))
        }
    }

    // MARK: - Hostile / malformed input

    @Test func aNonVitrineURLIsRejected() {
        let url = URL(string: "https://example.com/open?d=abc")!
        #expect(throws: SnapshotShareLink.ShareLinkError.malformed) {
            try SnapshotShareLink.snapshot(from: url)
        }
    }

    @Test func aMissingOrEmptyPayloadIsRejected() {
        for raw in ["vitrine://open", "vitrine://open?d=", "vitrine://open?x=abc"] {
            let url = URL(string: raw)!
            #expect(throws: SnapshotShareLink.ShareLinkError.malformed) {
                try SnapshotShareLink.snapshot(from: url)
            }
        }
    }

    @Test func garbageThatIsNotBase64ZlibJSONIsRejected() {
        // Valid base64url, but not zlib; and valid-looking but not a snapshot.
        for payload in ["not-base64!!", "aGVsbG8", Base64URL.encode(Data("hello".utf8))] {
            let url = URL(string: "vitrine://open?d=\(payload)")!
            #expect(throws: SnapshotShareLink.ShareLinkError.self) {
                try SnapshotShareLink.snapshot(from: url)
            }
        }
    }

    @Test func aPayloadOverTheLengthCapIsRejectedBeforeDecoding() {
        let huge = String(repeating: "A", count: SnapshotShareLink.maxEncodedLength + 1)
        let url = URL(string: "vitrine://open?d=\(huge)")!
        #expect(throws: SnapshotShareLink.ShareLinkError.malformed) {
            try SnapshotShareLink.snapshot(from: url)
        }
    }

    @Test func aHighlyCompressibleDecodedPayloadCannotCrossTheOutputLimit() throws {
        let oversized = Data(
            String(repeating: "compressible payload\n", count: 80_000).utf8)
        let compressed = try Zlib.compress(oversized)
        #expect(compressed.count < SnapshotShareLink.maxEncodedLength)
        #expect(throws: Zlib.ZlibError.outputTooLarge) {
            try Zlib.decompress(
                compressed, maxOutputBytes: SnapshotShareLink.maxDecodedLength)
        }
    }

    @Test func aCompressibleSnapshotLargerThanTheDecodedLimitIsRefusedAtEncodeTime() {
        var config = SnapshotConfig()
        config.code = String(repeating: "let value = 0\n", count: 90_000)
        #expect(throws: SnapshotShareLink.ShareLinkError.tooLarge) {
            try SnapshotShareLink.url(for: SharedSnapshot(capturing: config))
        }
    }

    @Test func schemeAndHostAreCaseInsensitive() throws {
        let original = try SnapshotShareLink.url(for: SharedSnapshot(capturing: sampleConfig()))
        let mixedCase = URL(
            string: original.absoluteString.replacingOccurrences(
                of: "vitrine://open", with: "VITRINE://OPEN"))!
        #expect(try SnapshotShareLink.snapshot(from: mixedCase).code == sampleConfig().code)
    }

    @Test func ambiguousURLShapesAreRejected() throws {
        let valid = try SnapshotShareLink.url(for: SharedSnapshot(capturing: sampleConfig()))
        let payload = try #require(
            URLComponents(url: valid, resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
        let malformed = [
            "vitrine://open/path?d=\(payload)",
            "vitrine://user@open?d=\(payload)",
            "vitrine://open:123?d=\(payload)",
            "vitrine://open?d=\(payload)&d=\(payload)",
            "vitrine://open?d=\(payload)#fragment",
        ]
        for raw in malformed {
            #expect(throws: SnapshotShareLink.ShareLinkError.malformed) {
                try SnapshotShareLink.snapshot(from: URL(string: raw)!)
            }
        }
    }

    @Test func decodedAnnotationsAndLineRangesAreBounded() throws {
        var snapshot = SharedSnapshot(capturing: sampleConfig())
        snapshot.code = "one\ntwo\nthree"
        snapshot.annotations = [
            Annotation(
                kind: .counter, start: CGPoint(x: -20, y: 30),
                end: CGPoint(x: 40, y: -50), text: String(repeating: "x", count: 5_000),
                thickness: 1_000, number: -4)
        ]
        snapshot.highlightedLineRanges = [-20...Int.max]

        let decoded = try SnapshotShareLink.snapshot(
            from: SnapshotShareLink.url(for: snapshot))
        let annotation = try #require(decoded.annotations.first)
        #expect(annotation.start == CGPoint(x: 0, y: 1))
        #expect(annotation.end == CGPoint(x: 1, y: 0))
        #expect(annotation.text.count == 4_096)
        #expect(annotation.thickness == Annotation.thicknessRange.upperBound)
        #expect(annotation.number == 0)
        #expect(decoded.highlightedLineRanges == [1...3])
    }

    @Test func aFutureSchemaVersionIsRefusedAsUnsupported() throws {
        // Hand-build a payload whose version is one ahead of this build.
        var snapshot = SharedSnapshot(capturing: sampleConfig())
        snapshot.version = SharedSnapshot.schemaVersion + 1
        let json = try JSONEncoder().encode(snapshot)
        let encoded = Base64URL.encode(try Zlib.compress(json))
        let url = URL(string: "vitrine://open?d=\(encoded)")!
        #expect(throws: SnapshotShareLink.ShareLinkError.unsupported) {
            try SnapshotShareLink.snapshot(from: url)
        }
    }

    // MARK: - Coding helpers

    @Test func base64URLRoundTripsAndIsURLSafe() {
        let data = Data((0...255).map { UInt8($0) })
        let encoded = Base64URL.encode(data)
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
        #expect(Base64URL.decode(encoded) == data)
    }

    @Test func zlibRoundTripsAndShrinksRepetitiveText() throws {
        let text = Data(String(repeating: "let x = 0\n", count: 500).utf8)
        let compressed = try Zlib.compress(text)
        #expect(compressed.count < text.count, "repetitive code must compress")
        #expect(try Zlib.decompress(compressed, maxOutputBytes: text.count) == text)
    }
}
