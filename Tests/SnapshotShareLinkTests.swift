import Foundation
import Testing

@testable import Vitrine

/// The reproducible snapshot share link (analysis §14.1): a `vitrine://open` URL that
/// round-trips content + style, decodes untrusted input defensively, and never carries
/// a local file reference.
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
        config.highlightedLineRanges = [1...1]
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
        #expect(target.highlightedLineRanges == source.highlightedLineRanges)
        #expect(target.annotations == source.annotations)
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
        #expect(try Zlib.decompress(compressed) == text)
    }
}
