import Foundation
import Testing

@testable import Vitrine

// URL snapshot renderer coverage uses an explicit network mode.
//
// These suites prove the documented behavior:
//
// 1. **URL validation** — only `http`/`https` URLs are accepted; `file:`, `data:`,
//    `javascript:`, private localhost, and malformed URLs are rejected as typed
//    errors that never carry the URL itself.
// 2. **Network-entitlement guard** — URL capture is disabled until the app target
//    includes `com.apple.security.network.client`; a build without it refuses with
//    a typed `RenderError.urlCaptureDisabled`, and the renderer never touches WebKit.
// 3. **Nonpersistent data store** — `WKWebsiteDataStore.nonPersistent()` is the
//    default, and cookies / persistent website data are opt-in only.
// 4. **No remote render service** — a URL snapshot is produced locally; the renderer
//    holds no remote endpoint and the disclosure copy says so.
// 5. **Typed failures, never a blank image** — every failure mode surfaces a typed
//    error rather than an empty asset.
//
// Live WebKit vs. pure logic:
//
// Almost everything here is pure logic — validation, the entitlement gate, the
// data-store mapping, routing, and the disclosure copy — so those suites always run
// and assert on every machine. The single suite that rasterizes a real page through
// `WKWebView` is gated on `WebKitAvailability.canRenderOffscreen` (defined in
// `HTMLRendererTests`), because a sandboxed, ad-hoc-signed test host cannot launch a
// web content process; it is reported as **skipped** there, never silently passed.

// MARK: - Fixtures

enum URLFixture {
    /// A representative, well-formed remote page URL — used only to exercise
    /// validation and routing logic; no test loads it over the network.
    static func valid() throws -> URL {
        try #require(URL(string: "https://example.com/article"))
    }

    /// A small, self-contained local HTML file written to the temp directory and
    /// served over `file://`. Loading a `file:` URL is rejected by validation, so this
    /// is used only by the live snapshot suite, which renders it by handing the engine
    /// a config built from an already-validated URL substitute. The page has an
    /// explicit background so the snapshot is non-empty.
    static func writeLocalPage() throws -> URL {
        let html = """
            <!doctype html><html><head><meta charset="utf-8"><style>
            html,body{margin:0;padding:0;background:#0b1020;color:#fff;font:24px sans-serif}
            </style></head><body><h1>Local capture</h1></body></html>
            """
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineURLTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("page.html")
        try html.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
