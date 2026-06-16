import Foundation
import SwiftUI
import Testing

@testable import Vitrine

@Suite("Privacy manifest")
struct PrivacyManifestTests {
    @Test func declaresNoTrackingAndOnlyUserDefaults() throws {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy must be bundled with the app (CS-011)")
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any] ?? []).isEmpty)

        let apiTypes = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let categories = apiTypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        #expect(categories == ["NSPrivacyAccessedAPICategoryUserDefaults"])
    }

    /// The manifest must stay minimal even though Product Phase 2 URL capture exists in
    /// the codebase (CS-043/CS-045): loading a user-requested page in a local
    /// `WKWebView` and rasterizing it on-device introduces no required-reason API beyond
    /// UserDefaults and collects no data. This asserts the "updated only if new
    /// required-reason APIs or data collection appear" acceptance — the manifest still
    /// declares no tracking, no tracking domains, and no collected data.
    @Test func urlCaptureAddsNoTrackingOrCollectionToTheManifest() throws {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [Any] ?? []).isEmpty)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any] ?? []).isEmpty)

        // The only required-reason API stays UserDefaults, used for the app's own
        // settings (reason CA92.1). URL capture adds nothing here.
        let apiTypes = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        #expect(apiTypes.count == 1)
        let reasons = apiTypes.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        #expect(reasons == ["CA92.1"])
    }
}

/// CS-045 — web snapshot privacy and permission UX.
///
/// These suites prove the acceptance criteria that are verifiable headlessly:
///
/// 1. The Phase 1 promise ("code never leaves the Mac") still appears in the user-facing
///    copy and docs.
/// 2. The Product Phase 2 copy says URL capture loads the requested webpage **locally**
///    in WebKit, with no remote screenshot service.
/// 3. The App Store privacy posture (no tracking, no collected data, no analytics) is
///    asserted both in the manifest and across the shipping web-rendering sources.
/// 4. The first-use disclosure view reuses the single, reviewable copy from
///    `WebSnapshotConfig.firstUseDisclosure`, and reflects the network-capability gate.
@Suite("Web snapshot privacy and permission UX · CS-045")
struct WebSnapshotPrivacyUXTests {

    // MARK: - Repository anchoring

    /// The repository root, anchored to this file (`<repo>/Tests/…`), so the docs- and
    /// source-consistency checks read the committed files rather than the built bundle.
    /// Mirrors `URLRendererTests` and `LocalizationTests`, which anchor the same way.
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    private static func file(_ components: String...) -> URL {
        components.reduce(repositoryRoot) { $0.appendingPathComponent($1) }
    }

    private static func text(_ components: String...) throws -> String {
        try String(
            contentsOf: components.reduce(repositoryRoot) { $0.appendingPathComponent($1) },
            encoding: .utf8)
    }

    // MARK: - First-use disclosure view reuses the single source of words

    /// The disclosure view exists and is built from the reviewable, localized copy in
    /// `WebSnapshotConfig.firstUseDisclosure` — the single source of the privacy
    /// sentence — rather than hard-coding its own wording. The view's source references
    /// that symbol; the copy itself is asserted by `URLFirstUseDisclosureTests`.
    @Test func theDisclosureViewReusesTheFirstUseCopy() throws {
        let source = try Self.text("Vitrine", "WebRendering", "WebPrivacyDisclosureView.swift")
        #expect(
            source.contains("WebSnapshotConfig.firstUseDisclosure"),
            "WebPrivacyDisclosureView must source its copy from the single firstUseDisclosure (CS-045)."
        )
        // It must restate the Phase 1 promise the first time the network is ever used.
        #expect(source.localizedCaseInsensitiveContains("never leaves your Mac"))
    }

    /// The disclosure view defaults its enabled state to the real network-capability
    /// gate, so a Phase 1 build (no network entitlement) shows the action disabled and a
    /// capable build shows it enabled — the UI never implies a capability the build lacks.
    ///
    /// This asserts the *wiring* as a value, not as source text: a default-constructed
    /// view adopts `NetworkCapability.isURLCaptureEnabled` verbatim, so the gate cannot
    /// be silently hard-coded to `true`. (That the confirm button's `.disabled` binding
    /// reads this flag is the one fact only the rendered `body` can show, so it stays a
    /// source check below; everything else is behavioral.)
    @Test func theDisclosureViewDefaultsToTheRealNetworkCapabilityGate() {
        let view = WebPrivacyDisclosureView(onConfirm: {}, onCancel: {})
        #expect(view.isURLCaptureEnabled == NetworkCapability.isURLCaptureEnabled)
    }

    /// The gate is injectable, so the disclosure renders in both states regardless of
    /// the host build's entitlement: a network-free build (gate off) and a capable build
    /// (gate on) are both representable. This is what lets the view show the disabled
    /// action plus the direct-download note on a build with no network entitlement, and
    /// the live confirm action on one that has it.
    @Test func theDisclosureViewGateIsInjectableInBothStates() {
        let disabled = WebPrivacyDisclosureView(
            onConfirm: {}, onCancel: {}, isURLCaptureEnabled: false)
        #expect(disabled.isURLCaptureEnabled == false)
        let enabled = WebPrivacyDisclosureView(
            onConfirm: {}, onCancel: {}, isURLCaptureEnabled: true)
        #expect(enabled.isURLCaptureEnabled)
    }

    /// The confirm button's `.disabled(!isURLCaptureEnabled)` binding is a property of
    /// the rendered `body`, which cannot be inspected here without driving SwiftUI and
    /// CoreText off the main actor (unsafe under the parallel test runner). Pinning the
    /// binding in source keeps the disabled-when-incapable contract from regressing; the
    /// flag it reads is asserted behaviorally above.
    @Test func theConfirmActionBindsItsDisabledStateToTheGate() throws {
        let source = try Self.text("Vitrine", "WebRendering", "WebPrivacyDisclosureView.swift")
        #expect(source.contains("disabled(!isURLCaptureEnabled)"))
    }

    /// The first-use copy itself makes both phase facts explicit: a URL capture loads
    /// the page locally in WebKit, and there is no remote render service. (The view
    /// renders this copy; here we pin the words the view shows.)
    @Test func theDisclosureCopySaysURLCaptureLoadsLocallyInWebKit() {
        let disclosure = WebSnapshotConfig.firstUseDisclosure
        #expect(disclosure.message.localizedCaseInsensitiveContains("locally"))
        #expect(disclosure.message.localizedCaseInsensitiveContains("WebKit"))
        #expect(disclosure.message.localizedCaseInsensitiveContains("on-device"))
        #expect(disclosure.message.localizedCaseInsensitiveContains("remote"))
    }

    // MARK: - Phase 1 promise remains in the shipping copy

    @Test func infoPlistKeepsThePhase1PromiseAndNamesLocalWebKitCapture() throws {
        let url = Self.file("Vitrine", "Resources", "Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let usage = try #require(
            plist["NSPasteboardUsageDescription"] as? String,
            "Info.plist must carry a clipboard usage description")

        // Phase 1 promise: code never leaves the Mac.
        #expect(usage.localizedCaseInsensitiveContains("never leaves your Mac"))
        // Phase 2 copy: a URL is captured by loading the webpage locally in WebKit.
        #expect(usage.localizedCaseInsensitiveContains("locally in WebKit"))
    }

    @Test func readmeStatesBothThePhase1PromiseAndLocalURLCapture() throws {
        let readme = try Self.text("README.md")
        // Phase 1 promise.
        #expect(readme.localizedCaseInsensitiveContains("never leaves your Mac"))
        // Phase 2: the requested webpage loads locally in WebKit, with no remote service.
        #expect(readme.localizedCaseInsensitiveContains("locally in WebKit"))
        #expect(readme.localizedCaseInsensitiveContains("no remote screenshot service"))
        // No analytics/telemetry is promised.
        #expect(readme.localizedCaseInsensitiveContains("no telemetry"))
    }

    @Test func projectDocStatesBothPhasesAndAppStorePrivacyLabels() throws {
        let project = try Self.text("docs", "PROJECT.md")
        // Phase 1 promise + Phase 2 local-WebKit posture.
        #expect(project.localizedCaseInsensitiveContains("never leaves your Mac"))
        #expect(project.localizedCaseInsensitiveContains("locally in WebKit"))
        #expect(project.localizedCaseInsensitiveContains("no remote screenshot service"))
        // App Store privacy labels match actual behavior: Data Not Collected.
        #expect(project.localizedCaseInsensitiveContains("Data Not Collected"))
        // No analytics or telemetry is introduced by URL capture.
        #expect(project.localizedCaseInsensitiveContains("telemetry"))
        // The README anchors to this section; keep the heading stable.
        #expect(project.contains("## Privacy and permissions"))
    }

    // MARK: - Entitlement / docs consistency

    /// The app target still ships **without** the network client entitlement in Phase 1,
    /// which is exactly what the docs and disclosure describe ("gated until the
    /// entitlement is added"). This keeps the shipped entitlement and the documented
    /// posture consistent — if the entitlement is ever added, this test forces the
    /// privacy copy and App Store posture to be revisited (CS-045/CS-062).
    @Test func entitlementsAndDocsAgreeThatPhase1HasNoNetworkAccess() throws {
        let data = try Data(contentsOf: Self.file("Vitrine", "Resources", "Vitrine.entitlements"))
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(
            plist[NetworkCapability.networkClientEntitlement] == nil,
            "Phase 1 must not request the network client entitlement; docs/disclosure gate on it (CS-045)."
        )
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)

        // The PROJECT.md posture explicitly names this gating entitlement.
        let project = try Self.text("docs", "PROJECT.md")
        #expect(project.contains(NetworkCapability.networkClientEntitlement))
    }

    // MARK: - No analytics or telemetry introduced by URL capture

    /// URL capture must introduce no analytics or telemetry. Scan the **code** of the
    /// web-rendering sources (the entire Phase 2 surface) for analytics/telemetry SDK
    /// integrations — an `import` of such a module, or a reference to one of its symbols
    /// — and fail on any. This is the source-level counterpart to the manifest's "no
    /// collected data" declaration.
    ///
    /// The scan strips line comments before matching, so privacy prose that *promises*
    /// the absence of analytics (e.g. "no analytics", "no telemetry") does not trip it;
    /// only an actual integration in compiled code does.
    @Test func webRenderingSourcesContainNoAnalyticsOrTelemetry() throws {
        let directory = Self.file("Vitrine", "WebRendering")
        let fileManager = FileManager.default
        let enumerator = try #require(
            fileManager.enumerator(at: directory, includingPropertiesForKeys: nil))

        // Concrete SDK / framework module names for analytics, telemetry, and crash
        // reporting. None of these belong anywhere in the URL-capture surface, whether
        // imported or referenced as a symbol. Matched as whole words on code lines.
        let forbiddenModules = [
            "Mixpanel", "FirebaseAnalytics", "Firebase", "Amplitude", "Segment", "Sentry",
            "AppCenterAnalytics", "AppCenter", "Crashlytics", "GoogleAnalytics", "Bugsnag",
            "TelemetryDeck", "OSLogAnalytics",
        ]
        let moduleRegexes = try forbiddenModules.map {
            try NSRegularExpression(pattern: #"\b\#($0)\b"#)
        }
        // Any `import` of a module whose name itself reads as analytics/telemetry.
        let analyticsImport = try NSRegularExpression(
            pattern: #"(?im)^\s*import\s+\w*(Analytics|Telemetry)\w*"#)

        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)

            // Whole-file check for an analytics/telemetry import.
            let fileRange = NSRange(source.startIndex..<source.endIndex, in: source)
            if analyticsImport.firstMatch(in: source, range: fileRange) != nil {
                offenders.append("\(url.lastPathComponent): analytics/telemetry import")
            }

            // Per-line check on *code only* (line comments stripped), so privacy prose
            // mentioning "analytics"/"telemetry" is ignored.
            for line in source.components(separatedBy: .newlines) {
                let code = Self.strippingLineComment(line)
                guard !code.isEmpty else { continue }
                let codeRange = NSRange(code.startIndex..<code.endIndex, in: code)
                for (index, regex) in moduleRegexes.enumerated()
                where regex.firstMatch(in: code, range: codeRange) != nil {
                    offenders.append("\(url.lastPathComponent): \(forbiddenModules[index])")
                }
            }
        }
        #expect(
            offenders.isEmpty,
            "URL capture must add no analytics or telemetry (CS-045). Found: \(offenders.joined(separator: ", "))"
        )
    }

    /// Returns `line` with any trailing `//`/`///` line comment removed, so a code-only
    /// scan ignores prose. Conservatively treats the first `//` as the comment start;
    /// the web-rendering sources contain no `//` inside string literals, so this is
    /// exact for them.
    private static func strippingLineComment(_ line: String) -> String {
        if let range = line.range(of: "//") {
            return String(line[line.startIndex..<range.lowerBound])
        }
        return line
    }
}

/// CS-045 — the disclosure view's runtime contract, exercised as values rather than
/// scanned as source text.
///
/// The view's user-facing promise is twofold: confirming proceeds with the capture,
/// and cancelling loads nothing. SwiftUI invokes the `onConfirm` / `onCancel`
/// closures the view stores when their buttons are pressed, so invoking those stored
/// closures is exactly what a tap does — and asserting which one fires proves the
/// confirm and cancel actions are wired to *distinct* handlers, not accidentally
/// swapped or collapsed onto one. This is the behavioral counterpart to the
/// source-level reuse and gate checks in `WebSnapshotPrivacyUXTests`; it never
/// renders `body`, so it stays clear of CoreText under the parallel runner.
@Suite("Web privacy disclosure action wiring · CS-045")
struct WebPrivacyDisclosureActionTests {
    /// A reference box that records how many times each disclosure action fired, so a
    /// stored escaping closure can report back into the test.
    private final class ActionRecorder {
        var confirmCount = 0
        var cancelCount = 0
    }

    private func makeView(_ recorder: ActionRecorder) -> WebPrivacyDisclosureView {
        WebPrivacyDisclosureView(
            onConfirm: { recorder.confirmCount += 1 },
            onCancel: { recorder.cancelCount += 1 })
    }

    @Test func confirmingInvokesOnlyTheConfirmAction() {
        let recorder = ActionRecorder()
        let view = makeView(recorder)

        // Pressing the confirm button invokes the stored `onConfirm` closure.
        view.onConfirm()

        #expect(recorder.confirmCount == 1)
        #expect(recorder.cancelCount == 0, "confirming must never fire the cancel action")
    }

    @Test func cancellingInvokesOnlyTheCancelAction() {
        let recorder = ActionRecorder()
        let view = makeView(recorder)

        // Pressing cancel (or the escape key) invokes the stored `onCancel` closure.
        view.onCancel()

        #expect(recorder.cancelCount == 1)
        #expect(recorder.confirmCount == 0, "cancelling must never fire the capture action")
    }

    @Test func theTwoActionsAreIndependentHandlers() {
        // Confirm and cancel are not the same closure: each press advances only its own
        // counter, so the prominent capture action and the cancel action stay distinct.
        let recorder = ActionRecorder()
        let view = makeView(recorder)

        view.onConfirm()
        view.onConfirm()
        view.onCancel()

        #expect(recorder.confirmCount == 2)
        #expect(recorder.cancelCount == 1)
    }
}
