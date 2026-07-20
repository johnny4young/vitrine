import CoreGraphics
import Foundation
import Vision

/// Extracts text from a beautified image fully on-device via Vision's recognizer, so a
/// screenshot of code can be turned back into copyable
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
        try await recognizeLines(in: cgImage).map(\.text).joined(separator: "\n")
    }

    /// Recognizes the text in `cgImage` as regions, each with the string Vision read
    /// and its bounding box — the input to `ImageSecretRedactor` for redacting secrets
    /// in a beautified image. Boxes are in Vision's space
    /// (normalized, origin bottom-left); the redactor flips them.
    ///
    /// `@concurrent` so the CPU-bound `perform` runs off the main actor; `CGImage` is
    /// `Sendable` and the returned value type carries no Vision object across the hop.
    @concurrent
    nonisolated static func recognizeLines(
        in cgImage: CGImage
    ) async throws -> [ImageSecretRedactor.RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        return
            (request.results ?? [])
            .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
            .compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return ImageSecretRedactor.RecognizedLine(
                    text: text, boundingBox: observation.boundingBox)
            }
    }
}
