import SwiftUI
import VitrineDomain
import VitrineRendering

/// One axis of a terminal crop as `first-last`. It commits on Return or when focus leaves, so
/// typing never re-renders the capture.
struct TerminalCropField: View {
    enum Axis { case rows, columns }

    @Bindable var settings: AppSettings
    let axis: Axis
    @State private var text = ""

    private var span: ClosedRange<Int>? {
        axis == .rows ? settings.style.terminalCrop.rows : settings.style.terminalCrop.columns
    }

    var body: some View {
        TokenTextField(prompt: Text("All"), text: $text, width: 76, onEndEditing: commit)
            .onSubmit(commit)
            .help(
                axis == .rows ? Text("Rows to keep, e.g. 6-18") : Text("Columns to keep, e.g. 1-80")
            )
            .accessibilityLabel(axis == .rows ? Text("Crop rows") : Text("Crop columns"))
            .accessibilityIdentifier(
                axis == .rows ? "terminal-crop-rows-field" : "terminal-crop-columns-field"
            )
            .onAppear(perform: reseed)
            .onChange(of: span) { reseed() }
    }

    private func reseed() {
        text = span.map { LineHighlight.describe([$0]) } ?? ""
    }

    /// An empty field keeps the whole axis; anything but one span is put back.
    private func commit() {
        let parsed = LineHighlight.parse(text)
        let cleared = text.trimmingCharacters(in: .whitespaces).isEmpty
        if cleared || parsed.count == 1 {
            let crop = settings.style.terminalCrop
            settings.style.terminalCrop =
                axis == .rows
                ? TerminalCrop(rows: parsed.first, columns: crop.columns)
                : TerminalCrop(rows: crop.rows, columns: parsed.first)
        }
        reseed()
    }
}
