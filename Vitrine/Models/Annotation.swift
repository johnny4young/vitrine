import SwiftUI

/// A single annotation drawn over the code snapshot (CS-083 / CS-085): an arrow,
/// line, rectangle, text callout, highlighter, blur/redaction box, or a numbered
/// counter badge.
///
/// Coordinates are **normalized** to the canvas (`0...1` of width and height), so an
/// annotation keeps its relative position when the canvas is re-sized — the
/// content-hugging editor preview and a fixed-size export preset frame the same
/// annotation identically. `start`/`end` define an arrow/line's two ends, a box's
/// opposite corners, or (for `.text` and `.counter`) the anchor point (`start`).
struct Annotation: Identifiable, Equatable, Codable {
    /// The kind of mark. A raw string keeps the persisted JSON stable and lets a
    /// future kind be added without breaking older stores.
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case arrow
        case line
        case rectangle
        case text
        case highlighter
        case blur
        case counter
        var id: String { rawValue }

        /// Whether dragging defines two free points (a shaft/box) versus a single
        /// anchor that is clicked into place (text and counters).
        var isPointPlaced: Bool { self == .text || self == .counter }
    }

    var id: UUID
    var kind: Kind
    /// Normalized `0...1` anchor — the arrow/line tail, a box corner, or the text /
    /// counter origin.
    var start: CGPoint
    /// Normalized `0...1` second point — the arrow/line head or the box's opposite
    /// corner. Unused by `.text` and `.counter`.
    var end: CGPoint
    /// The callout text. Only `.text` uses it.
    var text: String
    /// The mark's color (stroke / fill / badge). Blur boxes ignore it.
    var color: RGBAColor
    /// The stroke/size weight in canvas points: line width for arrow/line/rectangle,
    /// font size driver for text, badge size driver for counter.
    var thickness: Double
    /// The badge number. Only `.counter` uses it.
    var number: Int

    init(
        id: UUID = UUID(), kind: Kind, start: CGPoint, end: CGPoint,
        text: String = "", color: RGBAColor = Annotation.defaultColor,
        thickness: Double = Annotation.defaultThickness, number: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.text = text
        self.color = color
        self.thickness = thickness
        self.number = number
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, start, end, text, color, thickness, number
    }

    /// Decodes tolerantly: the fields added after the first version (`thickness`,
    /// `number`, and even `text`/`color`) default when absent, so an annotation
    /// saved by an earlier build still loads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        start = try container.decode(CGPoint.self, forKey: .start)
        end = try container.decode(CGPoint.self, forKey: .end)
        text = (try? container.decode(String.self, forKey: .text)) ?? ""
        color = (try? container.decode(RGBAColor.self, forKey: .color)) ?? Annotation.defaultColor
        thickness =
            (try? container.decode(Double.self, forKey: .thickness)) ?? Annotation.defaultThickness
        number = (try? container.decode(Int.self, forKey: .number)) ?? 0
    }
}

extension Annotation {
    /// The default mark color — a vivid red that reads on light and dark code alike.
    static let defaultColor = RGBAColor(Color(hex: "#FF453A"))
    /// The default stroke/size weight, in canvas points.
    static let defaultThickness: Double = 5
    /// The supported weight range for the toolbar slider.
    static let thicknessRange: ClosedRange<Double> = 2...28

    /// Denormalizes a `0...1` point to a point in a canvas of `size`.
    static func denormalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    func startPoint(in size: CGSize) -> CGPoint { Self.denormalize(start, in: size) }
    func endPoint(in size: CGSize) -> CGPoint { Self.denormalize(end, in: size) }

    /// The rect spanned by `start`→`end` in `size` points — a box, or the bounding
    /// box of a line/arrow.
    func rect(in size: CGSize) -> CGRect {
        let a = startPoint(in: size)
        let b = endPoint(in: size)
        return CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Clamps a normalized point to `0...1` so a drag can never push an annotation
    /// off the canvas.
    static func clampNormalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }

    /// A stable, **id-independent** serialization of the annotation's visual state,
    /// for deterministic config fingerprints (golden + gallery). The random `id`
    /// never affects a pixel, so it is deliberately excluded.
    var fingerprint: String {
        func f(_ point: CGPoint) -> String { String(format: "%.3f,%.3f", point.x, point.y) }
        return [
            kind.rawValue, f(start), f(end), text, String(format: "%.2f", thickness),
            String(number),
            String(
                format: "%.3f,%.3f,%.3f,%.3f", color.red, color.green, color.blue, color.opacity),
        ].joined(separator: "|")
    }

    /// Builds a new annotation for `tool` spanning `start`→`end`, inheriting the
    /// toolbar's current `color`/`thickness`. Point-placed kinds (text/counter) use
    /// `start` as the anchor; `number` is assigned by the caller for counters.
    ///
    /// Text callouts start **empty**: the editor opens a focused inline field (with a
    /// "Note" placeholder) so the user types the content, instead of dropping a literal
    /// "Note" they then have to clear. An empty callout that is never filled is removed.
    static func make(
        kind: Kind, from start: CGPoint, to end: CGPoint, color: RGBAColor, thickness: Double,
        number: Int = 0
    ) -> Annotation {
        Annotation(
            kind: kind, start: start, end: end,
            color: color, thickness: thickness, number: number)
    }

    /// Whether this is a text callout with no visible content — an empty field the
    /// editor drops on commit rather than leaving as an invisible mark.
    var isBlankText: Bool {
        kind == .text && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A tool in the annotation toolbar (CS-085). `select` is the move/resize pointer;
/// every other case draws its matching `Annotation.Kind`.
enum AnnotationTool: String, CaseIterable, Identifiable {
    case select
    case arrow
    case line
    case rectangle
    case text
    case highlighter
    case blur
    case counter

    var id: String { rawValue }

    /// The annotation kind this tool draws, or `nil` for the select pointer.
    var kind: Annotation.Kind? {
        switch self {
        case .select: return nil
        case .arrow: return .arrow
        case .line: return .line
        case .rectangle: return .rectangle
        case .text: return .text
        case .highlighter: return .highlighter
        case .blur: return .blur
        case .counter: return .counter
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.left"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        case .highlighter: return "highlighter"
        case .blur: return "drop.fill"
        case .counter: return "1.circle.fill"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .text: return "Text"
        case .highlighter: return "Highlighter"
        case .blur: return "Blur"
        case .counter: return "Counter"
        }
    }

    /// Whether this tool exposes a thickness/size slider (the fill-only highlighter
    /// and blur do not).
    var usesThickness: Bool {
        switch self {
        case .select, .highlighter, .blur: return false
        default: return true
        }
    }

    /// Whether this tool exposes the color swatch (blur is a fill of the underlying
    /// pixels, so it has no color).
    var usesColor: Bool { self != .select && self != .blur }
}
