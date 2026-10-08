import AppKit
import CoreGraphics
import Foundation
import Testing
import VitrineDomain
import VitrineRendering
import WebKit

@testable import Vitrine

private enum RepositoryFile {
    static func text(_ components: String...) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = components.reduce(root) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func catalog() throws -> [String: Any] {
        let data = Data(try text("Vitrine", "Resources", "Localizable.xcstrings").utf8)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(object?["strings"] as? [String: Any])
    }
}

private func solidImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

private func cornerAlpha(of image: CGImage) throws -> UInt8 {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try #require(
        CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(
        image,
        in: CGRect(
            x: 0, y: CGFloat(1 - image.height), width: CGFloat(image.width),
            height: CGFloat(image.height)))
    return pixel[3]
}

@MainActor
@Suite("Network-quiet wait")
struct NetworkQuietTrackerTests {
    private let start = ContinuousClock.now
    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .milliseconds(milliseconds))
    }

    @Test func aLoadedPageStillFetchingIsNotQuiet() {
        var tracker = NetworkQuietTracker(idleWindow: .milliseconds(500))
        let busy = NetworkQuietTracker.Sample(
            isComplete: true, pendingRequests: 1, resourceCount: 3)
        let quiet = (0...30).map { tracker.record(busy, at: at($0 * 100)) }
        #expect(!quiet.contains(true))
    }

    @Test func quietRequiresAFullIdleWindowWithNoNewResources() {
        var tracker = NetworkQuietTracker(idleWindow: .milliseconds(500))
        let idle = NetworkQuietTracker.Sample(
            isComplete: true, pendingRequests: 0, resourceCount: 3)
        let grew = NetworkQuietTracker.Sample(
            isComplete: true, pendingRequests: 0, resourceCount: 4)
        // A new resource at 400 ms restarts the idle window.
        let samples = [
            (idle, 0), (idle, 300), (grew, 400), (grew, 500), (grew, 900), (grew, 1_000),
        ]
        let quiet = samples.map { tracker.record($0.0, at: at($0.1)) }
        #expect(quiet == [false, false, false, false, false, true])
    }

    @Test func theInstrumentationLoadsBeforePageScripts() {
        let script = URLSnapshotEngine.networkActivityScript
        #expect(script.injectionTime == .atDocumentStart)
        #expect(script.source.contains("XMLHttpRequest"))
        #expect(script.source.contains("window.fetch"))
    }
}

@MainActor
@Suite(
    "Network activity instrumentation in WebKit",
    .enabled("requires a launchable WKWebView web process") {
        await WebKitAvailability.canRenderOffscreen()
    })
struct NetworkActivityInstrumentationTests {
    @Test func pendingFetchesAreCountedUntilTheySettle() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(URLSnapshotEngine.networkActivityScript)
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 200, height: 200), configuration: configuration)
        let navigation = WebLoadProbe()
        webView.navigationDelegate = navigation
        webView.loadHTMLString("<html><body>probe</body></html>", baseURL: nil)
        try await navigation.waitForLoad()

        let counts =
            try await webView.callAsyncJavaScript(
                """
                const request = fetch("data:text/plain,ok");
                const during = window.__vitrineNetworkActivity.pending;
                await request.catch(() => {});
                await new Promise((resolve) => setTimeout(resolve, 0));
                return [during, window.__vitrineNetworkActivity.pending];
                """, contentWorld: .page) as? [NSNumber]
        #expect(counts?.map(\.intValue) == [1, 0])
    }
}

/// Minimal navigation delegate for the instrumentation probe.
@MainActor
private final class WebLoadProbe: NSObject, WKNavigationDelegate {
    private let waiter = WebLoadWaiter()

    func waitForLoad() async throws { try await waiter.wait(timeout: .seconds(10)) }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waiter.complete(.success(()))
    }
}

@MainActor
@Suite("Web Snapshot export polish")
struct WebSnapshotExportPolishTests {
    // MARK: - Privacy copy

    @Test func theCaptureCaptionNeverClaimsNothingIsSent() throws {
        let inspector = try RepositoryFile.text(
            "Vitrine", "WebRendering", "WebSnapshotEditorView+Inspector.swift")
        #expect(!inspector.localizedCaseInsensitiveContains("nothing is sent"))
        #expect(inspector.contains("The website receives the request"))
        // File exports may truthfully say nothing is sent; web capture copy may not.
        let webKeys = try RepositoryFile.catalog().keys.filter {
            $0.contains("WebKit") || $0.localizedCaseInsensitiveContains("page")
        }
        #expect(!webKeys.contains { $0.contains("nothing is sent") })
    }

    // MARK: - Inspector

    @Test func urlOnlyCaptureOptionsAreHiddenForHTML() {
        #expect(WebInputMode.url.usesURLCaptureOptions)
        #expect(!WebInputMode.html.usesURLCaptureOptions)
    }

    // MARK: - Raster PDFs

    @Test func rasterPDFPagesAreSizedInPoints() throws {
        let image = try solidImage(width: 2_400, height: 1_260)
        let data = try #require(ExportManager.pdfData(from: image, scale: 2))
        let provider = try #require(CGDataProvider(data: data as CFData))
        let page = try #require(CGPDFDocument(provider)?.page(at: 1))
        #expect(page.getBoxRect(.mediaBox).size == CGSize(width: 1_200, height: 630))
        let unscaled = try #require(ExportManager.pdfData(from: image))
        let unscaledProvider = try #require(CGDataProvider(data: unscaled as CFData))
        let unscaledPage = try #require(CGPDFDocument(unscaledProvider)?.page(at: 1))
        #expect(unscaledPage.getBoxRect(.mediaBox).size == CGSize(width: 2_400, height: 1_260))
    }

    // MARK: - Export all sizes

    @Test func exportNamesUseTheActualCaptureSize() throws {
        let asset = RenderedAsset(
            cgImage: try solidImage(width: 2_880, height: 8_000), profile: .sRGB)
        let result = CapturedViewport(
            kind: .desktop, preset: .desktop, asset: asset, thumbnailAsset: asset)
        #expect(
            WebSnapshotModel.exportName(for: result, scale: 2) == "vitrine-web-desktop-1440x4000")
    }

    @Test func imageSetExportHonorsTheFormatAndNeverOverwrites() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrine-image-set-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("board.pdf")
        try Data("keep".utf8).write(to: existing)

        let items = [
            ExportManager.NamedRaster(name: "board", image: try solidImage(width: 40, height: 20)),
            ExportManager.NamedRaster(name: "board", image: try solidImage(width: 40, height: 20)),
        ]
        let result = await ExportManager.exportRasters(
            items, to: directory, format: .pdf, scale: 2)

        #expect(result.written == 2)
        #expect(try Data(contentsOf: existing) == Data("keep".utf8))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(names == ["board-2.pdf", "board-3.pdf", "board.pdf"])
    }

    // MARK: - Social card matte

    @Test func imageBackedSocialCardsExportOpaque() throws {
        let missing = ImageReference(fileName: "missing-\(UUID().uuidString).png")
        let model = SocialCardModel(
            title: "Matte", codeExcerpt: "let x = 1",
            background: .image(ImageBackground(reference: missing, fit: .fit, blur: 12)))
        let image = try SocialCardRenderer.renderCGImageChecked(model, scale: 1)
        #expect(try cornerAlpha(of: image) == 255)
    }

    // MARK: - Sign-in window

    @Test func theSignInWindowNamesTheHostAndFlagsInsecurePages() throws {
        let secure = try #require(URL(string: "https://id.example.com/login"))
        let plain = try #require(URL(string: "http://staging.example.com/"))
        #expect(
            WebSessionWindowController.locationSubtitle(url: secure, hasOnlySecureContent: true)
                == "id.example.com")
        #expect(
            WebSessionWindowController.locationSubtitle(url: secure, hasOnlySecureContent: false)
                != "id.example.com")
        #expect(
            WebSessionWindowController.locationSubtitle(url: plain, hasOnlySecureContent: true)
                .contains("staging.example.com"))
        #expect(
            WebSessionWindowController.locationSubtitle(url: nil, hasOnlySecureContent: true) == "")
    }

    @Test func httpAuthenticationAsksForPasswordMethodsOnly() async {
        let basic = Self.challenge(method: NSURLAuthenticationMethodHTTPBasic)
        let answer = URLCredential(user: "qa", password: "pw", persistence: .forSession)
        let granted = await URLLoadCoordinator.response(to: basic) { _ in answer }
        #expect(granted.0 == .useCredential)
        #expect(granted.1 === answer)

        let declined = await URLLoadCoordinator.response(to: basic) { _ in nil }
        #expect(declined.0 == .cancelAuthenticationChallenge)

        let failing = Self.challenge(method: NSURLAuthenticationMethodHTTPDigest, failures: 3)
        let exhausted = await URLLoadCoordinator.response(to: failing) { _ in answer }
        #expect(exhausted.0 == .cancelAuthenticationChallenge)

        let trust = Self.challenge(method: NSURLAuthenticationMethodServerTrust)
        let deferred = await URLLoadCoordinator.response(to: trust) { _ in
            Issue.record("Server trust must not prompt for a password")
            return nil
        }
        #expect(deferred.0 == .performDefaultHandling)
    }

    private static func challenge(method: String, failures: Int = 0) -> URLAuthenticationChallenge {
        URLAuthenticationChallenge(
            protectionSpace: URLProtectionSpace(
                host: "staging.example.com", port: 443, protocol: "https", realm: "QA",
                authenticationMethod: method),
            proposedCredential: nil, previousFailureCount: failures, failureResponse: nil,
            error: nil, sender: ChallengeSender())
    }

    // MARK: - Localization

    @Test func toolbarHelpAndCarouselCountAreLocalized() throws {
        let catalog = try RepositoryFile.catalog()
        let keys = [
            "Export all sizes", "Export every captured size, plus the board, to a folder",
            "Save the snapshot as a file", "Share the snapshot",
            "Render and save the card as a file", "Render and share the card",
        ]
        for key in keys {
            let entry = try #require(catalog[key] as? [String: Any], "\(key) missing")
            #expect(entry["extractionState"] as? String != "stale", "\(key) is stale")
            let localizations = entry["localizations"] as? [String: Any]
            #expect(localizations?["es"] != nil, "\(key) has no Spanish translation")
        }

        let english = try #require(
            Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        let format = english.localizedString(forKey: "%lld slides", value: "", table: nil)
        #expect(String(format: format, locale: Locale(identifier: "en"), 1) == "1 slide")
        #expect(String(format: format, locale: Locale(identifier: "en"), 3) == "3 slides")
    }
}

private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
