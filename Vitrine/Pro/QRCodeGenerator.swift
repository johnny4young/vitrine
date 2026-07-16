import CoreImage.CIFilterBuiltins
import Foundation

/// Generates the QR chip for the Brand Kit's link (feature #28) — fully on-device via
/// Core Image's `CIQRCodeGenerator`, so nothing about the URL leaves the machine.
///
/// The raw filter output is one point per module; scaling it with anything but
/// nearest-neighbor would blur the modules into unscannability, so the generator
/// integer-scales the bitmap itself and the renderer must draw it 1:1 (no smoothing).
enum QRCodeGenerator {
    /// The rendered pixel width of the chip bitmap. 33-module QR (version 4, level M)
    /// times an integer factor lands near 165 px — crisp at the badge's display size
    /// and dense enough for a typical `https://` profile or repo URL.
    static let targetPixelWidth = 165

    /// Builds a sharp QR bitmap for `link`, or `nil` for an empty/undecodable string.
    /// Level-M error correction is the scanning-robustness sweet spot for a chip that
    /// sits on a styled image.
    static func image(for link: String) -> CGImage? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        // Integer-scale so every module stays a hard-edged square.
        let moduleWidth = output.extent.width
        guard moduleWidth > 0 else { return nil }
        let factor = max(1, (CGFloat(targetPixelWidth) / moduleWidth).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: factor, y: factor))

        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(scaled, from: scaled.extent)
    }
}
