import Testing
import VitrineRendering

@testable import Vitrine

/// The `ExportFormat` catalog and its persistence contract.
///
/// This is the format *value type*, not the exporter: which outputs the menu offers,
/// which one is honestly labelled vector, and how a stored raw value resolves back. Kept
/// apart from the encoding suite because a change here is a change to what the app
/// advertises, while a change there is a change to the bytes it writes.
@MainActor
@Suite("Export · format catalog")
struct ExportFormatTests {
    @Test("PNG, PDF, HEIC, and AVIF are offered; PDF is the only vector option")
    func formatCasesAndVectorFlag() {
        #expect(ExportFormat.allCases == [.png, .pdf, .heic, .avif])
        #expect(ExportFormat.png.isVector == false)
        #expect(ExportFormat.pdf.isVector == true)
        #expect(ExportFormat.heic.isVector == false)
        #expect(ExportFormat.avif.isVector == false)
        // Exactly one supported vector format is advertised, and it is PDF.
        let vectors = ExportFormat.allCases.filter(\.isVector)
        #expect(vectors == [.pdf])
    }

    @Test("Interactive formats mirror the active ImageIO destination writers")
    func availableCasesMatchEncodingCapabilities() {
        #expect(ExportFormat.availableCases.contains(.png))
        #expect(ExportFormat.availableCases.contains(.pdf))
        for format in ExportFormat.allCases {
            #expect(ExportFormat.availableCases.contains(format) == format.isEncodingAvailable)
        }
    }

    @Test("Each format has a non-empty display name and summary")
    func formatLabelsArePresent() {
        for format in ExportFormat.allCases {
            #expect(!format.displayName.isEmpty)
            #expect(!format.summary.isEmpty)
        }
        #expect(ExportFormat.png.displayName == "PNG")
        #expect(ExportFormat.pdf.displayName == "PDF")
        #expect(ExportFormat.heic.displayName == "HEIC")
        #expect(ExportFormat.avif.displayName == "AVIF")
        // The vector summary names the scalable nature so the menu reads honestly.
        #expect(ExportFormat.pdf.summary.lowercased().contains("vector"))
    }

    @Test("Format round-trips through its persisted raw value")
    func formatRoundTrip() {
        for format in ExportFormat.allCases {
            #expect(ExportFormat.resolve(format.rawValue) == format)
            #expect(ExportFormat(rawValue: format.rawValue) == format)
        }
        // Raw values are the stable persistence contract; they must not
        // drift, or stored preferences would silently change format.
        #expect(ExportFormat.png.rawValue == "png")
        #expect(ExportFormat.pdf.rawValue == "pdf")
        #expect(ExportFormat.heic.rawValue == "heic")
        #expect(ExportFormat.avif.rawValue == "avif")
    }

    @Test("Unknown or missing format falls back to PNG")
    func formatFallback() {
        #expect(ExportFormat.resolve(nil) == .png)
        #expect(ExportFormat.resolve("") == .png)
        #expect(ExportFormat.resolve("svg") == .png)
        #expect(ExportFormat.fallback == .png)
        #expect(
            ExportFormat.resolveAvailable("avif")
                == (ExportFormat.avif.isEncodingAvailable ? .avif : .png))
    }
}
