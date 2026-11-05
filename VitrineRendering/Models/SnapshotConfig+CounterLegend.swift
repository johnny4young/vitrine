import AppKit
import Foundation
import VitrineDomain

/// The legend a canvas of a given size draws, and how many entries it had to leave out.
public struct CounterLegendFit: Equatable {
    public let entries: [CounterLegend.Entry]
    public let dropped: Int
}

/// Scanning a document costs far more than a body pass, and a label keystroke or a second
/// layout doesn't change the answer, so the last document's hidden text is kept.
private enum LegendHiddenTextCache {
    struct Key: Equatable {
        let code: String
        let isTerminal: Bool
        let columns: Int?
        let redactions: [ClosedRange<Int>]
        let blurred: Bool
    }

    static var entry: (key: Key, hidden: CounterLegend.HiddenText)?
}

extension SnapshotConfig {
    /// Every legend entry, whatever the canvas. Empty until a counter has a label, so
    /// every other capture renders exactly as it did without this feature.
    public var counterLegend: [CounterLegend.Entry] {
        guard CounterLegend.hasLabels(annotations) else { return [] }
        return CounterLegend.entries(from: annotations, hiding: legendHiddenText)
    }

    /// A natural canvas grows to fit its legend. A fixed frame gives it at most a third of
    /// its height and keeps the entries that fit, from the top.
    public func counterLegendFit(in fixedSize: CGSize?) -> CounterLegendFit {
        let entries = counterLegend
        guard let fixedSize, !entries.isEmpty else {
            return CounterLegendFit(entries: entries, dropped: 0)
        }
        let kept = CounterLegendMetrics.entriesFitting(
            entries, font: counterLegendFont, frame: fixedSize)
        return CounterLegendFit(
            entries: Array(entries.prefix(kept)), dropped: entries.count - kept)
    }

    public func isLegendLabelMasked(_ annotation: Annotation) -> Bool {
        CounterLegend.isMasked(annotation.text, hiding: legendHiddenText)
    }

    var counterLegendFont: NSFont {
        CodeFont.resolved(family: fontName, size: max(11, fontSize * 0.8), ligatures: false)
    }

    /// `annotations` with masked labels, for data leaving the app: a reopened link has
    /// neither the redacted lines nor the raw label to check against.
    var annotationsWithSafeLegendLabels: [Annotation] {
        guard CounterLegend.hasLabels(annotations) else { return annotations }
        let hidden = legendHiddenText
        return annotations.map { annotation in
            guard annotation.kind == .counter else { return annotation }
            var safe = annotation
            safe.text = CounterLegend.safeLabel(annotation.text, hiding: hidden)
            return safe
        }
    }

    private var legendHiddenText: CounterLegend.HiddenText {
        let blurred = annotations.contains { $0.kind == .blur }
        let redactions = LineHighlight.normalize(redactedLineRanges)
        guard !usesImageContent, blurred || !redactions.isEmpty else { return .none }

        let key = LegendHiddenTextCache.Key(
            code: code, isTerminal: language == .terminal, columns: terminalColumns,
            redactions: redactions, blurred: blurred)
        if let entry = LegendHiddenTextCache.entry, entry.key == key { return entry.hidden }

        // Redactions address final screen rows for a terminal capture, not transcript lines.
        let source =
            key.isTerminal ? ANSIRenderer.plainText(code, columns: terminalColumns) : code
        let hidden = CounterLegend.hiddenText(
            rows: source.components(separatedBy: "\n"), redactions: redactions, blurred: blurred,
            rowsMayWrap: key.isTerminal)
        LegendHiddenTextCache.entry = (key, hidden)
        return hidden
    }
}
