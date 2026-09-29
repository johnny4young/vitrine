import CoreGraphics
import Foundation
import VitrineDomain

/// Canvas-space interaction geometry shared by drawing, selecting and resizing.
/// SwiftUI scales the whole overlay with the preview; these values must not apply
/// a second zoom factor. Rendering and annotation persistence remain unchanged.
struct AnnotationInteractionGeometry {
    let annotation: Annotation
    let canvasSize: CGSize

    var start: CGPoint { annotation.startPoint(in: canvasSize) }
    var end: CGPoint { annotation.endPoint(in: canvasSize) }
    var rect: CGRect { annotation.rect(in: canvasSize) }

    enum Shape { case line, box, point }

    /// Exhaustive, so a new kind cannot silently fall back to a point-sized hit area.
    var shape: Shape {
        switch annotation.kind {
        case .arrow, .line, .curvedArrow, .measure: .line
        case .rectangle, .highlighter, .blur, .spotlight: .box
        case .text, .counter, .sticker: .point
        }
    }

    var isLineLike: Bool { shape == .line }
    var isBoxLike: Bool { shape == .box }

    var hitSize: CGSize {
        if isLineLike {
            return CGSize(
                width: max(hypot(end.x - start.x, end.y - start.y), 1),
                height: max(26, annotation.thickness + 18))
        }
        if isBoxLike {
            return CGSize(width: max(rect.width, 24), height: max(rect.height, 24))
        }
        let span = annotation.kind == .counter ? max(40, annotation.thickness * 4 + 16) : 120
        return CGSize(width: span, height: annotation.kind == .counter ? span : 44)
    }

    var hitCenter: CGPoint {
        if isLineLike { return CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2) }
        if isBoxLike { return CGPoint(x: rect.midX, y: rect.midY) }
        return start
    }

    var shaftAngle: Double { atan2(end.y - start.y, end.x - start.x) }

    var selectionRect: CGRect {
        if isBoxLike { return rect }
        return CGRect(
            x: start.x - hitSize.width / 2, y: start.y - hitSize.height / 2,
            width: hitSize.width, height: hitSize.height)
    }

    static func normalize(_ point: CGPoint, in canvasSize: CGSize) -> CGPoint {
        Annotation.clampNormalized(
            CGPoint(x: point.x / max(canvasSize.width, 1), y: point.y / max(canvasSize.height, 1)))
    }

    static func shouldCommit(kind: Annotation.Kind, from start: CGPoint, to end: CGPoint) -> Bool {
        kind.isPointPlaced || hypot(end.x - start.x, end.y - start.y) > 6
    }
}
