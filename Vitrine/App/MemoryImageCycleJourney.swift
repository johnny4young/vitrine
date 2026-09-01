import AppKit

/// Opt-in dynamic-memory journey for repeated foreground-image import and decode.
///
/// This is a development/release-QA hook, not a user feature. It deliberately re-imports
/// a deterministic sequence of PNGs through the production `BackgroundImageStore`,
/// resolves every decoded image, replaces the editor reference, and captures the live
/// window between transitions. Distinct content prevents the process-wide image cache
/// from turning later iterations into cache hits, so the loop repeatedly exercises
/// validation, hashing, decoding, observation, eviction, and SwiftUI teardown.
struct MemoryImageCycleJourney {
    struct Result: Equatable {
        let completedIterations: Int
        let uniqueReferences: Int
        let uniqueSnapshots: Int
    }

    enum JourneyError: Error, Equatable {
        case invalidIterationCount
        case fixtureEncodingFailed
        case fixtureDecodeFailed
        case snapshotCaptureFailed
        case duplicateSnapshot
    }

    static let journeyID = "image-import-cycle"
    static let completionMarker = "VITRINE_MEMORY_IMAGE_CYCLE_COMPLETE"
    // Exceed BackgroundImageStore's 32-entry decoded-image cache so the runtime
    // evidence includes deterministic count-limit eviction rather than only cache growth.
    static let defaultIterationCount = 36

    let settings: AppSettings
    let store: BackgroundImageStore
    let sleep: (Duration) async throws -> Void
    let capture: (Int) throws -> String
    let observe: (Int) async throws -> Void

    init(
        settings: AppSettings,
        store: BackgroundImageStore,
        sleep: @escaping (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        capture: @escaping (Int) throws -> String,
        observe: @escaping (Int) async throws -> Void = { _ in }
    ) {
        self.settings = settings
        self.store = store
        self.sleep = sleep
        self.capture = capture
        self.observe = observe
    }

    /// Runs the bounded image lifecycle and clears the editor reference on every exit.
    func run(iterations: Int = defaultIterationCount) async throws -> Result {
        guard iterations > 0 else { throw JourneyError.invalidIterationCount }
        var references = Set<ImageReference>()
        var snapshots = Set<String>()
        var completedIterations = 0
        defer { settings.config.foregroundImage = nil }

        for tick in 0..<iterations {
            try Task.checkCancellation()
            let data = try Self.fixturePNG(index: tick)
            let reference = try await store.importImageConcurrently(
                data: data, preferredExtension: "png")
            guard await store.preloadImage(for: reference) != nil else {
                throw JourneyError.fixtureDecodeFailed
            }
            references.insert(reference)
            settings.config.foregroundImage = reference

            // Yield long enough for observation and SwiftUI layout to publish the image
            // state before capturing the real window hierarchy.
            try await sleep(.milliseconds(250))
            guard snapshots.insert(try capture(tick)).inserted else {
                throw JourneyError.duplicateSnapshot
            }

            // Tear down the image view before every sample. The process-wide decoded
            // cache remains bounded independently, while the editor returns to code.
            settings.config.foregroundImage = nil
            try await sleep(.milliseconds(100))
            completedIterations += 1
            try await observe(completedIterations)
        }

        return Result(
            completedIterations: completedIterations,
            uniqueReferences: references.count,
            uniqueSnapshots: snapshots.count)
    }

    /// Each iteration receives a distinct, deterministic fixture so image replacement
    /// cannot be hidden by a cache hit. Drawing one fixture at a time avoids retaining
    /// the encoded fixture set for the duration of the journey.
    private static func fixturePNG(index: Int) throws -> Data {
        let width = 640
        let height = 360
        let hue = CGFloat((index * 37) % 360) / 360
        let background = NSColor(calibratedHue: hue, saturation: 0.72, brightness: 0.58, alpha: 1)
        let accent = NSColor(
            calibratedHue: (hue + 0.42).truncatingRemainder(dividingBy: 1),
            saturation: 0.58,
            brightness: 0.96,
            alpha: 1)
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0),
            let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw JourneyError.fixtureEncodingFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        background.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        accent.setFill()
        for offset in stride(from: -height + (index % 80), through: width, by: 80) {
            let stripe = NSBezierPath()
            stripe.move(to: NSPoint(x: offset, y: 0))
            stripe.line(to: NSPoint(x: offset + 44, y: 0))
            stripe.line(to: NSPoint(x: offset + height + 44, y: height))
            stripe.line(to: NSPoint(x: offset + height, y: height))
            stripe.close()
            stripe.fill()
        }
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw JourneyError.fixtureEncodingFailed
        }
        return data
    }
}
