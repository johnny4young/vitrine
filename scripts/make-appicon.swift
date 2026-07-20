#!/usr/bin/env swift  //
// Reproducibly generates the macOS app icon set: a rounded-rect ocean
// gradient with a "</>" glyph, rendered crisply at every required size.
// Run from the repo root: `swift scripts/make-appicon.swift` (or `make icon`).
//
import AppKit

let outDir = "Vitrine/Resources/Assets.xcassets/AppIcon.appiconset"

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let side = CGFloat(pixels)
    let inset = side * 0.08
    let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = rect.width * 0.2237
    let path = CGPath(
        roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors =
        [
            NSColor(srgbRed: 0.18, green: 0.19, blue: 0.57, alpha: 1).cgColor,
            NSColor(srgbRed: 0.11, green: 1.0, blue: 1.0, alpha: 1).cgColor,
        ] as CFArray
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient, start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    ctx.restoreGState()

    let glyph = "</>"
    let font = NSFont.monospacedSystemFont(ofSize: side * 0.30, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let string = NSAttributedString(string: glyph, attributes: attributes)
    let textSize = string.size()
    string.draw(at: NSPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let files: [(pixels: Int, name: String)] = [
    (16, "icon_16.png"), (32, "icon_32.png"), (64, "icon_64.png"),
    (128, "icon_128.png"), (256, "icon_256.png"), (512, "icon_512.png"), (1024, "icon_1024.png"),
]

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for file in files {
    try! render(file.pixels).write(to: URL(fileURLWithPath: "\(outDir)/\(file.name)"))
    print("• \(file.name) (\(file.pixels)px)")
}

let images: [[String: String]] = [
    ["idiom": "mac", "size": "16x16", "scale": "1x", "filename": "icon_16.png"],
    ["idiom": "mac", "size": "16x16", "scale": "2x", "filename": "icon_32.png"],
    ["idiom": "mac", "size": "32x32", "scale": "1x", "filename": "icon_32.png"],
    ["idiom": "mac", "size": "32x32", "scale": "2x", "filename": "icon_64.png"],
    ["idiom": "mac", "size": "128x128", "scale": "1x", "filename": "icon_128.png"],
    ["idiom": "mac", "size": "128x128", "scale": "2x", "filename": "icon_256.png"],
    ["idiom": "mac", "size": "256x256", "scale": "1x", "filename": "icon_256.png"],
    ["idiom": "mac", "size": "256x256", "scale": "2x", "filename": "icon_512.png"],
    ["idiom": "mac", "size": "512x512", "scale": "1x", "filename": "icon_512.png"],
    ["idiom": "mac", "size": "512x512", "scale": "2x", "filename": "icon_1024.png"],
]
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(
    withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
print("• Contents.json")
