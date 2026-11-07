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

    /// What a code derivation reads, gathered in one pass on the main actor.
    nonisolated public struct CodeSource: Sendable {
        let card: RGBAColor
        let isTranslucent: Bool
        let samples: ThemeLegibility.Samples?
    }

    /// The card must stand off every stop by at least the large-text ratio.
    nonisolated static let cardSeparation = Brand.Contrast.aaLarge
    nonisolated static let minimumSaturation = 0.18
    nonisolated static let minimumHueGap = 1.0 / 8
    nonisolated static let sampleSide = 16
    nonisolated static let lightnessStep = 0.04

    /// Reads the card and the visible text's inks once; the search runs off the main actor.
    public static func codeSource(for config: SnapshotConfig) -> CodeSource? {
        guard
            let card = ThemeLegibility.cardColor(
                theme: config.theme, language: config.language, palette: config.terminalPalette)
        else { return nil }
        return CodeSource(
            card: RGBAColor(
                red: card.redComponent, green: card.greenComponent, blue: card.blueComponent,
                opacity: 1),
            isTranslucent: card.alphaComponent < 1,
            samples: ThemeLegibility.samples(ThemeLegibility.Input(config)))
    }

    /// Gradients for a code capture, from the colors its visible text is drawn in.
    public static func gradients(for config: SnapshotConfig) async -> [CustomGradient] {
        guard let source = codeSource(for: config) else { return [] }
        return await gradients(from: source)
    }

    @concurrent public static func gradients(from source: CodeSource) async -> [CustomGradient] {
        let rule = StopRule(
            card: source.card, seenThrough: source.isTranslucent ? source.samples : nil)
        let swatches = source.samples.map(swatches(of:)) ?? []
        return variants(of: palette(from: swatches, rule: rule), rule: rule)
    }

    /// Gradients for a beautified image, from a small fixed-size sample of its pixels. ImageIO
    /// may resample differently across OS versions; a result is saved as a gradient anyway.
    @concurrent public static func gradients(forImageAt url: URL) async -> [CustomGradient] {
        let rule = StopRule(card: nil, seenThrough: nil)
        return variants(of: palette(from: swatches(ofImageAt: url), rule: rule), rule: rule)
    }

    /// The glyph share of each ink color.
    nonisolated static func swatches(of samples: ThemeLegibility.Samples) -> [Swatch] {
        let total = Double(samples.entries.reduce(0) { $0 + $1.count })
        var weights: [String: Double] = [:]
        for entry in samples.entries {
            weights[entry.hex, default: 0] += Double(entry.count) / total
        }
        return weights.compactMap { hex, weight in
            RGBAColor(hex: hex).map { Swatch(color: $0, weight: weight) }
        }
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
    nonisolated static func palette(from swatches: [Swatch], rule: StopRule) -> [RGBAColor] {
        let ranked = swatches.filter { $0.weight > 0 }.sorted {
            $0.weight != $1.weight ? $0.weight > $1.weight : $0.color.hexString < $1.color.hexString
        }
        var picked: [HSL] = []
        for swatch in ranked where picked.count < 3 {
            let hsl = HSL(swatch.color)
            guard hsl.saturation >= minimumSaturation,
                rule.card.map({ rounded(contrast(swatch.color, $0)) >= 1.2 }) ?? true,
                picked.allSatisfy({ hueDistance($0.hue, hsl.hue) >= minimumHueGap })
            else { continue }
            picked.append(hsl)
        }
        guard let first = picked.first else {
            let tone =
                ranked.first.map { HSL($0.color) } ?? rule.card.map { HSL($0) }
                ?? HSL(.fallbackBlack)
            let neutral = HSL(hue: tone.hue, saturation: min(tone.saturation, 0.12), lightness: 0.5)
            return [neutral.shifted(-0.14), neutral.shifted(0.12)].map { backdrop($0, rule: rule) }
        }
        if picked.count == 1 {
            picked.append(
                HSL(
                    hue: (first.hue + minimumHueGap).truncatingRemainder(dividingBy: 1),
                    saturation: first.saturation, lightness: first.lightness))
        }
        return picked.map { backdrop($0, rule: rule) }
    }

    /// Linear, reversed, three-stop and tonal variants of a palette, without repeats.
    nonisolated static func variants(of palette: [RGBAColor], rule: StopRule) -> [CustomGradient] {
        guard let first = palette.first else { return [] }
        let second = palette.count > 1 ? palette[1] : first
        let third = palette.count > 2 ? palette[2] : nil
        let base = HSL(first)
        let layouts: [([RGBAColor], Double)] = [
            ([first, second], 135),
            ([second, third ?? first], 45),
            ([first, second, third ?? backdrop(base.shifted(0.16), rule: rule)], 120),
            (
                [
                    backdrop(base.shifted(-0.14), rule: rule),
                    backdrop(base.shifted(0.14), rule: rule),
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

    /// A hue tamed into a backdrop, then the nearest lightness, either way out to black and
    /// white, that meets the rule. Failing that, the nearest that keeps the card distinct.
    nonisolated static func backdrop(_ hsl: HSL, rule: StopRule) -> RGBAColor {
        let tone = HSL(
            hue: hsl.hue,
            saturation: hsl.saturation < minimumSaturation
                ? hsl.saturation : min(max(hsl.saturation, 0.3), 0.8),
            lightness: min(max(hsl.lightness, 0.3), 0.7))
        guard let card = rule.card else { return tone.color }
        let white = RGBAColor(red: 1, green: 1, blue: 1, opacity: 1)
        let black = RGBAColor.fallbackBlack
        let lightenFirst = contrast(white, card) >= contrast(black, card)
        var candidates: [RGBAColor] = [tone.color]
        for step in 1...Int((1 / lightnessStep).rounded()) {
            for sign in lightenFirst ? [1.0, -1.0] : [-1.0, 1.0] {
                let lightness = tone.lightness + sign * lightnessStep * Double(step)
                guard (0...1).contains(lightness) else { continue }
                candidates.append(
                    HSL(hue: tone.hue, saturation: tone.saturation, lightness: lightness).color)
            }
        }
        candidates += lightenFirst ? [white, black] : [black, white]
        return candidates.first(where: rule.allows) ?? candidates.first(where: rule.separates)
            ?? (lightenFirst ? white : black)
    }

    /// What a stop must meet: the card stands off it, and text seen through a translucent card
    /// stays readable over it. Each color is measured once per derivation.
    nonisolated final class StopRule {
        let card: RGBAColor?
        let seenThrough: ThemeLegibility.Samples?
        private var readability: [RGBAColor: Bool] = [:]

        init(card: RGBAColor?, seenThrough: ThemeLegibility.Samples?) {
            self.card = card
            self.seenThrough = seenThrough
        }

        func separates(_ color: RGBAColor) -> Bool {
            guard let card else { return true }
            return MagicBackground.rounded(MagicBackground.contrast(color, card))
                >= MagicBackground.cardSeparation
        }

        func reads(_ color: RGBAColor) -> Bool {
            guard let seenThrough else { return true }
            if let known = readability[color] { return known }
            let backdrop = NSColor(
                srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
            let reads = !ThemeLegibility.isWeak(seenThrough.inks(over: backdrop))
            readability[color] = reads
            return reads
        }

        func allows(_ color: RGBAColor) -> Bool { separates(color) && reads(color) }
    }

    /// Ratios compared at three decimals, so a last-digit libm difference can't flip a stop.
    nonisolated static func rounded(_ ratio: Double) -> Double { (ratio * 1000).rounded() / 1000 }

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
