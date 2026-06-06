import Foundation
import Testing

/// CS-046 — Arbitrary screen/window capture discovery.
///
/// CS-046 is a *decision* ticket, not a feature: it concluded that Vitrine must not
/// capture arbitrary windows or display regions, and ships **no** screen-capture code in
/// the app target (`docs/SCREEN-CAPTURE-DISCOVERY.md`, `docs/ROADMAP.md`). There is no
/// runtime behavior to exercise, so these tests assert the *invariant the decision
/// establishes* instead: the shipped targets pull in no capture API and request no Screen
/// Recording capability, and the decision is recorded in the docs. If anyone later wires
/// up `ScreenCaptureKit` (or a rejected legacy capture API) or adds the Screen Recording
/// entitlement without re-opening the decision, this suite fails — the same regression
/// guard `WebSnapshotPrivacyUXTests` (CS-045) provides for the parked network entitlement.
///
/// The checks read the committed source tree (anchored to this file via `#filePath`),
/// because the entitlements file and the docs are not compiled into the test bundle. No
/// SwiftUI `body` is rendered, so the suite stays clear of CoreText under the parallel
/// runner.
@Suite("Arbitrary screen capture stays parked, no capture code ships · CS-046")
struct ScreenCaptureDecisionTests {

    // MARK: - Repository anchoring

    /// The repository root, anchored to this file (`<repo>/Tests/…`), so the source- and
    /// docs-consistency checks read the committed files rather than the built bundle.
    /// Mirrors `WebSnapshotPrivacyUXTests` and `URLRendererTests`, which anchor the same
    /// way.
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    private static func file(_ components: String...) -> URL {
        components.reduce(repositoryRoot) { $0.appendingPathComponent($1) }
    }

    private static func text(_ components: String...) throws -> String {
        try String(
            contentsOf: components.reduce(repositoryRoot) { $0.appendingPathComponent($1) },
            encoding: .utf8)
    }

    /// The shipped source roots whose Swift files must contain no screen-capture API. The
    /// app and its command-line renderer are the only first-party targets that ship to
    /// users; the test target and docs are deliberately *not* scanned, because the
    /// discovery doc legitimately names these APIs in prose.
    private static let shippedSourceRoots = ["Vitrine", "VitrineCLI"]

    /// Every `.swift` file under the shipped source roots.
    private static func shippedSwiftSources() throws -> [URL] {
        let fileManager = FileManager.default
        var sources: [URL] = []
        for root in shippedSourceRoots {
            let directory = file(root)
            let enumerator = try #require(
                fileManager.enumerator(at: directory, includingPropertiesForKeys: nil),
                "Shipped source root \(root) must exist")
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                sources.append(url)
            }
        }
        #expect(!sources.isEmpty, "Expected to find shipped Swift sources to scan (CS-046)")
        return sources
    }

    // MARK: - No screen-capture API in the shipped targets

    /// The shipped targets must reference **no** screen-capture framework or symbol — not
    /// `ScreenCaptureKit` (the modern API the decision gates behind a separate approval),
    /// and none of the rejected legacy paths (`CGWindowListCreateImage`,
    /// `CGDisplayCreateImage`, `AVCaptureScreenInput`). The decision is "no capture code in
    /// the app target," so even a comment naming one of these symbols in shipped code would
    /// signal that capture work has begun; the discovery doc — which *does* discuss them —
    /// is not scanned. The match is whole-word and case-sensitive (these are exact API
    /// identifiers), and covers both `import` lines and symbol uses.
    @Test func shippedSourcesReferenceNoScreenCaptureAPI() throws {
        // Capture frameworks/symbols that must never appear in shipped code. Includes the
        // modern ScreenCaptureKit surface (parked behind the doc's checklist) and the
        // explicitly rejected legacy Quartz/AVFoundation capture APIs.
        let forbiddenSymbols = [
            "ScreenCaptureKit",
            "SCShareableContent",
            "SCScreenshotManager",
            "SCStream",
            "SCContentFilter",
            "CGWindowListCreateImage",
            "CGDisplayCreateImage",
            "AVCaptureScreenInput",
        ]
        let regexes = try forbiddenSymbols.map {
            try NSRegularExpression(pattern: #"\b\#($0)\b"#)
        }

        var offenders: [String] = []
        for url in try Self.shippedSwiftSources() {
            let source = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for (index, regex) in regexes.enumerated()
            where regex.firstMatch(in: source, range: range) != nil {
                offenders.append("\(url.lastPathComponent): \(forbiddenSymbols[index])")
            }
        }
        #expect(
            offenders.isEmpty,
            """
            CS-046 ships no screen-capture code in the app target. Found capture API \
            references in shipped sources: \(offenders.joined(separator: ", ")). If capture \
            is being revived, re-open the decision in docs/SCREEN-CAPTURE-DISCOVERY.md and \
            docs/ROADMAP.md first.
            """)
    }

    // MARK: - No Screen Recording capability in the entitlements

    /// The app must request **no** Screen Recording capability. CS-046's promise is that a
    /// shipped build "needs no Screen Recording," so the entitlements file must stay the
    /// Phase 1 set (sandbox + user-selected files) and carry no Screen Recording / screen
    /// capture entitlement key. The entitlements file is excluded from the compiled test
    /// bundle, so it is read from the source tree.
    @Test func appEntitlementsRequestNoScreenRecording() throws {
        let data = try Data(contentsOf: Self.file("Vitrine", "Resources", "Vitrine.entitlements"))
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Vitrine.entitlements must be a property list")

        // The sandbox stays on; this is the Phase 1 posture the decision preserves.
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)

        // No entitlement key may name screen recording or screen capture. macOS surfaces
        // the grant at runtime via TCC rather than a single fixed entitlement key, so this
        // matches defensively on any key mentioning recording/capture of the screen. None
        // exist today; this fails loudly if one is added.
        let screenKeys = plist.keys.filter { key in
            let lowered = key.lowercased()
            return lowered.contains("screen")
                && (lowered.contains("record") || lowered.contains("capture"))
        }
        #expect(
            screenKeys.isEmpty,
            "CS-046: the app must request no Screen Recording entitlement. Found: \(screenKeys)")
    }

    /// No `Info.plist` usage string for Screen Recording may be present anywhere in the
    /// shipped resources. A capture feature would require an `NSScreenCaptureUsageDescription`
    /// (or equivalent) usage string; its absence is part of the "no capture code ships"
    /// guarantee. Scans the committed `Info.plist` files under the shipped source roots.
    @Test func noInfoPlistDeclaresAScreenCaptureUsageString() throws {
        let fileManager = FileManager.default
        var offenders: [String] = []
        for root in Self.shippedSourceRoots {
            let directory = Self.file(root)
            guard
                let enumerator = fileManager.enumerator(
                    at: directory, includingPropertiesForKeys: nil)
            else { continue }
            for case let url as URL in enumerator where url.pathExtension == "plist" {
                let contents = try String(contentsOf: url, encoding: .utf8)
                if contents.contains("NSScreenCaptureUsageDescription") {
                    offenders.append(url.lastPathComponent)
                }
            }
        }
        #expect(
            offenders.isEmpty,
            """
            CS-046: no Info.plist may declare a Screen Recording usage string. Found \
            NSScreenCaptureUsageDescription in: \(offenders.joined(separator: ", ")).
            """)
    }

    // MARK: - The decision is recorded in the docs

    /// The discovery document exists and records the actual decision: it weighs
    /// ScreenCaptureKit against the system-screenshot handoff and the rejected legacy paths,
    /// names the required Screen Recording permission and the App Store / trust cost, and
    /// states the "park it / no code in the app target" conclusion. This is the deliverable
    /// CS-046 ships; asserting its substantive contents (not merely that the file exists)
    /// keeps the recorded decision from being silently gutted.
    @Test func discoveryDocRecordsTheParkDecisionAndItsTradeoffs() throws {
        let doc = try Self.text("docs", "SCREEN-CAPTURE-DISCOVERY.md")

        // The three options the acceptance criteria require it to compare.
        #expect(doc.contains("ScreenCaptureKit"), "Doc must evaluate ScreenCaptureKit (Option A)")
        #expect(
            doc.localizedCaseInsensitiveContains("System Screenshot handoff"),
            "Doc must evaluate the system Screenshot handoff (Option B)")
        // The rejected legacy capture paths are named as no-gos.
        #expect(doc.contains("CGWindowListCreateImage"))
        #expect(doc.contains("AVCaptureScreenInput"))

        // The required permission and its modern macOS surface name are documented.
        #expect(doc.contains("Screen Recording"))
        #expect(doc.contains("Screen & System Audio Recording"))

        // App Store risk and user-trust impact are documented.
        #expect(doc.contains("App Store"))
        #expect(doc.localizedCaseInsensitiveContains("user-trust"))

        // The decision itself: park it, and ship no capture code in the app target.
        #expect(doc.localizedCaseInsensitiveContains("Park it"))
        #expect(doc.localizedCaseInsensitiveContains("no screen-capture code"))
        #expect(doc.localizedCaseInsensitiveContains("App Sandbox"))
    }

    /// When the maintainer's local working roadmap is present, cross-check that it records
    /// CS-046 as parked with the no-code resolution. `docs/ROADMAP.md` is the **git-ignored**
    /// local backlog, so it is absent in CI and fresh clones — there the committed decision
    /// record `docs/SCREEN-CAPTURE-DISCOVERY.md` (asserted above) is the source of truth, and
    /// this cross-check is skipped rather than failing on a deliberately-uncommitted file.
    @Test func localRoadmapParksCS046WhenPresent() throws {
        let roadmapURL = Self.file("docs", "ROADMAP.md")
        guard FileManager.default.fileExists(atPath: roadmapURL.path) else { return }
        let roadmap = try String(contentsOf: roadmapURL, encoding: .utf8)
        #expect(roadmap.contains("CS-046"), "ROADMAP must contain the CS-046 entry")
        // Parked, not promoted. The status is asserted via stable text ("parked" and the
        // explicit refusal to promote) rather than the ⏸ status emoji, so a re-encoding of
        // the glyph cannot mask a real promotion of the ticket.
        #expect(
            roadmap.localizedCaseInsensitiveContains("(parked)"),
            "CS-046 must be marked parked in the ROADMAP")
        #expect(
            roadmap.localizedCaseInsensitiveContains("do not promote to Product Phase"),
            "CS-046 must explicitly decline promotion to a Product phase")
        // The no-code resolution, matched on the contiguous phrase (the ROADMAP prose
        // wraps "No" onto the previous line, so the full sentence is not on one line).
        #expect(
            roadmap.localizedCaseInsensitiveContains(
                "screen-capture code is added to the app target"),
            "ROADMAP must record that CS-046 adds no screen-capture code to the app target")
        // It points at the discovery document as the decision record.
        #expect(roadmap.contains("SCREEN-CAPTURE-DISCOVERY.md"))
    }
}
