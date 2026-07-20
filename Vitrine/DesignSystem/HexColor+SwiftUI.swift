import SwiftUI

/// SwiftUI bridge for `HexColor` (the strict, primitive-based theme color), kept in the
/// UI layer so `Theme`/`ThemePalette`/`HexColor` themselves stay UI-free (VitrineCore
/// prerequisite). The model owns the sRGB components, `hexString`, and luminance; this
/// adapter reconstructs the `SwiftUI.Color` for rendering.
extension HexColor {
    /// The SwiftUI color, reconstructed in the fixed sRGB space the components were
    /// parsed in so it renders identically on any display (deterministic sizing).
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
