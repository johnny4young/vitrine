import CoreGraphics
import Foundation
import Vision

/// Extracts the text from a beautified image (feature #34) — fully on-device via
/// Vision's text recognizer, so a screenshot of code can be turned back into copyable
/// text without anything leaving the machine. The natural complement to Vitrine's
/// copyable-text sidecar: code → image already travels with its source; this covers
/// the reverse, image → code.
enum ImageTextExtractor {
    /// Recognizes the text in `cgImage`, top-to-bottom in reading order, joined with
    /// newlines. Returns an empty string when the image contains no legible text.
    /// Accurate mode (not fast): a code screenshot is dense, small type where the
    /// extra pass visibly pays for itself, and the user explicitly asked.
    ///
    /// `@concurrent` so the recognition (a CPU-bound, blocking `perform`) runs off the
    /// main actor; `CGImage` is `Sendable`, so the hop is sound.
    @concurrent
    nonisolated static func recognizeText(in cgImage: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false  // code is not prose; don't "fix" tokens

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        let observations = request.results ?? []
        // Vision returns observations in an unspecified order; sort by the box's top
        // edge (normalized, origin bottom-left → higher minY is higher on screen) so
        // lines come out in reading order.
        let lines =
            observations
            .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
            .compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
