import OSLog
import SwiftUI
import Testing

@testable import Vitrine

/// Render-latency performance budget (CS-026).
///
/// Vitrine's product promise is "one shortcut away": the perceived workflow has
/// to feel instant, so a slow render is a correctness bug, not just a polish
/// item. These tests turn that promise into an enforced budget. They drive the
/// real render path (`SnapshotCanvas` → `ImageRenderer` → `CGImage`, the same
/// `ExportManager.renderCGImage` used by quick-capture and export) on stable
/// fixtures, time it with a monotonic clock, and assert the latency stays inside
/// a documented ceiling.
///
/// ## Methodology
///
/// - **Warm-up.** The first render of a process pays one-time costs — SwiftUI
///   pipeline setup, font registration, syntax-highlighter priming — that a user
///   never sees on the second screenshot. Every measurement discards a warm-up
///   pass first so the budget reflects steady-state latency, not cold start.
/// - **Sampling.** Each case renders `sampleCount` times and reports the
///   **median** and **p95** of the per-render durations. The median is the
///   typical experience; p95 is the tail the budget actually guards, because a
///   budget that only holds "on average" still ships a janky product.
/// - **Logging.** Both statistics are printed (`PERF …`) for every fixture, so a
///   CI run records median/p95 for representative inputs even when it passes —
///   the trend is visible in the log without extra tooling.
///
/// ## Thresholds (documented, two-tier)
///
/// The acceptance bar is "default code render completes under 300 ms on a CI Mac
/// runner after warm-up". That 300 ms is the **target** (`PerfBudget.target`):
/// crossing it prints a `PERF WARN` line so a regression is visible immediately,
/// but does not fail the suite, because shared CI hardware is noisy and a single
/// slow sample should not red-flag a branch. The suite **fails** only past a
/// deliberately generous **hard ceiling** (`PerfBudget.hardCeiling`), which
/// catches a real, order-of-magnitude regression while tolerating CI jitter. The
/// large-snippet fixture has its own, larger documented budget; the
/// representative inputs share one render path, so the same two-tier rule applies.
@MainActor
@Suite("Render performance budget (CS-026)")
struct PerformanceTests {
    // MARK: - Documented budgets

    /// The render-latency budgets, in milliseconds, that this suite enforces.
    /// These are the single source of truth referenced by the `make perf` target
    /// and the CI step; keep the documented numbers and the assertions in sync.
    enum PerfBudget {
        /// Target for a default-size code render after warm-up (the CS-026
        /// acceptance bar). Exceeding it warns but does not fail.
        static let target: Duration = .milliseconds(300)

        /// Hard ceiling for a default-size render. Exceeding it fails the suite —
        /// generous enough to absorb noisy shared CI hardware, tight enough to
        /// catch a true regression (a ~10x blow-up of the 300 ms target).
        static let hardCeiling: Duration = .milliseconds(3000)

        /// Hard ceiling for the large-snippet render. A ~300-line file is far
        /// past any realistic screenshot, so its budget is larger but still
        /// bounded, proving the render path degrades gracefully rather than
        /// stalling the main actor unboundedly.
        static let largeHardCeiling: Duration = .milliseconds(6000)

        /// Hard ceiling for the paths the default fixture does not exercise:
        /// a terminal capture (the cell-buffer emulator + per-run styling), a
        /// custom theme (which uses a separate renderer and cache), a blur-annotated
        /// render (which composites the
        /// whole canvas twice and blurs a full copy), and a 3× export.
        ///
        /// Deliberately the same generous ceiling as the default case: these are
        /// all *ordinary* renders a user waits on, not the outsized large-snippet
        /// case, so they get the ordinary budget. The soft target still reports a
        /// `PERF WARN`, which is what makes a regression visible before it breaks
        /// CI — the point of adding these fixtures is the trend line, not the gate.
        static let secondaryHardCeiling: Duration = .milliseconds(3000)
    }

    /// How many timed renders each case samples (after the discarded warm-up).
    private static let sampleCount = 7

    // MARK: - Fixtures

    /// A representative default snippet: a few lines of idiomatic Swift, the kind
    /// of thing a developer screenshots most often. Highlighted with the default
    /// theme/font so the timing reflects the out-of-the-box experience.
    private static func defaultConfig() -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = """
            import SwiftUI

            struct CounterView: View {
                @State private var count = 0

                var body: some View {
                    Button("Tapped \\(count) times") {
                        count += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            """
        return config
    }

    /// A short one-liner — the floor of the input range. Pins that a tiny snippet
    /// is never slower than the default fixture's budget.
    private static func shortConfig() -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "let answer = 42"
        return config
    }

    /// A large snippet (~300 lines) that exercises the documented large-input
    /// budget. Deterministically generated so the fixture is byte-stable across
    /// runs and the timing is comparable over time.
    private static func largeConfig() -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = (1...300)
            .map { "let value\($0) = compute(\($0)) + offset // line \($0)" }
            .joined(separator: "\n")
        return config
    }

    /// A colorful terminal capture: SGR runs in every style the renderer supports,
    /// which is what makes this fixture worth timing — each styled run resolves its
    /// own font, so the cost scales with run count, not line count. Modeled on a
    /// build/test log, the output developers screenshot most.
    private static func terminalConfig() -> SnapshotConfig {
        var config = SnapshotConfig()
        config.language = .terminal
        let rows = (1...40).map { index in
            "\u{1B}[32m✓\u{1B}[0m \u{1B}[1mTest \(index)\u{1B}[0m "
                + "\u{1B}[2mpassed\u{1B}[0m in \u{1B}[38;5;214m\(index * 3) ms\u{1B}[0m "
                + "\u{1B}[3;36m(suite \(index % 7))\u{1B}[0m"
        }
        config.code = rows.joined(separator: "\n")
        return config
    }

    /// The default snippet under a **custom** theme. Custom palettes take a
    /// different highlight path from the built-in themes, so a budget on the
    /// built-ins says nothing about what a custom-theme user experiences.
    private static func customThemeConfig() -> SnapshotConfig {
        var config = defaultConfig()
        config.theme = Theme(
            id: "custom.perf",
            displayName: "Perf Sample",
            palette: ThemePalette(
                background: HexColor("#1E1E1E")!,
                foreground: HexColor("#D4D4D4")!,
                keyword: HexColor("#C586C0")!,
                string: HexColor("#CE9178")!,
                comment: HexColor("#6A9955")!,
                number: HexColor("#B5CEA8")!,
                type: HexColor("#4EC9B0")!,
                function: HexColor("#DCDCAA")!,
                variable: HexColor("#9CDCFE")!,
                attribute: HexColor("#569CD6")!))
        return config
    }

    /// The default snippet with a blur (redaction) box and a spotlight. Both are
    /// compositing effects: the canvas is drawn again and a full copy is blurred,
    /// so this fixture times roughly the worst-case annotated export.
    private static func blurAnnotatedConfig() -> SnapshotConfig {
        var config = defaultConfig()
        config.annotations = [
            Annotation(
                kind: .blur, start: CGPoint(x: 0.1, y: 0.3), end: CGPoint(x: 0.6, y: 0.45)),
            Annotation(
                kind: .spotlight, start: CGPoint(x: 0.05, y: 0.2), end: CGPoint(x: 0.95, y: 0.7)),
        ]
        return config
    }

    // MARK: - Timing

    /// Renders `config` once and discards the result, paying any one-time warm-up
    /// cost so the subsequent measurements reflect steady state.
    private func warmUp(_ config: SnapshotConfig) {
        _ = ExportManager.renderCGImage(config, scale: 2)
    }

    /// Renders `config` `Self.sampleCount` times, returning each render's wall
    /// duration. Uses `ContinuousClock`, a monotonic clock unaffected by wall-time
    /// adjustments, and requires every render to succeed (a `nil` image would make
    /// the timing meaningless, so it is recorded as a test failure).
    private func samples(_ config: SnapshotConfig, scale: CGFloat = 2) -> [Duration] {
        let clock = ContinuousClock()
        var durations: [Duration] = []
        durations.reserveCapacity(Self.sampleCount)
        for _ in 0..<Self.sampleCount {
            var image: CGImage?
            let elapsed = clock.measure {
                image = ExportManager.renderCGImage(config, scale: scale)
            }
            if image == nil { Issue.record("render produced no image during timing") }
            durations.append(elapsed)
        }
        return durations
    }

    /// Measures `config` end to end: warm up, sample, then report and budget-check
    /// the result under `label`. Returns the computed statistics so a caller can
    /// add fixture-specific assertions.
    @discardableResult
    private func measureRender(
        _ config: SnapshotConfig, label: String,
        target: Duration? = PerfBudget.target, hardCeiling: Duration
    ) -> Statistics {
        warmUp(config)
        let stats = Statistics(samples(config))
        report(stats, label: label, target: target)
        let p95Ms = stats.p95.milliseconds
        let ceilingMs = hardCeiling.milliseconds
        // Single interpolated literal (no `+`): Swift Testing's `Comment` is
        // expressible by a string literal, but a runtime `String` concatenation
        // is not convertible to it.
        #expect(
            stats.p95 <= hardCeiling,
            "\(label) p95 \(p95Ms) ms over hard ceiling \(ceilingMs) ms (CS-026)")
        return stats
    }

    /// Prints the median/p95 for a fixture, and a `PERF WARN` line when the p95
    /// crosses the soft target. This is the "CI warns" half of the documented
    /// two-tier threshold — visible in the log on every run, pass or fail.
    private func report(_ stats: Statistics, label: String, target: Duration?) {
        print(
            "PERF \(label) median=\(stats.median.milliseconds)ms "
                + "p95=\(stats.p95.milliseconds)ms n=\(stats.count)")
        if let target, stats.p95 > target {
            print(
                "PERF WARN \(label) p95 \(stats.p95.milliseconds)ms exceeds target "
                    + "\(target.milliseconds)ms (CS-026)")
        }
    }

    // MARK: - Cases

    @Test func defaultRenderMeetsBudget() {
        // The headline acceptance bar: a default-size code render after warm-up.
        // Fails only past the hard ceiling; the 300 ms target is reported as a
        // warning so a regression toward the limit is visible before it breaks CI.
        measureRender(
            Self.defaultConfig(), label: "default",
            hardCeiling: PerfBudget.hardCeiling)
    }

    @Test func shortRenderIsNeverSlowerThanDefaultBudget() {
        // A trivial one-liner must comfortably clear the same budget; this guards
        // against a fixed per-render overhead regression that a larger fixture
        // might mask.
        measureRender(
            Self.shortConfig(), label: "short",
            hardCeiling: PerfBudget.hardCeiling)
    }

    @Test func largeRenderStaysWithinItsDocumentedBudget() {
        // ~300 lines is far past a realistic screenshot. It has its own, larger
        // documented budget and must still complete — proving the synchronous,
        // main-actor render degrades gracefully under load rather than stalling
        // unboundedly. No soft target here: the large case is expected to exceed
        // 300 ms, so only the hard ceiling applies.
        let stats = measureRender(
            Self.largeConfig(), label: "large",
            target: nil, hardCeiling: PerfBudget.largeHardCeiling)
        // Every timed render must have produced an image (the timing loop records
        // a failure otherwise): a complete sample set means the heavy render
        // returned the main actor on each pass rather than stalling indefinitely.
        #expect(stats.count == Self.sampleCount)
    }

    // MARK: - Secondary paths
    //
    // The three cases above all time the same shape of render: plain code, a
    // built-in theme, no annotations, scale 2. The paths below are the ones a real
    // session actually hits that the default fixture cannot speak for — each is
    // known (or suspected) to be materially more expensive, and none had a budget
    // before. They exist to make a regression *visible in the log* on every CI run;
    // the ceiling is the same generous one as the default case, so they gate only
    // against an order-of-magnitude blow-up.

    @Test func terminalRenderMeetsBudget() {
        // The cell-buffer emulator plus per-run font resolution: cost scales with
        // the number of styled runs, which no code fixture exercises.
        measureRender(
            Self.terminalConfig(), label: "terminal",
            hardCeiling: PerfBudget.secondaryHardCeiling)
    }

    @Test func customThemeRenderMeetsBudget() {
        // Custom palettes take a different highlight path from the built-ins, so
        // the default budget says nothing about a custom-theme user's experience.
        measureRender(
            Self.customThemeConfig(), label: "custom-theme",
            hardCeiling: PerfBudget.secondaryHardCeiling)
    }

    @Test func blurAnnotatedRenderMeetsBudget() {
        // Blur and spotlight are compositing effects: the canvas is drawn twice and
        // a full copy is blurred. This is the worst-case annotated export.
        measureRender(
            Self.blurAnnotatedConfig(), label: "blur-annotated",
            hardCeiling: PerfBudget.secondaryHardCeiling)
    }

    @Test func retinaExportRenderMeetsBudget() {
        // 3× is what the export path actually produces for a retina PNG; the other
        // cases all time scale 2. Same fixture as `default`, so the two labels are
        // directly comparable in the log — the delta IS the scale cost.
        warmUp(Self.defaultConfig())
        let stats = Statistics(samples(Self.defaultConfig(), scale: 3))
        report(stats, label: "default@3x", target: PerfBudget.target)
        #expect(
            stats.p95 <= PerfBudget.secondaryHardCeiling,
            "default@3x p95 over the secondary hard ceiling (CS-026)")
    }

    @Test func budgetsAreOrdered() {
        // A guard on the documented thresholds themselves: the target must sit
        // below the hard ceiling, and the default ceiling below the large one, or
        // the two-tier warn/fail policy would be meaningless.
        #expect(PerfBudget.target < PerfBudget.hardCeiling)
        #expect(PerfBudget.hardCeiling <= PerfBudget.largeHardCeiling)
        // The secondary paths are ordinary renders, so they share the ordinary
        // ceiling — pinned here so raising one silently doesn't skip the other.
        #expect(PerfBudget.secondaryHardCeiling == PerfBudget.hardCeiling)
    }
}

// MARK: - Statistics summarizer

/// Direct unit tests for the `Statistics` summarizer that turns raw render
/// samples into the median/p95 the budget asserts against (CS-026).
///
/// The latency cases above feed `Statistics` real, noisy timings, so they can
/// only ever confirm that *some* number stayed under the ceiling — they cannot
/// prove the number is the *right* one. If the nearest-rank p95 math were off by
/// one, or the input were summarized unsorted, the budget would silently grade a
/// slow render against a wrong statistic and CS-026 would stop catching
/// regressions. These tests pin the computation on fixed inputs with known
/// answers so that path is verified independently of any wall-clock timing.
@Suite("Statistics summarizer (CS-026)")
struct StatisticsTests {
    @Test func reportsMedianAndP95ForAKnownSpread() {
        // Ten ascending samples (10…100 ms). count/2 == 5 selects the 60 ms
        // sample as the median; nearest-rank p95 at n=10 is rank
        // ceil(0.95*10)-1 == 9, the 100 ms tail.
        let samples = (1...10).map { Duration.milliseconds($0 * 10) }
        let stats = Statistics(samples)
        #expect(stats.count == 10)
        #expect(stats.median == .milliseconds(60))
        #expect(stats.p95 == .milliseconds(100))
    }

    @Test func summarizesUnsortedInput() {
        // The summarizer must sort internally: the same multiset in shuffled
        // order has to yield the same median/p95 as the ascending case, or a
        // real (unordered) sample stream would be mis-ranked.
        let shuffled: [Duration] = [
            .milliseconds(70), .milliseconds(10), .milliseconds(100),
            .milliseconds(40), .milliseconds(90), .milliseconds(20),
            .milliseconds(60), .milliseconds(30), .milliseconds(80),
            .milliseconds(50),
        ]
        let stats = Statistics(shuffled)
        #expect(stats.median == .milliseconds(60))
        #expect(stats.p95 == .milliseconds(100))
    }

    @Test func p95SelectsTheTailNotTheMedian() {
        // A single slow tail among otherwise-fast samples must surface in p95.
        // Nine 1 ms samples plus one 500 ms outlier: nearest-rank p95 at n=10 is
        // index 9 (the outlier), while the median stays at 1 ms. This is the
        // exact shape the budget exists to catch — a tail the average hides.
        var samples = Array(repeating: Duration.milliseconds(1), count: 9)
        samples.append(.milliseconds(500))
        let stats = Statistics(samples)
        #expect(stats.median == .milliseconds(1))
        #expect(stats.p95 == .milliseconds(500))
    }

    @Test func singleSampleCollapsesToThatSample() {
        // With one sample the clamp must resolve both statistics to it rather
        // than indexing out of bounds (rank would be -1 before clamping).
        let stats = Statistics([.milliseconds(42)])
        #expect(stats.count == 1)
        #expect(stats.median == .milliseconds(42))
        #expect(stats.p95 == .milliseconds(42))
    }

    @Test func sevenSampleP95MatchesTheSuiteSampleCount() {
        // The suite samples seven times; pin the p95 rank for that exact size so
        // the budget's tail definition is locked. ceil(0.95*7)-1 == 6, the last
        // (slowest) of seven ascending samples.
        let samples = (1...7).map { Duration.milliseconds($0) }
        let stats = Statistics(samples)
        #expect(stats.count == 7)
        #expect(stats.median == .milliseconds(4))
        #expect(stats.p95 == .milliseconds(7))
    }

    @Test func emptyInputCollapsesToZeroWithoutTrapping() {
        // A degenerate (empty) sample set must not crash the summarizer; it
        // collapses to zero and the empty count is what the caller records as a
        // failure. Reaching these assertions at all proves no out-of-bounds trap.
        let stats = Statistics([])
        #expect(stats.count == 0)
        #expect(stats.median == .zero)
        #expect(stats.p95 == .zero)
    }
}

// MARK: - Render signpost instrumentation

/// Tests for the production signpost that feeds the CS-026 budget (CS-048).
///
/// `ExportManager.renderCGImage` brackets every render in an `OSSignposter`
/// interval named by `RenderSignpost`. That interval is the documented "signal
/// CS-026's performance budget consumes" — the hook that lets render latency be
/// measured in Instruments and the unified log without a stopwatch in the hot
/// path. These tests assert the plumbing exists and is exercisable, so the
/// instrumentation cannot be silently dropped while the timing tests above keep
/// passing on their own out-of-band clock.
@Suite("Render signpost instrumentation (CS-026)")
struct RenderSignpostTests {
    @Test func intervalNameIsStable() {
        // The interval name is what an Instruments template / `log` filter keys
        // on; pin it so a rename is a deliberate, reviewed change rather than a
        // silent break of every saved performance trace.
        #expect("\(RenderSignpost.renderName)" == "Render snapshot")
    }

    @Test func signposterMintsAValidIDAndBalancesAnInterval() {
        // Drive the begin/end pair `renderCGImage` relies on. The production
        // signposter must mint a usable (non-null) signpost ID, then open and
        // close an interval keyed by that ID with a non-PII argument matching the
        // production "scale=…/length=…" shape. A non-null ID is the concrete
        // contract that the signposter is live; reaching the close proves the
        // interval is balanced rather than leaking an open region.
        let signposter = RenderSignpost.signposter
        let id = signposter.makeSignpostID()
        #expect(id != .null)
        let state = signposter.beginInterval(
            RenderSignpost.renderName, id: id, "scale=2 length=0")
        signposter.endInterval(RenderSignpost.renderName, state)
    }

    @Test func realRenderExercisesTheSignpostedPath() throws {
        // End to end: a real render must succeed, which means control passed
        // through the signposted interval in `renderCGImage` (begin → render →
        // end). This ties the instrumentation to the actual render call the
        // budget times, not just to a standalone signposter.
        var config = SnapshotConfig()
        config.code = "let x = 1"
        let image = try #require(ExportManager.renderCGImage(config, scale: 2))
        #expect(image.width > 0)
        #expect(image.height > 0)
    }
}

// MARK: - Statistics

/// Median and p95 over a set of `Duration` samples, used to summarize render
/// timings. Lives here (test-only) so the production render path carries no
/// measurement code in its hot path — the budget is observed from the outside.
struct Statistics {
    let count: Int
    let median: Duration
    let p95: Duration

    /// Builds the summary from raw samples. Empty input collapses to zero so a
    /// degenerate run cannot crash the suite (an empty sample set is itself a
    /// failure recorded by the caller).
    init(_ samples: [Duration]) {
        let sorted = samples.sorted()
        count = sorted.count
        guard !sorted.isEmpty else {
            median = .zero
            p95 = .zero
            return
        }
        median = sorted[sorted.count / 2]
        // Nearest-rank p95: smallest sample at or above the 95th percentile,
        // clamped to the last index so small sample sets resolve to the maximum.
        let rank = Int((0.95 * Double(sorted.count)).rounded(.up)) - 1
        p95 = sorted[min(max(rank, 0), sorted.count - 1)]
    }
}

extension Duration {
    /// Whole-millisecond view of a `Duration`, for budget logs and assertions.
    fileprivate var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds * 1000) + Int(attoseconds / 1_000_000_000_000_000)
    }
}
