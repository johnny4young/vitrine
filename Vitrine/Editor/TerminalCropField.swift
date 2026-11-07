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
    @State private var isInvalid = false

    private var span: ClosedRange<Int>? {
        axis == .rows ? settings.style.terminalCrop.rows : settings.style.terminalCrop.columns
    }

    private var isBlocked: Bool { TerminalCrop.isBlocked(by: settings.style.annotations) }

    var body: some View {
        TokenTextField(
            prompt: Text("All"), text: $text, width: 88, isInvalid: isInvalid,
            onEndEditing: commit
        )
        .onSubmit(commit)
        .disabled(isBlocked)
        .help(help)
        .accessibilityLabel(axis == .rows ? Text("Crop rows") : Text("Crop columns"))
        .accessibilityValue(isInvalid ? Text("Invalid range") : Text(verbatim: text))
        .accessibilityIdentifier(
            axis == .rows ? "terminal-crop-rows-field" : "terminal-crop-columns-field"
        )
        .onAppear(perform: reseed)
        .onChange(of: span) { reseed() }
        .onChange(of: text) { isInvalid = false }
    }

    private var help: Text {
        if isBlocked { return Text("Remove blur and spotlight boxes to crop") }
        return axis == .rows ? Text("Rows to keep, e.g. 6-18") : Text("Columns to keep, e.g. 1-80")
    }

    private func reseed() {
        text = span.map { LineHighlight.describe([$0]) } ?? ""
    }

    /// An empty field keeps the whole axis. Anything but one span stays as typed and is marked.
    private func commit() {
        let parsed = TerminalCrop.span(text)
        guard parsed != nil || text.trimmingCharacters(in: .whitespaces).isEmpty else {
            isInvalid = true
            return
        }
        let crop = settings.style.terminalCrop
        settings.style.terminalCrop =
            axis == .rows
            ? TerminalCrop(rows: parsed, columns: crop.columns)
            : TerminalCrop(rows: crop.rows, columns: parsed)
        reseed()
    }
}
