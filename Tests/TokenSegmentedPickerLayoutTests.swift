import AppKit
import SwiftUI
import Testing

@testable import Vitrine

@MainActor
@Suite("Segmented-picker layout")
struct TokenSegmentedPickerLayoutTests {
    private let options = ["None", "Window", "Browser", "MacBook", "iPhone"]

    private func measuredHeight(width: CGFloat) -> CGFloat {
        let picker = TokenSegmentedPicker(
            options: Array(options.enumerated()).map {
                (value: $0.offset, label: Text($0.element))
            },
            selection: .constant(0)
        )
        .frame(width: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)

        let host = NSHostingView(rootView: picker)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 200)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    /// A control that fits stays on one line; the same control in an inspector-sized
    /// slot grows vertically instead of laying its trailing options outside the column.
    @Test func huggingSegmentsWrapWhenTheirOptionsDoNotFit() {
        let oneLineHeight = measuredHeight(width: 420)
        let wrappedHeight = measuredHeight(width: 220)

        #expect(oneLineHeight > 0)
        #expect(
            wrappedHeight > oneLineHeight,
            "the narrow picker stayed \(wrappedHeight) pt tall instead of wrapping")
    }
}
