import Foundation

/// The canvas background style (CS-005 / CS-051).
///
/// ray.so / Carbon parity: the background is the single biggest lever on
/// perceived quality, so Vitrine supports a built-in **gradient preset**, a
/// **custom gradient** (stops + angle), a **solid color**, a user-chosen
/// **image** (fit/blur/dimming), and real **transparency**.
///
/// Every case is value-typed and `Codable` so a background round-trips through
/// presets (CS-030) and persisted preferences (CS-050). The preset gradient and
/// custom gradient are deliberately *separate* cases rather than one parameter:
/// it keeps `.gradient(.aurora)` — the value used everywhere as the signature
/// default — unchanged, and lets a preset gradient persist by name (stable across
/// palette tweaks) while a custom gradient persists by value.
///
/// The transparent case is load-bearing for color management (CS-024): it must
/// export with a real alpha channel and never composite the canvas over an
/// opaque matte (see `BackgroundView`).
enum BackgroundStyle {
    case solid(RGBAColor)
    case gradient(GradientPreset)
    case customGradient(CustomGradient)
    case image(ImageBackground)
    case transparent

    /// A short, non-PII label for the background kind, used by diagnostics
    /// (CS-048). A solid color reports only `"solid"`, not its RGBA, and an image
    /// reports only `"image"`, never the file name or path — so nothing
    /// user-specific leaks. A gradient reports its preset name; a custom gradient
    /// reports only `"custom-gradient"`.
    var diagnosticsKind: String {
        switch self {
        case .solid: "solid"
        case .gradient(let preset): "gradient(\(preset.rawValue))"
        case .customGradient: "custom-gradient"
        case .image: "image"
        case .transparent: "transparent"
        }
    }
}

// MARK: - Value equality

/// Equality and hashing are **value-based on fixed-sRGB color components**.
///
/// Solid colors are stored as `RGBAColor` (quantized fixed-sRGB), so a background
/// compares equal to its own persistence round-trip — the behavior presets (CS-030)
/// and the "diverged from preset" check (CS-020) rely on. (A raw `SwiftUI.Color` would
/// not: a named `.red`, a `Color(hex:)`, and a restored color can differ underneath.)
extension BackgroundStyle: Equatable, Hashable {
    static func == (lhs: BackgroundStyle, rhs: BackgroundStyle) -> Bool {
        switch (lhs, rhs) {
        case (.solid(let a), .solid(let b)): a == b
        case (.gradient(let a), .gradient(let b)): a == b
        case (.customGradient(let a), .customGradient(let b)): a == b
        case (.image(let a), .image(let b)): a == b
        case (.transparent, .transparent): true
        default: false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .solid(let color):
            hasher.combine(0)
            hasher.combine(color)
        case .gradient(let preset):
            hasher.combine(1)
            hasher.combine(preset)
        case .customGradient(let gradient):
            hasher.combine(2)
            hasher.combine(gradient)
        case .image(let image):
            hasher.combine(3)
            hasher.combine(image)
        case .transparent:
            hasher.combine(4)
        }
    }
}

// MARK: - Codable

extension BackgroundStyle: Codable {
    /// On-disk discriminator for the background kind. Stored as a stable string so
    /// the persisted shape is human-readable and resilient to case reordering.
    private enum Kind: String, Codable {
        case solid, gradient, customGradient, image, transparent
    }

    private enum CodingKeys: String, CodingKey {
        case kind, color, preset, customGradient, image
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .solid(let color):
            try container.encode(Kind.solid, forKey: .kind)
            try container.encode(color, forKey: .color)
        case .gradient(let preset):
            try container.encode(Kind.gradient, forKey: .kind)
            try container.encode(preset.rawValue, forKey: .preset)
        case .customGradient(let gradient):
            try container.encode(Kind.customGradient, forKey: .kind)
            try container.encode(gradient, forKey: .customGradient)
        case .image(let image):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(image, forKey: .image)
        case .transparent:
            try container.encode(Kind.transparent, forKey: .kind)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .solid:
            self = .solid(try container.decode(RGBAColor.self, forKey: .color))
        case .gradient:
            // An unknown preset name degrades to the signature default rather than
            // failing the whole decode (CS-050 documented fallback).
            let raw = try container.decode(String.self, forKey: .preset)
            self = .gradient(GradientPreset(rawValue: raw) ?? .aurora)
        case .customGradient:
            self = .customGradient(
                try container.decode(CustomGradient.self, forKey: .customGradient))
        case .image:
            self = .image(try container.decode(ImageBackground.self, forKey: .image))
        case .transparent:
            self = .transparent
        }
    }
}

// MARK: - Gradient presets

/// Built-in gradient presets used as canvas backgrounds.
///
/// `aurora` is Vitrine's signature preset: it uses the same violet→azure brand
/// vocabulary as the app accent and chrome (`Brand.Palette`), so a rendered
/// screenshot is recognizably "Vitrine" (CS-036).
enum GradientPreset: String, CaseIterable, Identifiable, Codable {
    case aurora = "Aurora"
    case ocean = "Ocean"
    case sunset = "Sunset"
    case forest = "Forest"
    case night = "Night"
    case carbon = "Carbon"

    var id: String { rawValue }

    /// Stop colors (top-leading → bottom-trailing) as fixed-sRGB `RGBAColor`, so the
    /// preset vocabulary is UI-free; the UI layer's `colors`/`gradient` bridge these to
    /// `SwiftUI.Color`/`LinearGradient`. `aurora` uses the brand accent/secondary hex so
    /// it stays in lockstep with `Brand.Palette` without a UI dependency here.
    var stopColors: [RGBAColor] {
        func rgba(_ hex: String) -> RGBAColor { RGBAColor(hex: hex) ?? .fallbackBlack }
        switch self {
        case .aurora: return [rgba("#4F46E5"), rgba("#06B6D4")]  // brand accent → secondary
        case .ocean: return [rgba("#2E3192"), rgba("#1BFFFF")]
        case .sunset: return [rgba("#FF512F"), rgba("#F09819")]
        case .forest: return [rgba("#11998E"), rgba("#38EF7D")]
        case .night: return [rgba("#0F2027"), rgba("#2C5364")]
        case .carbon: return [rgba("#1F1C2C"), rgba("#928DAB")]
        }
    }

    /// The equivalent editable custom gradient, used to seed the custom-gradient
    /// editor from a preset so "tweak this preset" is a one-tap starting point
    /// (CS-051). Stops are spread evenly; the angle matches the preset's
    /// top-leading → bottom-trailing diagonal.
    var asCustomGradient: CustomGradient {
        let colors = stopColors
        let stops: [GradientStop]
        switch colors.count {
        case 0: stops = CustomGradient.default.stops
        case 1: stops = [GradientStop(color: colors[0], location: 0)]
        default:
            let last = Double(colors.count - 1)
            stops = colors.enumerated().map { index, color in
                GradientStop(color: color, location: Double(index) / last)
            }
        }
        return CustomGradient(stops: stops, angle: 135)
    }
}

// MARK: - Custom gradient (CS-051)

/// One color stop in a custom gradient: a color at a normalized location
/// (`0...1`) along the gradient axis.
///
/// `id` is identity for SwiftUI's `ForEach` only; it is regenerated on decode and
/// is deliberately **excluded** from equality/hashing, which compare by the
/// stop's *value* — color (via fixed-sRGB `RGBAColor`) and location — so a stop
/// equals its own persistence round-trip.
struct GradientStop: Codable, Identifiable {
    let id: UUID
    /// The stop color, stored as a fixed-sRGB `RGBAColor` so it is UI-free and survives
    /// a persistence round-trip; the UI reads `color.color` to render.
    var color: RGBAColor
    /// Normalized position along the gradient, `0` (start) … `1` (end).
    var location: Double

    init(id: UUID = UUID(), color: RGBAColor, location: Double) {
        self.id = id
        self.color = color
        self.location = min(max(location, 0), 1)
    }

    // MARK: Codable — `id` is regenerated on decode

    private enum CodingKeys: String, CodingKey { case color, location }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.color = try container.decode(RGBAColor.self, forKey: .color)
        self.location = min(max(try container.decode(Double.self, forKey: .location), 0), 1)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(location, forKey: .location)
    }
}

extension GradientStop: Equatable, Hashable {
    /// Value equality on color + location only (not the `ForEach` identity).
    static func == (lhs: GradientStop, rhs: GradientStop) -> Bool {
        lhs.color == rhs.color && lhs.location == rhs.location
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(color)
        hasher.combine(location)
    }
}

/// A user-defined linear gradient: ordered color stops plus an angle in degrees
/// (`0` = left→right, `90` = top→bottom), rendered locally (CS-051).
struct CustomGradient: Equatable, Hashable, Codable {
    /// Color stops. Always kept with at least two entries so the gradient is
    /// well-defined; the initializer pads a short list from the default.
    var stops: [GradientStop]
    /// Gradient direction in degrees, `0...360`.
    var angle: Double

    init(stops: [GradientStop], angle: Double) {
        self.stops = stops.count >= 2 ? stops : Self.default.stops
        self.angle = Self.normalizeAngle(angle)
    }

    /// A neutral two-stop starting point (violet → azure brand vocabulary — the brand
    /// accent/secondary hex, kept in lockstep with `Brand.Palette`), used as the editor's
    /// seed and as the safe fallback for a degenerate decode.
    static let `default` = CustomGradient(
        stops: [
            GradientStop(color: RGBAColor(hex: "#4F46E5") ?? .fallbackBlack, location: 0),
            GradientStop(color: RGBAColor(hex: "#06B6D4") ?? .fallbackBlack, location: 1),
        ],
        angle: 135
    )

    /// The stops sorted by location — the order a gradient renderer expects. UI-free
    /// (the SwiftUI `Gradient.Stop`/`LinearGradient` bridging lives in `Background+UI`).
    var stopsSortedByLocation: [GradientStop] {
        stops.sorted { $0.location < $1.location }
    }

    private static func normalizeAngle(_ value: Double) -> Double {
        guard value.isFinite else { return 135 }
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    private enum CodingKeys: String, CodingKey { case stops, angle }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStops = try container.decode([GradientStop].self, forKey: .stops)
        self.stops = decodedStops.count >= 2 ? decodedStops : Self.default.stops
        self.angle = Self.normalizeAngle(try container.decode(Double.self, forKey: .angle))
    }
}

// MARK: - Image background (CS-051)

/// How an image background fills the canvas.
enum BackgroundFit: String, CaseIterable, Identifiable, Codable {
    /// Scale to fill the frame, cropping overflow (the common, edge-to-edge look).
    case fill
    /// Scale to fit entirely inside the frame, letterboxing as needed.
    case fit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fill: "Fill"
        case .fit: "Fit"
        }
    }
}

/// A user-chosen image background with fit, optional blur, and dimming (CS-051).
///
/// The image is referenced by `ImageReference`, which resolves to a file the app
/// is allowed to read — copied into the app's container, never auto-uploaded and
/// never requiring a broad file entitlement. `blur` and `dimming` are normalized
/// post-processing applied locally at render time.
struct ImageBackground: Equatable, Hashable, Codable {
    /// Where the image lives (a file in the app container; CS-051).
    var reference: ImageReference
    /// How the image fills the canvas.
    var fit: BackgroundFit
    /// Gaussian blur radius in points, `0` (none) … `40`.
    var blur: Double
    /// Dark overlay strength, `0` (none) … `1` (black). Improves code legibility
    /// over a busy photo without editing the photo itself.
    var dimming: Double

    static let blurRange = 0.0...40.0
    static let dimmingRange = 0.0...1.0

    init(
        reference: ImageReference, fit: BackgroundFit = .fill, blur: Double = 0, dimming: Double = 0
    ) {
        self.reference = reference
        self.fit = fit
        self.blur = Self.clamp(blur, to: Self.blurRange)
        self.dimming = Self.clamp(dimming, to: Self.dimmingRange)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey { case reference, fit, blur, dimming }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.reference = try container.decode(ImageReference.self, forKey: .reference)
        // A missing or unknown fit decodes to the common `.fill`; numeric values
        // are re-clamped so a hand-edited store can never feed a wild radius to
        // the renderer (CS-050).
        self.fit =
            (try? container.decode(BackgroundFit.self, forKey: .fit)) ?? .fill
        self.blur = Self.clamp(
            (try? container.decode(Double.self, forKey: .blur)) ?? 0, to: Self.blurRange)
        self.dimming = Self.clamp(
            (try? container.decode(Double.self, forKey: .dimming)) ?? 0, to: Self.dimmingRange)
    }
}

/// A stable reference to an image background file (CS-051).
///
/// The app copies the user-selected image into its own container and stores only
/// the relative file name here — not an absolute path and not the bytes — so the
/// reference is small, sandbox-safe, and survives relaunch without a broad file
/// entitlement. `BackgroundImageStore` resolves a reference to a concrete URL and
/// handles the missing-file case by reporting `nil`, which callers degrade to a
/// safe default background (CS-051 graceful degradation).
struct ImageReference: Equatable, Hashable, Codable {
    /// The file name within the app's background-images directory (no path).
    let fileName: String
}
