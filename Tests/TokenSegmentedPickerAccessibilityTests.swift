import Foundation
import Testing

/// A unit-test host builds no SwiftUI accessibility tree, so this pins the modifier order
/// that the step chips' UI test and VoiceOver depend on.
@Suite("Segmented picker accessibility")
struct TokenSegmentedPickerAccessibilityTests {
    /// Contained after the focus modifiers only, the first segment reports the whole track
    /// as its frame, and a click at that frame's center lands between the first two.
    @Test func theTrackIsContainedBeforeItBecomesFocusable() throws {
        let source = try String(
            contentsOf: URL(filePath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Vitrine/DesignSystem/TokenComponents.swift"),
            encoding: .utf8)
        let picker = try #require(source.range(of: "struct TokenSegmentedPicker"))
        let body = source[picker.upperBound...]
        let contained = try #require(body.range(of: ".accessibilityElement(children: .contain)"))
        let focusable = try #require(body.range(of: ".focusable(interactions: .activate)"))
        #expect(contained.lowerBound < focusable.lowerBound)
    }
}
