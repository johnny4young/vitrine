import SwiftUI

/// SwiftUI presentation for `AnnotationTool` (its label and keyboard shortcut), kept in
/// the UI layer so the `AnnotationTool` model itself stays UI-free (VitrineCore
/// prerequisite). The model owns the tool's identity, kind, `systemImage` name, and
/// behavior flags; this adapter supplies only the `LocalizedStringKey`/`KeyEquivalent`
/// the toolbar needs.
extension AnnotationTool {
    var label: LocalizedStringKey {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .curvedArrow: "Curved Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .text: "Text"
        case .highlighter: "Highlighter"
        case .blur: "Blur"
        case .counter: "Counter"
        case .sticker: "Sticker"
        }
    }

    /// The shortcut digit that selects this tool, used with ⌘ (⌘1…⌘8 in toolbar order).
    /// A Command-modified shortcut is the reliable, non-hijacking choice on macOS: a
    /// modifier-less key would either not fire or steal the code editor's typing, so the
    /// tools take the digit row under ⌘ instead.
    var keyEquivalent: KeyEquivalent {
        switch self {
        case .select: "1"
        case .arrow: "2"
        case .line: "3"
        case .rectangle: "4"
        case .text: "5"
        case .highlighter: "6"
        case .blur: "7"
        case .counter: "8"
        case .sticker: "9"
        // "0" rather than renumbering: 1–9 stay exactly what users learned.
        case .curvedArrow: "0"
        }
    }
}
