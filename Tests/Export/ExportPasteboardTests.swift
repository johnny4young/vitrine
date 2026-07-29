import AppKit
import Foundation
import Testing

@testable import Vitrine

/// Clipboard delivery (`ExportManager+Pasteboard`).
///
/// Scoped to the plain-source copy; the multi-representation rich clipboard has its own
/// suite in `RichExportTests`. Serialized because pasteboard state is shared, and each
/// test uses a uniquely named scratch pasteboard so a parallel suite can never clobber
/// the developer's real clipboard.
@MainActor
@Suite("Export · source text clipboard", .serialized)
struct SourceTextClipboardTests {
    @Test("Copying source replaces other representations and preserves exact text")
    func copySource() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("VitrineSourceCopyTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        #expect(pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png))
        let source = "let greeting = \"¡Hola!\"\nprint(greeting)"

        #expect(ExportManager.copySourceToPasteboard(source, to: pasteboard))
        #expect(pasteboard.string(forType: .string) == source)
        #expect(pasteboard.data(forType: .png) == nil)
    }
}
