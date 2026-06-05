import SwiftUI

/// A hand-authored SVG serializer for the **deterministic simple-template subset
/// only** — never the arbitrary code canvas (CS-023, Step 3).
///
/// ## Why this is scoped, not a general SVG export
///
/// The CS-023 spike confirmed that SwiftUI, `ImageRenderer`, and AppKit expose no
/// faithful full-canvas SVG path: a code snapshot's text is laid out and
/// rasterized by the text system (per-glyph kerning, ligatures, sub-pixel
/// positioning, theme attributes), and there is no public API that re-emits that
/// layout as vector glyphs. The supported vector format for the full canvas is
/// therefore **PDF** (`ExportManager.pdfData`). Shipping a `.svg` that simply
/// wrapped a raster PNG in an `<image>` element would be a fake vector file, which
/// the ticket explicitly forbids.
///
/// What *can* be expressed as honest, resolution-independent SVG is the
/// **background of a deterministic social-card / simple template** (CS-041): a
/// solid color, a built-in gradient preset, a custom gradient, or transparency.
/// Those are pure geometry and color with no text layout, so this serializer emits
/// native SVG primitives (`<rect>`, `<linearGradient>`) — real vectors, byte-for-
/// byte reproducible from the same input.
///
/// ## The exact supported subset
///
/// `background(_:size:)` accepts a `BackgroundStyle` and returns SVG **only** for
/// the cases it can represent faithfully:
///
/// - `.solid` → a filled `<rect>`.
/// - `.gradient` (built-in preset) → an `objectBoundingBox` `<linearGradient>`.
/// - `.customGradient` → an `objectBoundingBox` `<linearGradient>` with the user's
///   stops and angle.
/// - `.transparent` → a document with **no** background rectangle, so the canvas is
///   genuinely transparent (real alpha, no matte) — matching the PNG/PDF behavior.
///
/// It returns `nil` for `.image`: an image background points at a file in the app
/// container and is not a deterministic, self-contained vector, so it is out of
/// scope rather than smuggled in as an embedded raster.
///
/// ## Determinism
///
/// Colors are quantized through `RGBAColor` (fixed sRGB, four-decimal rounding) and
/// every number is formatted with a fixed precision and a stable attribute order,
/// so the same `BackgroundStyle` and `size` always serialize to identical bytes —
/// the property the simple-template export and its tests rely on.
enum VectorTemplateSVG {
    /// Serializes the **background** of a simple template to standalone SVG markup,
    /// or returns `nil` for a background kind outside the supported subset
    /// (currently only `.image`).
    ///
    /// `size` is the logical canvas size in points; SVG is unitless and scales, so
    /// the emitted `viewBox` carries the aspect and a `width`/`height` give a
    /// sensible default render size without pinning resolution.
    static func background(_ background: BackgroundStyle, size: CGSize) -> String? {
        let width = max(size.width, 1)
        let height = max(size.height, 1)

        let body: String
        switch background {
        case .solid(let color):
            body = solidRect(color, width: width, height: height)
        case .gradient(let preset):
            body = gradientMarkup(preset.asCustomGradient, width: width, height: height)
        case .customGradient(let gradient):
            body = gradientMarkup(gradient, width: width, height: height)
        case .transparent:
            // No background rectangle: the document is genuinely transparent, so a
            // viewer composites it over whatever is behind it (no matte). This is
            // the SVG analogue of the PNG/PDF transparent-background guarantee.
            body = ""
        case .image:
            // An image background is a container file, not a deterministic vector;
            // it is intentionally unsupported here rather than embedded as a raster.
            return nil
        }

        return document(width: width, height: height, body: body)
    }

    /// Whether `background` is inside the serializable simple-template subset, so a
    /// caller can decide up front whether an SVG template export is available
    /// (everything except `.image`).
    static func supports(_ background: BackgroundStyle) -> Bool {
        if case .image = background { return false }
        return true
    }

    // MARK: - Markup builders

    /// Wraps `body` in a standalone `<svg>` document with a `viewBox` that carries
    /// the aspect ratio. The XML declaration and namespace make the output a valid
    /// standalone file, not just a fragment.
    private static func document(width: CGFloat, height: CGFloat, body: String) -> String {
        let w = number(width)
        let h = number(height)
        let inner = body.isEmpty ? "" : "\n\(body)\n"
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" \
            viewBox="0 0 \(w) \(h)">\(inner)</svg>
            """
    }

    /// A single filled rectangle covering the canvas, with a separate
    /// `fill-opacity` so a translucent solid color keeps its alpha.
    private static func solidRect(_ color: Color, width: CGFloat, height: CGFloat) -> String {
        let rgba = RGBAColor(color)
        return """
              <rect x="0" y="0" width="\(number(width))" height="\(number(height))" \
            fill="\(hex(rgba))" fill-opacity="\(number(rgba.opacity))"/>
            """
    }

    /// A `<defs>` linear gradient plus a rectangle that paints it. The gradient is
    /// declared in `objectBoundingBox` units so its endpoints are independent of the
    /// canvas size, and the angle maps through the same endpoint math the live
    /// SwiftUI gradient uses, so the SVG matches the on-canvas direction.
    private static func gradientMarkup(
        _ gradient: CustomGradient, width: CGFloat, height: CGFloat
    ) -> String {
        let (start, end) = gradient.endpoints
        let stops = gradient.stops
            .sorted { $0.location < $1.location }
            .map { stop -> String in
                let rgba = RGBAColor(stop.color)
                return """
                      <stop offset="\(number(stop.location))" stop-color="\(hex(rgba))" \
                    stop-opacity="\(number(rgba.opacity))"/>
                    """
            }
            .joined(separator: "\n")

        return """
              <defs>
                <linearGradient id="bg" x1="\(number(start.x))" y1="\(number(start.y))" \
            x2="\(number(end.x))" y2="\(number(end.y))">
            \(stops)
                </linearGradient>
              </defs>
              <rect x="0" y="0" width="\(number(width))" height="\(number(height))" \
            fill="url(#bg)"/>
            """
    }

    // MARK: - Deterministic formatting

    /// The `#RRGGBB` form of an `RGBAColor`'s opaque channels. Alpha is emitted as a
    /// separate `*-opacity` attribute (broadly compatible and easier to read than an
    /// eight-digit hex), so this never includes the alpha byte.
    private static func hex(_ rgba: RGBAColor) -> String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgba.red), byte(rgba.green), byte(rgba.blue))
    }

    /// Formats a number with a fixed, trimmed precision so serialization is
    /// deterministic: up to four decimals, trailing zeros and a trailing dot
    /// removed (`2.5`, `0`, `1200`), never locale-formatted.
    private static func number(_ value: CGFloat) -> String {
        number(Double(value))
    }

    private static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        var string = String(format: "%.4f", value)
        if string.contains(".") {
            while string.hasSuffix("0") { string.removeLast() }
            if string.hasSuffix(".") { string.removeLast() }
        }
        // Normalize a possible "-0" to "0".
        return string == "-0" ? "0" : string
    }
}
