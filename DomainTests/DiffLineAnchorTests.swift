import CoreGraphics
import Foundation
import Testing

@testable import VitrineDomain

@Suite("Diff line anchors")
struct DiffLineAnchorTests {
    private static let text = "@@ -1,3 +1,3 @@\n one\n-two\n+TWO\n three"

    private func comment(row: Int, side: DiffLineAnchor.Side = .new) -> Annotation {
        Annotation(
            kind: .text, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5),
            text: "why", lineAnchor: DiffLineAnchor(row: row, side: side))
    }

    private func rows(_ annotations: [Annotation]) -> [Int?] {
        annotations.map { $0.lineAnchor.flatMap { $0.isDetached ? nil : $0.row } }
    }

    @Test func aRemovedLineAnchorsToTheOldSideAndEveryOtherRowToTheNew() {
        let document = DiffDocument(source: Self.text)
        #expect(DiffLineAnchor.anchor(row: 3, in: document).side == .old)
        #expect(DiffLineAnchor.anchor(row: 4, in: document).side == .new)
        #expect(DiffLineAnchor.anchor(row: 2, in: document).side == .new)
        #expect(DiffLineAnchor.anchor(row: 99, in: document) == DiffLineAnchor(row: 99, side: .new))
    }

    @Test func editsAboveAndBelowMoveOrKeepTheLine() {
        let marks = [comment(row: 3), comment(row: 5)]
        let inserted = Self.text.replacingOccurrences(of: " one\n", with: " one\n zero\n")
        #expect(rows(DiffLineAnchor.rebasing(marks, from: Self.text, to: inserted)) == [4, 6])
        let removed = Self.text.replacingOccurrences(of: " one\n", with: "")
        #expect(rows(DiffLineAnchor.rebasing(marks, from: Self.text, to: removed)) == [2, 4])
        let appended = Self.text + "\n four"
        #expect(rows(DiffLineAnchor.rebasing(marks, from: Self.text, to: appended)) == [3, 5])
        let split = Self.text.replacingOccurrences(of: "-two", with: "-two\n")
        #expect(rows(DiffLineAnchor.rebasing(marks, from: Self.text, to: split)) == [3, 6])
    }

    @Test func anEditedOrReplacedLineDetaches() {
        let marks = [comment(row: 3), comment(row: 5)]
        let edited = Self.text.replacingOccurrences(of: "-two", with: "-tw0")
        let rebased = DiffLineAnchor.rebasing(marks, from: Self.text, to: edited)
        #expect(rebased[0].lineAnchor?.isDetached == true)
        #expect(rows(rebased) == [nil, 5])
        #expect(rows(DiffLineAnchor.rebasing(marks, from: Self.text, to: "new")) == [nil, nil])
        // Detached stays detached, even when the text comes back.
        #expect(rows(DiffLineAnchor.rebasing(rebased, from: edited, to: Self.text)) == [nil, 5])
    }

    @Test func freeMarksAndUnchangedTextAreLeftAlone() {
        let free = Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 1, y: 1))
        #expect(DiffLineAnchor.rebasing([free], from: Self.text, to: "") == [free])
        let marks = [comment(row: 3)]
        #expect(DiffLineAnchor.rebasing(marks, from: Self.text, to: Self.text) == marks)
    }

    @Test func existingAnnotationsDecodeAndEncodeUnchanged() throws {
        let legacy = Annotation(kind: .text, start: .zero, end: .zero, text: "Note")
        let data = try JSONEncoder().encode(legacy)
        #expect(String(decoding: data, as: UTF8.self).contains("lineAnchor") == false)
        let decoded = try JSONDecoder().decode(Annotation.self, from: data)
        #expect(decoded == legacy)
        #expect(decoded.lineAnchor == nil)
        #expect(!legacy.fingerprint.contains("|L"))
    }

    @Test func anchorsRoundTripAndHostileRowsDecodeDetached() throws {
        let pinned = comment(row: 7, side: .old)
        let decoded = try JSONDecoder().decode(
            Annotation.self, from: JSONEncoder().encode(pinned))
        #expect(decoded.lineAnchor == DiffLineAnchor(row: 7, side: .old))
        #expect(
            pinned.fingerprint
                != Annotation(
                    kind: .text, start: pinned.start, end: pinned.end, text: "why"
                ).fingerprint)

        for row in [0, -4, DiffLineAnchor.maximumRow + 1] {
            let json = #"{"row":\#(row),"side":"sideways"}"#
            let anchor = try JSONDecoder().decode(DiffLineAnchor.self, from: Data(json.utf8))
            #expect(anchor == DiffLineAnchor(row: 1, side: .new, isDetached: true))
        }
        let detached = DiffLineAnchor(row: 2, side: .new, isDetached: true)
        #expect(
            try JSONDecoder().decode(
                DiffLineAnchor.self, from: JSONEncoder().encode(detached)) == detached)
    }

    @Test func aDuplicateIsAFreeCallout() {
        let copy = comment(row: 3).duplicated(in: CGSize(width: 400, height: 300), counterNumber: 1)
        #expect(copy.lineAnchor == nil)
    }
}
