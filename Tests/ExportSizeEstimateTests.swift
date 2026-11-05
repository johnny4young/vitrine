import AppKit
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

/// Stands in for a render: counts requests and can hold one open.
private final class FakeMeasure {
    var requested: [String] = []
    var failing: Set<String> = []
    var isHeld = false
    private var held: CheckedContinuation<Void, Never>?

    func callAsFunction(_ preset: ExportPreset, _: PresetSizeEstimator.Input) async -> Int? {
        requested.append(preset.id)
        if isHeld { await withCheckedContinuation { held = $0 } }
        return failing.contains(preset.id) ? nil : 100
    }

    func release() {
        isHeld = false
        held?.resume()
        held = nil
    }
}

@Suite("Export size estimates")
@MainActor
struct ExportSizeEstimateTests {
    private func config(code: String = "let answer = 42") -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = code
        return config
    }

    private func input(code: String = "let answer = 42") -> PresetSizeEstimator.Input {
        PresetSizeEstimator.Input(config: config(code: code), format: .png, profile: .sRGB)
    }

    private func estimator(_ fake: FakeMeasure) -> PresetSizeEstimator {
        PresetSizeEstimator(debounce: .zero) { await fake($0, $1) }
    }

    private func localization(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private func waitForRequests(_ count: Int, _ fake: FakeMeasure) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while fake.requested.count < count, ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    private let two: [ExportPreset] = [.twitter, .linkedIn]
    private var twoIDs: Set<String> { Set(two.map(\.id)) }

    // MARK: - Measuring

    @Test func eachPresetIsMeasuredOncePerInput() async {
        let fake = FakeMeasure()
        let estimator = estimator(fake)
        await estimator.measure(two, for: input())
        await estimator.measure(two, for: input())
        #expect(fake.requested == two.map(\.id))
        #expect(estimator.total(of: twoIDs, for: input()) == 200)

        // A subset needs no render at all.
        await estimator.measure([.twitter], for: input())
        #expect(fake.requested.count == 2)
        #expect(estimator.total(of: [ExportPreset.twitter.id], for: input()) == 100)
    }

    @Test func aPartialMeasurementHasNoTotal() async {
        let fake = FakeMeasure()
        let estimator = estimator(fake)
        await estimator.measure([.twitter], for: input())
        #expect(estimator.total(of: twoIDs, for: input()) == nil)
        #expect(estimator.total(of: [], for: input()) == nil)
    }

    @Test func aFailedPresetIsNotRetriedAndBlocksOnlyTotalsThatIncludeIt() async {
        let fake = FakeMeasure()
        fake.failing = [ExportPreset.twitter.id]
        let estimator = estimator(fake)
        await estimator.measure(two, for: input())
        await estimator.measure(two, for: input())
        #expect(fake.requested == two.map(\.id))
        #expect(estimator.total(of: twoIDs, for: input()) == nil)
        #expect(estimator.total(of: [ExportPreset.linkedIn.id], for: input()) == 100)

        // A new input may render fine, so it gets its own attempt.
        fake.failing = []
        await estimator.measure(two, for: input(code: "let other = 1"))
        #expect(fake.requested.count == 4)
    }

    @Test func aNewInputDiscardsEveryMeasurement() async {
        let fake = FakeMeasure()
        let estimator = estimator(fake)
        await estimator.measure(two, for: input())
        #expect(estimator.total(of: twoIDs, for: input(code: "let other = 1")) == nil)

        var differentFormat = input()
        differentFormat.format = .heic
        await estimator.measure(two, for: differentFormat)
        #expect(fake.requested.count == 4)
        #expect(estimator.total(of: twoIDs, for: input()) == nil)
        #expect(estimator.total(of: twoIDs, for: differentFormat) == 200)
    }

    @Test func cancellingKeepsTheResultInFlightAndMeasuresNoMore() async {
        let fake = FakeMeasure()
        fake.isHeld = true
        let estimator = estimator(fake)
        let run = Task { await estimator.measure(two, for: input()) }
        await waitForRequests(1, fake)

        run.cancel()
        fake.release()
        await run.value
        #expect(fake.requested == [ExportPreset.twitter.id])
        #expect(estimator.total(of: [ExportPreset.twitter.id], for: input()) == 100)
    }

    @Test func aResultForAnOlderInputIsDiscarded() async {
        let fake = FakeMeasure()
        fake.isHeld = true
        let estimator = estimator(fake)
        let old = Task { await estimator.measure([.twitter], for: input()) }
        await waitForRequests(1, fake)

        let newer = input(code: "let other = 1")
        let current = Task { await estimator.measure([.linkedIn], for: newer) }
        await waitForRequests(2, fake)
        fake.release()
        await old.value
        await current.value
        #expect(estimator.total(of: [ExportPreset.twitter.id], for: newer) == nil)
    }

    @Test func stoppingEndsTheLoopBeforeTheNextRender() async {
        let fake = FakeMeasure()
        fake.isHeld = true
        let estimator = estimator(fake)
        let run = Task { await estimator.measure(two, for: input()) }
        await waitForRequests(1, fake)

        estimator.stop()
        fake.release()
        await run.value
        #expect(fake.requested == [ExportPreset.twitter.id])

        // Measuring again picks up what is left.
        await estimator.measure(two, for: input())
        #expect(fake.requested == two.map(\.id))
    }

    @Test func aDocumentAboveTheLimitIsNotRendered() async {
        let fake = FakeMeasure()
        let estimator = estimator(fake)
        let line = String(repeating: "x", count: 99) + "\n"
        let limit = PresetSizeEstimator.maximumMeasuredBytes
        let large = input(code: String(repeating: line, count: limit / 100 + 1))
        await estimator.measure(two, for: large)
        #expect(fake.requested.isEmpty)
        #expect(estimator.total(of: twoIDs, for: large) == nil)

        let atLimit = input(code: String(repeating: "x", count: limit))
        await estimator.measure(two, for: atLimit)
        #expect(fake.requested.count == 2)
    }

    // MARK: - Measuring for real

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SizeEstimate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writtenSize(format: ExportFormat, in dir: URL) async throws -> Int {
        let result = await ExportManager.exportPresetSizes(
            config(), presets: [.twitter], to: dir, format: format)
        #expect(result.written == 1)
        let written = try #require(
            try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .first)
        return try Data(contentsOf: written).count
    }

    @Test(arguments: [ExportFormat.png, .heic])
    func theEstimateIsTheSizeTheExportWrites(format: ExportFormat) async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let size = try await writtenSize(format: format, in: dir)
        let estimate = await ExportManager.estimatedPresetBytes(
            config(), preset: .twitter, format: format)
        #expect(estimate == size)
    }

    /// A PDF embeds its creation time, so two renders can differ by a few bytes.
    @Test func aPDFEstimateIsCloseToTheFileTheExportWrites() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let size = try await writtenSize(format: .pdf, in: dir)
        let estimate = try #require(
            await ExportManager.estimatedPresetBytes(config(), preset: .twitter, format: .pdf))
        #expect(abs(estimate - size) <= size / 10)
    }

    // MARK: - Wording

    @Test(arguments: ["en", "es"])
    func voiceOverHearsTheSameSizeWithoutSymbols(language: String) throws {
        let bundle = try localization(language)
        let summary = ExportSizeEstimate.summary(format: .heic, bytes: 1_400_000, bundle: bundle)
        let size = Int64(1_400_000).formatted(.byteCount(style: .file))
        #expect(summary.text == "HEIC · ~\(size)")
        #expect(summary.spokenText.hasPrefix("HEIC, "))
        #expect(summary.spokenText.hasSuffix(size))
        #expect(!summary.spokenText.contains("~"))
        #expect(!summary.spokenText.contains("·"))
    }

    @Test func aSpokenEstimateIsTranslated() throws {
        let spanish = try localization("es")
        #expect(ExportSizeEstimate.spoken(1000, bundle: spanish).hasPrefix("alrededor de "))
    }

    @Test func theCarouselSummaryIsReadWithoutSymbols() throws {
        let english = try localization("en")
        let names = CarouselPaginator.plannedFilenames(slideCount: 4, in: nil)
        let spoken = CarouselPaginator.spokenOutputSummary(
            filenames: names, estimatedBytes: 1_400_000, bundle: english)
        #expect(spoken.hasPrefix("carousel-01.png to 04.png, about "))
        #expect(!spoken.contains("…"))
        #expect(!spoken.contains("~"))
        #expect(
            CarouselPaginator.spokenOutputSummary(
                filenames: ["carousel-01.png"], estimatedBytes: nil, bundle: english)
                == "carousel-01.png")
    }
}
