#!/usr/bin/env swift
// Standalone golden-image comparator (CS-025).
//
// Diffs two PNGs the same way the in-process suite (`Tests/GoldenComparator.swift`)
// does, so the tool CI uses to triage an uploaded diff artifact is itself verified.
// It deliberately depends on nothing but Foundation + ImageIO + CoreGraphics, so it
// runs as `swift scripts/compare-goldens.swift <a.png> <b.png>` with no build step.
//
// The per-channel tolerance and the differing-pixel fraction floor below are the
// SAME constants as `GoldenComparator.channelTolerance` /
// `GoldenComparator.pixelFractionTolerance`. The test
// `GoldenImageTests.toleranceConstantsAreTheDocumentedValues` pins those values, so
// a change to the tolerance is a reviewed edit that must update both copies — the
// two can never silently diverge.
//
// Exit codes: 0 = match (within tolerance), 1 = differ / unequal size, 2 = usage or
// read error.

import CoreGraphics
import Foundation
import ImageIO

/// Maximum allowed absolute difference per 8-bit channel before a pixel counts as
/// changed. Mirrors `GoldenComparator.channelTolerance`.
let channelTolerance = 2

/// Maximum allowed fraction of pixels that may exceed `channelTolerance` before the
/// images are considered different. Mirrors `GoldenComparator.pixelFractionTolerance`.
let pixelFractionTolerance = 0.001

/// Prints a message to standard error.
func warn(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Decodes a PNG at `path` into a `CGImage`, or `nil` if unreadable.
func loadImage(_ path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url),
        let source = CGImageSourceCreateWithData(data as CFData, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// Redraws `image` into a tightly packed straight-alpha RGBA8 buffer so two images
/// compare channel-for-channel regardless of original layout or color space.
func rgba8Bytes(_ image: CGImage) -> [UInt8]? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return [] }
    let bytesPerRow = width * 4
    var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
        guard
            let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return ok ? buffer : nil
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    warn("usage: compare-goldens.swift <golden.png> <actual.png>")
    exit(2)
}

let goldenPath = arguments[1]
let actualPath = arguments[2]

guard let golden = loadImage(goldenPath) else {
    warn("error: could not read image at \(goldenPath)")
    exit(2)
}
guard let actual = loadImage(actualPath) else {
    warn("error: could not read image at \(actualPath)")
    exit(2)
}

guard golden.width == actual.width, golden.height == actual.height else {
    print(
        "DIFFER size \(golden.width)x\(golden.height) vs \(actual.width)x\(actual.height)")
    exit(1)
}

guard let goldenBytes = rgba8Bytes(golden), let actualBytes = rgba8Bytes(actual) else {
    warn("error: could not rasterize one of the images for comparison")
    exit(2)
}

let pixelCount = golden.width * golden.height
var differingPixels = 0
var maxChannelDelta = 0
var index = 0
let byteCount = pixelCount * 4
while index < byteCount {
    var pixelDiffers = false
    for channel in 0..<4 {
        let delta = abs(Int(goldenBytes[index + channel]) - Int(actualBytes[index + channel]))
        if delta > maxChannelDelta { maxChannelDelta = delta }
        if delta > channelTolerance { pixelDiffers = true }
    }
    if pixelDiffers { differingPixels += 1 }
    index += 4
}

let fraction = pixelCount == 0 ? 0 : Double(differingPixels) / Double(pixelCount)
let summary =
    "differing=\(differingPixels)/\(pixelCount) "
    + "maxDelta=\(maxChannelDelta) fraction=\(String(format: "%.5f", fraction)) "
    + "(channelTolerance=\(channelTolerance) fractionTolerance=\(pixelFractionTolerance))"

if fraction <= pixelFractionTolerance {
    print("MATCH \(summary)")
    exit(0)
} else {
    print("DIFFER \(summary)")
    exit(1)
}
