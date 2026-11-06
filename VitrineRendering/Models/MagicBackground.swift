import AppKit
import ImageIO
import SwiftUI
import VitrineDomain

/// Background gradients derived from the capture: the syntax colors its text uses, or the
/// dominant colors of a beautified image. The same input always gives the same gradients, and a
/// result is an ordinary custom gradient, so presets, recipes and share links carry it unchanged.
public enum MagicBackground {
    /// One color of the capture and the share of it drawn in that color.
    nonisolated public struct Swatch: Equatable, Sendable {
        public let color: RGBAColor
        public let weight: Double

        public init(color: RGBAColor, weight: Double) {
            self.color = color
            self.weight = weight
        }
    }

    /// The card must stand off every stop by at least the large-text ratio.
    nonisolated static let cardSeparation = Brand.Contrast.aaLarge
    nonisolated static let minimumSaturation = 0.18
    nonisolated static let minimumHueGap = 1.0 / 8
    nonisolated static let sampleSide = 16

    /// Gradients for a code capture, from the colors its visible text is drawn in. Under a
    /// translucent card each stop is darkened or lightened until the legibility guard passes.
    public static func gradients(for config: SnapshotConfig) -> [CustomGradient] {
        guard
            let card = ThemeLegibility.cardColor(
                theme: config.theme, language: config.language, palette: config.terminalPalette)
        else { return [] }
        let cardColor = RGBAColor(
            red: card.redComponent, green: card.greenComponent, blue: card.blueComponent,
            opacity: 1)
        let candidates = variants(
            of: palette(from: codeSwatches(for: config), card: cardColor), card: cardColor)
        guard card.alphaComponent < 1 else { return candidates }
        let towardDark = HSL(cardColor).lightness < 0.5
        return candidates.map { gradient in
            CustomGradient(
                stops: gradient.stops.map {
                    GradientStop(
                        color: readable($0.color, config: config, towardDark: towardDark),
                        location: $0.location)
                },
                angle: gradient.angle)
        }
    }

    /// Gradients for a beautified image, from a small fixed-size sample of its pixels.
    @concurrent public static func gradients(forImageAt url: URL) async -> [CustomGradient] {
        variants(of: palette(from: swatches(ofImageAt: url), card: nil), card: nil)
    }

    /// The glyph share of each ink, measured by the legibility guard over a known surface so a
    /// translucent card still reports.
    static func codeSwatches(for config: SnapshotConfig) -> [Swatch] {
        var probe = config
        probe.background = .solid(.fallbackBlack)
        probe.showShadow = false
        guard let report = ThemeLegibility.measure(ThemeLegibility.Input(probe)) else { return [] }
        var weights: [String: Double] = [:]
        for ink in report.inks { weights[ink.hex, default: 0] += ink.share }
        return weights.compactMap { hex, weight in
            RGBAColor(hex: hex).map { Swatch(color: $0, weight: weight) }
        }
    }

    private static func readable(
        _ color: RGBAColor, config: SnapshotConfig, towardDark: Bool
    ) -> RGBAColor {
        var hsl = HSL(color)
        for _ in 0..<10 {
            var probe = config
            probe.background = .solid(hsl.color)
            probe.showShadow = false
            guard let report = ThemeLegibility.measure(ThemeLegibility.Input(probe)), report.isWeak
            else { return hsl.color }
            hsl.lightness = min(max(hsl.lightness + (towardDark ? -0.08 : 0.08), 0), 1)
        }
        return hsl.color
    }

    nonisolated static func swatches(ofImageAt url: URL) -> [Swatch] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            (try? BackgroundImageStore.validatedImageMetadata(in: source)) != nil
        else { return [] }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: sampleSide * 4,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return [] }
        return swatches(of: image)
    }

    /// Averages the image's pixels into 512 color buckets, skipping mostly transparent ones.
    nonisolated static func swatches(of image: CGImage) -> [Swatch] {
        let side = sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                    bytesPerRow: side * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }

        var buckets: [Int: (red: Double, green: Double, blue: Double, count: Int)] = [:]
        var total = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3])
            guard alpha >= 128 else { continue }
            let channels = (0..<3).map { min(Double(pixels[index + $0]) / alpha, 1) }
            let key = channels.reduce(0) { $0 << 3 | Int($1 * 7.999) }
            var bucket = buckets[key] ?? (0, 0, 0, 0)
            bucket.red += channels[0]
            bucket.green += channels[1]
            bucket.blue += channels[2]
            bucket.count += 1
            buckets[key] = bucket
            total += 1
        }
        guard total > 0 else { return [] }
        return buckets.keys.sorted().compactMap { key in
            guard let bucket = buckets[key] else { return nil }
            let count = Double(bucket.count)
            return Swatch(
                color: RGBAColor(
                    red: bucket.red / count, green: bucket.green / count,
                    blue: bucket.blue / count, opacity: 1),
                weight: count / Double(total))
        }
    }

    /// Up to three distinct hues, heaviest first. Grays and the card's own color carry no hue,
    /// so content without one gets a neutral pair in its dominant tone.
    nonisolated static func palette(from swatches: [Swatch], card: RGBAColor?) -> [RGBAColor] {
        let ranked = swatches.filter { $0.weight > 0 }.sorted {
            $0.weight != $1.weight ? $0.weight > $1.weight : $0.color.hexString < $1.color.hexString
        }
        var picked: [HSL] = []
        for swatch in ranked where picked.count < 3 {
            let hsl = HSL(swatch.color)
            guard hsl.saturation >= minimumSaturation,
                card.map({ contrast(swatch.color, $0) >= 1.2 }) ?? true,
                picked.allSatisfy({ hueDistance($0.hue, hsl.hue) >= minimumHueGap })
            else { continue }
            picked.append(hsl)
        }
        guard let first = picked.first else {
            let tone =
                ranked.first.map { HSL($0.color) } ?? card.map { HSL($0) } ?? HSL(.fallbackBlack)
            let neutral = HSL(hue: tone.hue, saturation: min(tone.saturation, 0.12), lightness: 0.5)
            return [neutral.shifted(-0.14), neutral.shifted(0.12)].map { backdrop($0, card: card) }
        }
        if picked.count == 1 {
            picked.append(
                HSL(
                    hue: (first.hue + minimumHueGap).truncatingRemainder(dividingBy: 1),
                    saturation: first.saturation, lightness: first.lightness))
        }
        return picked.map { backdrop($0, card: card) }
    }

    /// Linear, reversed, three-stop and tonal variants of a palette, without repeats.
    nonisolated static func variants(of palette: [RGBAColor], card: RGBAColor?) -> [CustomGradient]
    {
        guard let first = palette.first else { return [] }
        let second = palette.count > 1 ? palette[1] : first
        let third = palette.count > 2 ? palette[2] : nil
        let base = HSL(first)
        let layouts: [([RGBAColor], Double)] = [
            ([first, second], 135),
            ([second, third ?? first], 45),
            ([first, second, third ?? backdrop(base.shifted(0.16), card: card)], 120),
            (
                [
                    backdrop(base.shifted(-0.14), card: card),
                    backdrop(base.shifted(0.14), card: card),
                ], 90
            ),
        ]
        var gradients: [CustomGradient] = []
        for (colors, angle) in layouts {
            let last = Double(colors.count - 1)
            let gradient = CustomGradient(
                stops: colors.enumerated().map {
                    GradientStop(color: $0.element, location: Double($0.offset) / last)
                },
                angle: angle)
            if !gradients.contains(gradient) { gradients.append(gradient) }
        }
        return gradients
    }

    /// A hue tamed into a backdrop, then moved away from the card until the card stands off it.
    nonisolated static func backdrop(_ hsl: HSL, card: RGBAColor?) -> RGBAColor {
        var tone = HSL(
            hue: hsl.hue,
            saturation: hsl.saturation < minimumSaturation
                ? hsl.saturation : min(max(hsl.saturation, 0.3), 0.8),
            lightness: min(max(hsl.lightness, 0.3), 0.7))
        guard let card else { return tone.color }
        let lighten = HSL(card).lightness < 0.5
        while contrast(tone.color, card) < cardSeparation,
            lighten ? tone.lightness < 0.9 : tone.lightness > 0.1
        {
            tone.lightness += lighten ? 0.04 : -0.04
        }
        return tone.color
    }

    nonisolated static func contrast(_ a: RGBAColor, _ b: RGBAColor) -> Double {
        Brand.Contrast.ratio(
            Color(.sRGB, red: a.red, green: a.green, blue: a.blue),
            on: Color(.sRGB, red: b.red, green: b.green, blue: b.blue))
    }

    nonisolated static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let distance = abs(a - b)
        return min(distance, 1 - distance)
    }

    /// Hue, saturation and lightness in `0...1`, so derived tones stay deterministic plain math.
    nonisolated struct HSL: Equatable {
        var hue: Double
        var saturation: Double
        var lightness: Double

        init(hue: Double, saturation: Double, lightness: Double) {
            self.hue = hue
            self.saturation = saturation
            self.lightness = lightness
        }

        init(_ color: RGBAColor) {
            let high = max(color.red, color.green, color.blue)
            let low = min(color.red, color.green, color.blue)
            let delta = high - low
            lightness = (high + low) / 2
            guard delta > 0 else {
                hue = 0
                saturation = 0
                return
            }
            saturation = delta / (1 - abs(2 * lightness - 1))
            let sector: Double =
                switch high {
                case color.red: (color.green - color.blue) / delta
                case color.green: (color.blue - color.red) / delta + 2
                default: (color.red - color.green) / delta + 4
                }
            hue = (sector / 6).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
        }

        func shifted(_ amount: Double) -> HSL {
            HSL(hue: hue, saturation: saturation, lightness: min(max(lightness + amount, 0), 1))
        }

        var color: RGBAColor {
            let chroma = (1 - abs(2 * lightness - 1)) * saturation
            let sector = hue * 6
            let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
            let (r, g, b): (Double, Double, Double) =
                switch Int(sector) % 6 {
                case 0: (chroma, x, 0)
                case 1: (x, chroma, 0)
                case 2: (0, chroma, x)
                case 3: (0, x, chroma)
                case 4: (x, 0, chroma)
                default: (chroma, 0, x)
                }
            let m = lightness - chroma / 2
            return RGBAColor(red: r + m, green: g + m, blue: b + m, opacity: 1)
        }
    }
}
