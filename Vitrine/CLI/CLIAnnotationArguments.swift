import Foundation
import VitrineDomain

/// Invocation-local annotation values. Token parsing remains in `CLIArgumentParser`;
/// this value owns modifier compatibility and projection into the stable CLI options.
struct CLIAnnotationArguments {
    struct PositionedStyle {
        var x: Double?
        var y: Double?
        var color: RGBAColor?
        var size: Double?

        var isRequested: Bool { x != nil || y != nil || color != nil || size != nil }
        var hasPartialPosition: Bool { (x == nil) != (y == nil) }
        var position: CGPoint? {
            guard let x, let y else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    struct GeometryGroup {
        var points: [(start: CGPoint, end: CGPoint)] = []
        var color: RGBAColor?
        var size: Double?

        var hasStyle: Bool { color != nil || size != nil }
        var materialized: [CLIOptions.SegmentAnnotation] {
            points.map {
                CLIOptions.SegmentAnnotation(start: $0.start, end: $0.end, color: color, size: size)
            }
        }
    }

    var calloutText: String?
    var callout = PositionedStyle()
    var counterNumber: Int?
    var counter = PositionedStyle()
    var arrows = GeometryGroup()
    var lines = GeometryGroup()
    var rectangles = GeometryGroup()
    var highlighters = GeometryGroup()
    var blurBoxes = GeometryGroup()

    /// The compatibility pass has already rejected orphan modifiers before checking
    /// `--edit`, so only actual annotation content participates in its style decision.
    var hasContent: Bool {
        calloutText != nil || counterNumber != nil || !arrows.points.isEmpty
            || !lines.points.isEmpty || !rectangles.points.isEmpty
            || !highlighters.points.isEmpty || !blurBoxes.points.isEmpty
    }

    /// Keep the established kind order and exact diagnostics, even when argv contains
    /// several incompatible annotation groups in a different order.
    func validate() throws {
        if calloutText == nil, callout.isRequested {
            throw CLIError.incompatibleOptions(
                "--callout-x, --callout-y, --callout-color, and --callout-size require --callout.")
        }
        if callout.hasPartialPosition {
            throw CLIError.incompatibleOptions(
                "--callout-x and --callout-y must be provided together.")
        }
        if counterNumber == nil, counter.isRequested {
            throw CLIError.incompatibleOptions(
                "--counter-x, --counter-y, --counter-color, and --counter-size require --counter.")
        }
        if counter.hasPartialPosition {
            throw CLIError.incompatibleOptions(
                "--counter-x and --counter-y must be provided together.")
        }
        if arrows.points.isEmpty, arrows.hasStyle {
            throw CLIError.incompatibleOptions("--arrow-color and --arrow-size require --arrow.")
        }
        if lines.points.isEmpty, lines.hasStyle {
            throw CLIError.incompatibleOptions("--line-color and --line-size require --line.")
        }
        if rectangles.points.isEmpty, rectangles.hasStyle {
            throw CLIError.incompatibleOptions(
                "--rectangle-color and --rectangle-size require --rectangle.")
        }
        if highlighters.points.isEmpty, highlighters.color != nil {
            throw CLIError.incompatibleOptions("--highlighter-color requires --highlighter.")
        }
    }
}
