import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// The golden-image regression suite (CS-025).
///
/// Each `GoldenScenario` is rendered through the production export path and
/// compared against its committed PNG fixture under a documented per-channel
/// tolerance. Because text rasterization differs across macOS/Xcode versions, the
/// strict pixel comparison runs **only on the pinned runner image** recorded in
/// `Tests/Fixtures/Golden/manifest.json`. On any other image — including the
/// default GitHub `macos-latest` runner — each scenario logs `GOLDEN SKIP` and
/// still asserts the render produced a non-nil image of the expected dimensions,
/// so the render path is exercised end to end everywhere while the byte-exact
/// guard fires only where it is meaningful.
///
/// On a strict mismatch the suite writes the freshly rendered "actual" PNG and a
/// visual diff mask into a stable directory (`vitrine-golden-diffs` under the
/// runner temp), which CI uploads as an artifact for triage.
@MainActor
@Suite("Golden image regression (CS-025)")
struct GoldenImageTests {
    // MARK: - Pin resolution

    /// The committed manifest, or `nil` if none has been recorded yet.
    static let manifest = GoldenManifest.load(from: GoldenPaths.fixturesDirectory)

    /// Whether the live runner matches the manifest's pinned image, gating the
    /// strict pixel comparison. A missing manifest means "no pin recorded", so the
    /// strict diff is skipped (render coverage still runs).
    static var isPinnedImage: Bool {
        guard let manifest else { return false }
        return manifest.pinnedImage == .current()
    }

    /// The directory diff artifacts are written to on a strict mismatch. Honors the
    /// CI runner temp (`RUNNER_TEMP`), falling back to the process temp directory
    /// locally; the path is the one the CI workflow uploads on failure.
    static let diffArtifactDirectory: URL = {
        let base =
            ProcessInfo.processInfo.environment["RUNNER_TEMP"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            } ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("vitrine-golden-diffs", isDirectory: true)
    }()

    // MARK: - Per-scenario coverage / comparison

    /// Every scenario is rendered on every runner. When the runner is the pinned
    /// image and a fixture exists, the render is pixel-diffed against it; otherwise
    /// the render is only checked for existence and expected dimensions, and a
    /// `GOLDEN SKIP` line records that the strict diff did not run here.
    @Test(arguments: GoldenScenario.allCases)
    func scenarioMatchesGoldenOrRendersCleanly(_ scenario: GoldenScenario) throws {
        let image = try #require(
            scenario.render(), "render produced no image for \(scenario.label)")
        #expect(image.width > 0 && image.height > 0)

        let goldenURL = GoldenPaths.goldenURL(for: scenario)
        let goldenExists = FileManager.default.fileExists(atPath: goldenURL.path)

        guard Self.isPinnedImage, goldenExists else {
            // Off the pin (or before a baseline exists): exercise the render only.
            // A *fixed-size* scenario (OpenGraph) renders at a contractually
            // guaranteed pixel size on any OS, so its dimensions are still asserted;
            // a content-hugging scenario's size derives from text layout, which can
            // shift across OS versions, so it is left to the strict (pinned) path.
            if let expected = scenario.expectedFixedPixelSize {
                #expect(
                    image.width == expected.width && image.height == expected.height,
                    "\(scenario.label) fixed-size render is \(image.width)x\(image.height), expected \(expected.width)x\(expected.height)"
                )
            }
            print(
                "GOLDEN SKIP \(scenario.label) "
                    + "(runner is not the pinned image or no fixture); render-only check passed")
            return
        }

        // On the pinned image with a committed fixture: strict pixel comparison.
        let golden = try #require(
            GoldenComparator.loadImage(at: goldenURL),
            "could not decode committed golden for \(scenario.label)")
        // Absorb host contention: re-render on a settled run loop until a frame
        // matches, falling back to the last frame (a genuine mismatch) if none do.
        // See `strictRenderAttempts` for why this cannot mask a real regression.
        let (settled, attempts) = Self.settledMatch(scenario, golden: golden, first: image)
        switch GoldenComparator.compare(golden, settled) {
        case .success(let result):
            print(
                "GOLDEN COMPARE \(scenario.label) "
                    + "differing=\(result.differingPixels)/\(result.pixelCount) "
                    + "maxDelta=\(result.maxChannelDelta) "
                    + "fraction=\(String(format: "%.5f", result.differingFraction)) "
                    + "attempts=\(attempts)")
            if !result.matches {
                let artifacts = Self.writeDiffArtifacts(scenario, actual: settled, golden: golden)
                Issue.record(
                    """
                    Golden mismatch for \(scenario.label) after \(attempts) settled \
                    render(s): \(result.differingPixels)/\(result.pixelCount) pixels \
                    exceeded the per-channel tolerance (max channel delta \
                    \(result.maxChannelDelta)). Diff artifacts: \(artifacts)
                    """)
            }
        case .failure(let failure):
            let artifacts = Self.writeDiffArtifacts(scenario, actual: settled, golden: golden)
            Issue.record(
                "Golden comparison failed for \(scenario.label): \(failure). Artifacts: \(artifacts)"
            )
        }
    }

    /// Writes the rendered "actual" image, the committed "golden", and a visual diff
    /// mask into the artifact directory, returning the directory path for the
    /// failure message. Best-effort: a write failure here must not mask the real
    /// assertion failure, so errors are swallowed.
    static func writeDiffArtifacts(
        _ scenario: GoldenScenario, actual: CGImage, golden: CGImage
    ) -> String {
        try? FileManager.default.createDirectory(
            at: diffArtifactDirectory, withIntermediateDirectories: true)
        if let png = ExportManager.pngData(from: actual) {
            try? png.write(
                to: diffArtifactDirectory.appendingPathComponent("\(scenario.rawValue).actual.png"))
        }
        if let png = ExportManager.pngData(from: golden) {
            try? png.write(
                to: diffArtifactDirectory.appendingPathComponent("\(scenario.rawValue).golden.png"))
        }
        if let mask = diffMask(golden: golden, actual: actual),
            let png = ExportManager.pngData(from: mask)
        {
            try? png.write(
                to: diffArtifactDirectory.appendingPathComponent("\(scenario.rawValue).diff.png"))
        }
        return diffArtifactDirectory.path
    }

    /// Builds a black image with differing pixels painted red, so a reviewer can
    /// see *where* two renders disagree at a glance. Returns `nil` if the images
    /// differ in size (no per-pixel mask is meaningful then).
    static func diffMask(golden: CGImage, actual: CGImage) -> CGImage? {
        guard golden.width == actual.width, golden.height == actual.height,
            let goldenBytes = GoldenComparator.rgba8Bytes(golden),
            let actualBytes = GoldenComparator.rgba8Bytes(actual)
        else { return nil }
        let width = golden.width
        let height = golden.height
        let tolerance = Int(GoldenComparator.channelTolerance)
        var mask = [UInt8](repeating: 0, count: width * height * 4)
        var index = 0
        while index < mask.count {
            var differs = false
            for channel in 0..<4
            where abs(Int(goldenBytes[index + channel]) - Int(actualBytes[index + channel]))
                > tolerance
            {
                differs = true
            }
            // Opaque black baseline; differing pixels flare red.
            mask[index] = differs ? 255 : 0
            mask[index + 1] = 0
            mask[index + 2] = 0
            mask[index + 3] = 255
            index += 4
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return mask.withUnsafeMutableBytes { raw -> CGImage? in
            guard
                let context = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            return context.makeImage()
        }
    }

    // MARK: - Render settling (contention resilience)

    /// How many times a strict, pinned-image render check re-renders a scenario on
    /// a settled run loop before treating a mismatch as a genuine regression.
    ///
    /// Each scenario renders identically in isolation (every diff is zero), but a
    /// full `make test` run rasterizes these scenarios while ~600 other tests share
    /// the host. Registering or unregistering a font anywhere in the suite
    /// (`CLIFontRegistrationTests`) posts an **asynchronous** Core Text
    /// fonts-changed notification; if the run loop services it while a golden
    /// scenario is rasterizing, it invalidates the glyph caches mid-render and
    /// nudges a content-hugging layout by a sub-point — a 1px height drift, or a
    /// band of anti-aliased edge pixels that tips the line-number gutter past the
    /// fraction floor. That is host contention, not a render bug.
    ///
    /// The CLI byte-identity test absorbs the exact same perturbation by draining
    /// the run loop and re-rendering once on a settled frame (see `CLITests`); this
    /// suite was simply missing that guard. `settledMatch`/`settledSize` apply the
    /// same mitigation with a few attempts: each retry first delivers any in-flight
    /// fonts-changed notification (while no render is running), then renders again
    /// against rebuilt, stable caches. The check stays strict — a real regression
    /// shifts every frame and still fails; only an environment-perturbed frame
    /// clears on a settled re-render, so this can never mask a true regression.
    static let strictRenderAttempts = 5

    /// Delivers any in-flight Core Text fonts-changed notification by briefly
    /// spinning the main run loop, so the *next* render rasterizes against stable
    /// glyph caches. Mirrors the drain `CLIFontRegistrationTests.unregisterFont` and
    /// the CLI byte-identity test use for the same reason.
    static func settleFontCaches() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    /// Re-renders `scenario` until a frame matches `golden` within tolerance,
    /// returning that frame and the attempt it landed on; if none match within
    /// `strictRenderAttempts`, returns the last frame rendered (the genuine
    /// mismatch, for the assertion and diff artifacts). `first` is the frame the
    /// caller already rendered, reused as attempt 1 so the common (clean) path
    /// renders exactly once and never spins the run loop.
    static func settledMatch(
        _ scenario: GoldenScenario, golden: CGImage, first: CGImage
    ) -> (image: CGImage, attempts: Int) {
        var candidate = first
        for attempt in 1...strictRenderAttempts {
            if case .success(let result) = GoldenComparator.compare(golden, candidate),
                result.matches
            {
                return (candidate, attempt)
            }
            // Out of attempts: surface the last (mismatching) frame as the failure.
            if attempt == strictRenderAttempts { break }
            // Deliver any in-flight fonts-changed notification now, while no render
            // is running, then render again against rebuilt, stable glyph caches.
            settleFontCaches()
            if let next = scenario.render() { candidate = next }
        }
        return (candidate, strictRenderAttempts)
    }

    /// Re-renders `scenario` until it produces the recorded `width × height`,
    /// returning that frame; if none match within `strictRenderAttempts`, returns
    /// the last frame (the genuine drift, so the assertion reports the real size).
    /// Same contention rationale as `settledMatch`.
    static func settledSize(_ scenario: GoldenScenario, width: Int, height: Int) -> CGImage? {
        var last: CGImage?
        for attempt in 1...strictRenderAttempts {
            if attempt > 1 { settleFontCaches() }
            guard let image = scenario.render() else { continue }
            last = image
            if image.width == width, image.height == height { return image }
        }
        return last
    }

    // MARK: - Manifest integrity

    @Test func manifestIsPresentAndWellFormed() throws {
        // A committed baseline must carry a parseable manifest pinning the image it
        // belongs to; without it the strict diff could never run on any runner.
        let manifest = try #require(
            Self.manifest, "Tests/Fixtures/Golden/manifest.json is missing or unparseable")
        #expect(manifest.schema == GoldenManifest.currentSchema)
        #expect(!manifest.pinnedImage.osVersion.isEmpty)
        #expect(!manifest.pinnedImage.architecture.isEmpty)
        #expect(!manifest.pinnedImage.swiftVersion.isEmpty)
    }

    @Test func manifestCoversEveryScenarioWithCurrentFingerprints() throws {
        // Every scenario must be recorded, and its recorded fingerprint must match
        // the live config. A drift here means a committed PNG no longer reflects
        // the scenario that produces it (the baseline is stale) and must be
        // re-recorded — caught from the manifest alone, independent of pixels.
        let manifest = try #require(Self.manifest)
        for scenario in GoldenScenario.allCases {
            let record = try #require(
                manifest.scenarios[scenario.rawValue],
                "manifest is missing scenario \(scenario.label); re-run make record-goldens")
            #expect(
                record.configFingerprint == scenario.configFingerprint,
                "\(scenario.label) config changed since recording; re-run make record-goldens")
            #expect(record.width > 0 && record.height > 0)
        }
    }

    @Test func configFingerprintIsStableAndDistinguishesEveryScenario() {
        // The stale-fixture guard above only works if the fingerprint actually has
        // the two properties it claims: it must be *deterministic* (same config →
        // same hash, so a re-record produces a minimal diff and the manifest check
        // is not flaky) and it must *discriminate* between distinct configs (so a
        // changed input genuinely invalidates the recorded hash). The
        // manifest-vs-live check cannot prove either: a fingerprint hard-coded to a
        // constant would satisfy it. These assertions would fail loudly for that
        // degenerate implementation.
        for scenario in GoldenScenario.allCases {
            #expect(
                scenario.configFingerprint == scenario.configFingerprint,
                "\(scenario.label) fingerprint is not stable across calls")
            // A SHA-256 hex digest is 64 characters; a truncated/empty hash would
            // mean the descriptor was not actually hashed.
            #expect(
                scenario.configFingerprint.count == 64,
                "\(scenario.label) fingerprint is not a full SHA-256 hex digest")
        }
        // The six scenarios differ on at least one pixel-affecting axis each (theme,
        // background, line-number gutter, highlight band, fixed size). Distinct
        // inputs must therefore yield distinct fingerprints — if any two collide,
        // the fingerprint is ignoring a field the recorded PNG depends on.
        let fingerprints = GoldenScenario.allCases.map(\.configFingerprint)
        #expect(
            Set(fingerprints).count == GoldenScenario.allCases.count,
            "two scenarios share a fingerprint; the hash is missing a pixel-affecting field")
    }

    @Test func manifestRoundTripsAndEncodesDeterministically() throws {
        // The recorder writes the manifest with `encoded()` and the suite reads it
        // back with `load`/`JSONDecoder`; if those two halves disagree the pin can
        // never be matched and the strict diff silently never runs. Prove the
        // contract directly: a manifest survives encode → decode unchanged, and the
        // encoding is byte-stable (sorted keys) so a re-record yields a minimal diff
        // rather than reshuffled JSON noise.
        let original = GoldenManifest(
            schema: GoldenManifest.currentSchema,
            pinnedImage: .current(),
            scenarios: [
                "beta": GoldenManifest.ScenarioRecord(
                    width: 200, height: 100, configFingerprint: "beta-hash"),
                "alpha": GoldenManifest.ScenarioRecord(
                    width: 848, height: 556, configFingerprint: "alpha-hash"),
            ])

        let encoded = try original.encoded()
        let decoded = try JSONDecoder().decode(GoldenManifest.self, from: encoded)
        #expect(decoded == original, "manifest did not survive an encode → decode round-trip")

        // Encoding the same value twice must produce identical bytes (the recorder
        // relies on this so an unchanged baseline re-records to a no-op diff).
        #expect(
            try original.encoded() == encoded, "manifest encoding is not deterministic")

        // Sorted-keys output means the scenario written second ("beta") still appears
        // after the one written first ("alpha") in the serialized text.
        let json = try #require(String(data: encoded, encoding: .utf8))
        let alphaIndex = try #require(json.range(of: "alpha"))
        let betaIndex = try #require(json.range(of: "beta"))
        #expect(
            alphaIndex.lowerBound < betaIndex.lowerBound,
            "manifest keys are not sorted; re-records would produce churny diffs")
    }

    @Test func everyScenarioHasACommittedFixture() throws {
        // The manifest and the PNGs must travel together: a recorded scenario whose
        // PNG is absent would silently downgrade to render-only on the pinned image.
        for scenario in GoldenScenario.allCases {
            let url = GoldenPaths.goldenURL(for: scenario)
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                "missing committed fixture \(scenario.fileName); re-run make record-goldens")
        }
    }

    @Test func fixedSizeScenariosRenderAtTheirGuaranteedSize() throws {
        // A fixed-size scenario (OpenGraph) must render at exactly `fixedSize ×
        // scale` on *any* runner: `ImageRenderer` honors the pinned `proposedSize`,
        // so this dimension is OS-independent and is the one golden assertion safe
        // to make everywhere. It must also agree with the recorded manifest size.
        let manifest = try #require(Self.manifest)
        for scenario in GoldenScenario.allCases {
            guard let expected = scenario.expectedFixedPixelSize else { continue }
            let image = try #require(scenario.render())
            #expect(image.width == expected.width && image.height == expected.height)
            if let record = manifest.scenarios[scenario.rawValue] {
                #expect(record.width == expected.width && record.height == expected.height)
            }
        }
    }

    @Test func recordedDimensionsMatchAFreshRenderOnThePinnedImage() throws {
        // For content-hugging scenarios the rendered size derives from text layout,
        // which can shift across OS versions — so the recorded-vs-fresh dimension
        // check only holds on the pinned image. Off the pin it is a no-op (the
        // strict pixel comparison is gated the same way and would not run either).
        guard Self.isPinnedImage else {
            print("GOLDEN SKIP recordedDimensions (runner is not the pinned image)")
            return
        }
        let manifest = try #require(Self.manifest)
        for scenario in GoldenScenario.allCases {
            guard let record = manifest.scenarios[scenario.rawValue] else { continue }
            // Settle-and-retry: a content-hugging layout can drift by ~1px under
            // host contention (a fonts-changed notification serviced mid-render);
            // re-render on a settled run loop until the recorded size reappears. A
            // real size regression never reappears and still fails (see
            // `strictRenderAttempts`).
            let image = try #require(
                Self.settledSize(scenario, width: record.width, height: record.height),
                "render produced no image for \(scenario.label)")
            #expect(
                image.width == record.width && image.height == record.height,
                "\(scenario.label) is \(image.width)x\(image.height), manifest recorded \(record.width)x\(record.height)"
            )
        }
    }

    // MARK: - Comparator math (pure, deterministic, OS-independent)

    @Test func identicalImagesMatch() throws {
        // The foundational invariant: an image compared against an exact copy of
        // itself must match with zero differing pixels, on any runner. This is also
        // what the CI comparator smoke relies on.
        let scenario = GoldenScenario.defaultTheme
        let image = try #require(scenario.render())
        let result = try Self.expectSuccess(GoldenComparator.compare(image, image))
        #expect(result.matches)
        #expect(result.differingPixels == 0)
        #expect(result.maxChannelDelta == 0)
    }

    @Test func aSinglePixelOverToleranceIsCaughtOnlyPastTheFraction() throws {
        // One channel pushed just past the tolerance must register as a differing
        // pixel and raise the max delta — but a single pixel is below the fraction
        // floor, so a lone changed pixel does not by itself fail a comparison.
        // (A real regression changes far more than one pixel.)
        let base = Self.solidImage(width: 40, height: 40, r: 100, g: 100, b: 100)
        let tweaked = Self.solidImage(width: 40, height: 40, r: 100, g: 100, b: 100)
        Self.setPixel(tweaked, x: 5, y: 5, r: 100 + GoldenComparator.channelTolerance + 1)
        let result = try Self.expectSuccess(GoldenComparator.compare(base.image, tweaked.image))
        #expect(result.differingPixels == 1)
        #expect(result.maxChannelDelta == Int(GoldenComparator.channelTolerance) + 1)
        #expect(result.matches, "one differing pixel is under the fraction floor")
    }

    @Test func subToleranceNoiseIsIgnored() throws {
        // A per-channel delta at exactly the tolerance must NOT count as a
        // difference: this is the anti-aliasing absorption the tolerance exists for.
        let base = Self.solidImage(width: 30, height: 30, r: 50, g: 50, b: 50)
        let nudged = Self.solidImage(width: 30, height: 30, r: 50, g: 50, b: 50)
        // Nudge every pixel by exactly the tolerance on the red channel.
        for y in 0..<30 {
            for x in 0..<30 {
                Self.setPixel(nudged, x: x, y: y, r: 50 + GoldenComparator.channelTolerance)
            }
        }
        let result = try Self.expectSuccess(GoldenComparator.compare(base.image, nudged.image))
        #expect(result.differingPixels == 0, "deltas at the tolerance are not differences")
        #expect(result.matches)
    }

    @Test func aLargeChangedRegionFailsTheComparison() throws {
        // The regression case: changing a big block far past the tolerance pushes
        // the differing fraction over the floor and fails the comparison — proving
        // the tolerance does not swallow a genuine visual change.
        let base = Self.solidImage(width: 50, height: 50, r: 0, g: 0, b: 0)
        let changed = Self.solidImage(width: 50, height: 50, r: 0, g: 0, b: 0)
        // Repaint the top-left quarter (25% of pixels, far over the 0.1% floor).
        for y in 0..<25 {
            for x in 0..<25 {
                Self.setPixel(changed, x: x, y: y, r: 255)
            }
        }
        let result = try Self.expectSuccess(GoldenComparator.compare(base.image, changed.image))
        #expect(!result.matches)
        #expect(result.differingFraction > GoldenComparator.pixelFractionTolerance)
    }

    @Test func differentDimensionsAreAHardFailure() throws {
        // A size change is unambiguously a regression, not a soft pixel mismatch:
        // the comparator must surface it as a typed `sizeMismatch` failure rather
        // than try to diff mismatched buffers.
        let small = Self.solidImage(width: 10, height: 10, r: 0, g: 0, b: 0)
        let large = Self.solidImage(width: 20, height: 10, r: 0, g: 0, b: 0)
        switch GoldenComparator.compare(small.image, large.image) {
        case .success:
            Issue.record("expected a sizeMismatch failure, got a pixel result")
        case .failure(let failure):
            guard case .sizeMismatch(let a, let b) = failure else {
                Issue.record("expected sizeMismatch, got \(failure)")
                return
            }
            #expect(a == CGSize(width: 10, height: 10))
            #expect(b == CGSize(width: 20, height: 10))
        }
    }

    @Test func unreadableFileIsAHardFailure() {
        // A missing file is a hard failure (not a mismatch), so a typo in a fixture
        // path surfaces loudly instead of silently grading nothing.
        let missing = GoldenPaths.fixturesDirectory.appendingPathComponent("does-not-exist.png")
        switch GoldenComparator.compareFiles(missing, missing) {
        case .success:
            Issue.record("expected an unreadable failure for a missing file")
        case .failure(let failure):
            guard case .unreadable = failure else {
                Issue.record("expected unreadable, got \(failure)")
                return
            }
        }
    }

    @Test func diffMaskHighlightsChangedPixels() throws {
        // The triage artifact must actually mark differences: a mask over two
        // images that differ in a known block paints those pixels red (channel 0
        // high) and leaves matching pixels black.
        let base = Self.solidImage(width: 16, height: 16, r: 0, g: 0, b: 0)
        let changed = Self.solidImage(width: 16, height: 16, r: 0, g: 0, b: 0)
        Self.setPixel(changed, x: 4, y: 4, r: 255)
        let mask = try #require(Self.diffMask(golden: base.image, actual: changed.image))
        let bytes = try #require(GoldenComparator.rgba8Bytes(mask))
        let changedOffset = (4 * 16 + 4) * 4
        let matchOffset = (10 * 16 + 10) * 4
        #expect(bytes[changedOffset] == 255, "changed pixel is flagged red")
        #expect(bytes[matchOffset] == 0, "matching pixel stays black")
    }

    // MARK: - Tolerance contract (keeps the standalone script in sync)

    @Test func toleranceConstantsAreTheDocumentedValues() {
        // The standalone `scripts/compare-goldens.swift` hard-codes the same two
        // constants (it cannot import the test target). Pin them here so a change to
        // the tolerance is a deliberate, reviewed edit that updates both copies —
        // not a silent divergence that would let CI and the suite disagree.
        #expect(GoldenComparator.channelTolerance == 2)
        #expect(GoldenComparator.pixelFractionTolerance == 0.001)
    }

    // MARK: - Recorder gating

    @Test func recorderIsOffByDefault() {
        // The recorder must never rewrite fixtures during a routine `make test`:
        // without the opt-in env flag it is disarmed. (CI's record step sets the
        // flag explicitly; nothing else should.)
        if ProcessInfo.processInfo.environment["VITRINE_RECORD_GOLDENS"] == nil {
            #expect(!GoldenRecording.isActive)
        }
    }

    // MARK: - Test image helpers (pure, in-memory)

    /// A mutable in-memory RGBA8 image backed by a heap buffer, used to construct
    /// exact pixel inputs for the comparator math tests without rendering.
    final class MutableImage {
        let width: Int
        let height: Int
        var bytes: [UInt8]
        init(width: Int, height: Int, bytes: [UInt8]) {
            self.width = width
            self.height = height
            self.bytes = bytes
        }
        /// A `CGImage` snapshot of the current bytes.
        var image: CGImage {
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            let context = bytes.withUnsafeMutableBytes { raw in
                CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            }
            return context.makeImage()!
        }
    }

    /// Builds a solid-color opaque test image.
    static func solidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> MutableImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var i = 0
        while i < bytes.count {
            bytes[i] = r
            bytes[i + 1] = g
            bytes[i + 2] = b
            bytes[i + 3] = 255
            i += 4
        }
        return MutableImage(width: width, height: height, bytes: bytes)
    }

    /// Overwrites a single pixel's RGB (alpha stays opaque), for crafting a known
    /// difference. Channels left `nil` keep their current value.
    static func setPixel(
        _ image: MutableImage, x: Int, y: Int, r: UInt8? = nil, g: UInt8? = nil, b: UInt8? = nil
    ) {
        let offset = (y * image.width + x) * 4
        if let r { image.bytes[offset] = r }
        if let g { image.bytes[offset + 1] = g }
        if let b { image.bytes[offset + 2] = b }
    }

    /// Unwraps a comparator success result or records a failure and rethrows.
    static func expectSuccess(
        _ result: Swift.Result<GoldenComparator.Result, GoldenComparator.Failure>
    ) throws -> GoldenComparator.Result {
        switch result {
        case .success(let value): return value
        case .failure(let failure):
            Issue.record("expected a comparison result, got failure \(failure)")
            throw failure
        }
    }
}
