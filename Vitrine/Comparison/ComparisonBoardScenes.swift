import CoreGraphics
import Foundation

/// A camera over the finished board image. Zoom 1 frames the whole board and zoom 2 a
/// quarter of it; the frame keeps the board's aspect and never leaves it.
nonisolated struct ComparisonBoardViewport: Equatable, Sendable {
    static let zoomRange: ClosedRange<CGFloat> = 1...4
    static let whole = ComparisonBoardViewport()

    let zoom: CGFloat
    /// Normalized to the board, top-left origin.
    let center: CGPoint

    init(zoom: CGFloat = 1, center: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        let zoom =
            zoom.isFinite ? min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound) : 1
        let half = 0.5 / zoom
        func clamped(_ value: CGFloat) -> CGFloat {
            value.isFinite ? min(max(value, half), 1 - half) : 0.5
        }
        self.zoom = zoom
        self.center = CGPoint(x: clamped(center.x), y: clamped(center.y))
    }

    enum Axis { case zoom, horizontal, vertical }

    /// What the inspector sliders show: the zoom and the center, in percent.
    func percent(_ axis: Axis) -> Double {
        switch axis {
        case .zoom: zoom * 100
        case .horizontal: center.x * 100
        case .vertical: center.y * 100
        }
    }

    func setting(_ axis: Axis, percent: Double) -> ComparisonBoardViewport {
        let value = percent / 100
        return switch axis {
        case .zoom: ComparisonBoardViewport(zoom: value, center: center)
        case .horizontal:
            ComparisonBoardViewport(zoom: zoom, center: CGPoint(x: value, y: center.y))
        case .vertical: ComparisonBoardViewport(zoom: zoom, center: CGPoint(x: center.x, y: value))
        }
    }

    /// The framed part of the board in unit coordinates.
    var rect: CGRect {
        let side = 1 / zoom
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    /// Whole pixels of a `width` × `height` image, at least one and never outside it.
    func pixelRect(width: Int, height: Int) -> CGRect {
        guard width > 0, height > 0 else { return .zero }
        func span(_ length: Int, _ origin: CGFloat, _ size: CGFloat) -> (Int, Int) {
            let extent = min(length, max(1, Int((CGFloat(length) * size).rounded())))
            let start = min(max(0, Int((CGFloat(length) * origin).rounded())), length - extent)
            return (start, extent)
        }
        let (x, w) = span(width, rect.minX, rect.width)
        let (y, h) = span(height, rect.minY, rect.height)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// A saved view of the board with the name and time a presenter shows it for.
nonisolated struct ComparisonBoardScene: Identifiable, Equatable, Sendable {
    static let durationRange = 1...60
    static let defaultDuration = 3
    static let maximumCount = 20

    let id: UUID
    var name: String
    var seconds: Int
    let viewport: ComparisonBoardViewport
}
