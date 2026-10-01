import AppKit
import CoreGraphics
import Darwin
import Foundation

// No local display changes. Mode switching is restricted to disposable GitHub-hosted runners.
struct DisplaySize {
    let width: Int
    let height: Int
    var area: Int { width * height }
}

func candidateIndices(_ sizes: [DisplaySize]) -> [Int] {
    sizes.indices.filter { sizes[$0].width >= 1440 && sizes[$0].height >= 900 }
        .sorted { sizes[$0].area < sizes[$1].area }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--self-test"] {
    let sizes = [
        DisplaySize(width: 1024, height: 768), DisplaySize(width: 1920, height: 1080),
        DisplaySize(width: 1440, height: 900), DisplaySize(width: 1280, height: 800),
    ]
    guard candidateIndices(sizes) == [2, 1], candidateIndices([]).isEmpty else {
        fail("Display selection self-test failed")
    }
    print("Display selection self-test passed; local preferences unchanged")
    exit(0)
}
guard arguments == ["--check"] || arguments == ["--qualify"] else {
    fail("Use --check, --qualify (hosted CI only), or --self-test")
}
let visible = NSScreen.main?.visibleFrame.size ?? .zero
let qualified = visible.width >= 1280 && visible.height >= 800
if arguments == ["--check"] {
    let payload: [String: Any] = [
        "qualified": qualified, "visibleWidth": visible.width,
        "visibleHeight": visible.height, "requiredWidth": 1280, "requiredHeight": 800,
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    guard qualified else { fail("Display cannot qualify the required 1280x800 UI journey") }
    exit(0)
}
let environment = ProcessInfo.processInfo.environment
guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_ENVIRONMENT"] == "github-hosted"
else {
    fail("Refusing to change a local or self-hosted display")
}
if qualified {
    print("Display already qualifies; no mode changed")
    exit(0)
}
let display = CGMainDisplayID()
guard let modes = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] else {
    fail("Hosted display modes unavailable")
}
let sizes = modes.map { DisplaySize(width: $0.width, height: $0.height) }
for index in candidateIndices(sizes) {
    if CGDisplaySetDisplayMode(display, modes[index], nil) == .success,
        let actual = CGDisplayCopyDisplayMode(display), actual.width >= 1440, actual.height >= 900
    {
        print("Selected hosted display mode: \(actual.width)x\(actual.height)")
        // A fresh --check process must independently measure AppKit's usable frame before UI tests.
        exit(0)
    }
}
fail("No supported hosted mode qualifies; refusing clipped or skipped UI evidence")
