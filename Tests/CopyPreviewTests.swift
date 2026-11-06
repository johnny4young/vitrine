import AppKit
import Testing
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Copy preview", .serialized)
struct CopyPreviewTests {
    private final class PreviewSpy {
        var items: [CopyPreview.Item] = []
        var dismissals = 0
        var display: FeedbackDisplay {
            FeedbackDisplay(
                { _, _ in }, preview: { [weak self] in self?.items.append($0) },
                dismissPreview: { [weak self] in self?.dismissals += 1 })
        }
    }

    /// Never ordered on screen, so the suite leaves no window on the developer's display.
    private final class OffscreenPanel: NSPanel {
        override func orderFrontRegardless() {}
    }

    private func makeController(
        announcing: @escaping @MainActor (String) -> Void = { _ in }
    )
        -> CopyPreviewController
    {
        let controller = CopyPreviewController(
            postAnnouncement: announcing, makePanel: { OffscreenPanel() })
        controller.holdsUntilDismissed = true
        return controller
    }

    private func makeSession(_ settings: AppSettings, display: FeedbackDisplay) -> EditorSession {
        settings.config.code = "let x = 1"
        settings.outputBehavior.closeAfterCopy = false
        return EditorSession(
            identity: EditorWindowIdentity(index: 62),
            environment: AppEnvironment(defaults: testDefaults()),
            feedback: display, presentation: .noOp, settings: settings)
    }

    private func samplePNG(width: Int = 40, height: Int = 20) throws -> Data {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test func aConcealedOrDisabledCopyShowsNoPreview() {
        let behavior = AppSettings(defaults: testDefaults()).outputBehavior
        #expect(CopyPreview.isShown(for: behavior))
        behavior.concealClipboard = true
        #expect(!CopyPreview.isShown(for: behavior))
        behavior.concealClipboard = false
        behavior.showsCopyPreview = false
        #expect(!CopyPreview.isShown(for: behavior))
    }

    @Test func theSettingPersists() {
        let defaults = testDefaults()
        AppSettings(defaults: defaults).outputBehavior.showsCopyPreview = false
        #expect(!OutputBehavior(defaults: defaults).showsCopyPreview)
    }

    @Test func anEditorCopyPreviewsTheExactBytesOnThePasteboard() throws {
        let spy = PreviewSpy()
        let session = makeSession(AppSettings(defaults: testDefaults()), display: spy.display)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        session.copyImage(closing: nil, pasteboard: pasteboard)

        let copied = try #require(pasteboard.data(forType: .png))
        #expect(spy.items.map(\.png) == [copied])
    }

    @Test func aConcealedEditorCopyIsNeverPreviewed() {
        let spy = PreviewSpy()
        let settings = AppSettings(defaults: testDefaults())
        settings.outputBehavior.concealClipboard = true
        let session = makeSession(settings, display: spy.display)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        session.copyImage(closing: nil, pasteboard: pasteboard)

        #expect(pasteboard.data(forType: .png) != nil)
        #expect(spy.items.isEmpty)
        #expect(spy.dismissals == 1)
    }

    @Test(arguments: [true, false])
    func aQuickCapturePreviewReopensRecentsOnlyWhenHistoryKeptIt(saved: Bool) throws {
        let spy = PreviewSpy()
        var routed: [String] = []
        let presenter = CaptureFeedbackPresenter(
            display: spy.display,
            routing: CaptureRecoveryRouting(
                loadPrimaryEditor: { _ in routed.append("load") },
                presentEditor: { routed.append("editor") },
                presentWebSnapshot: { _ in routed.append("web") },
                presentRecents: { routed.append("recents") }))
        let png = try samplePNG()
        let result = QuickCapture.Result(
            outcome: .copied, copiedToClipboard: true, savedToFile: false, copiedPNG: png,
            savedToRecents: saved)

        presenter.present(result, environment: AppEnvironment(defaults: testDefaults()))
        presenter.present(
            .nonProducing(.empty), environment: AppEnvironment(defaults: testDefaults()))

        let item = try #require(spy.items.first)
        #expect(spy.items.count == 1)
        #expect(spy.dismissals == 1)
        #expect(item.png == png)
        item.reopen()
        #expect(routed == [saved ? "recents" : "editor"])
    }

    @Test func theDraggedItemCarriesThePNGAndWritesItOnlyOnce() throws {
        let png = try samplePNG()
        let promise = CopiedImagePromise(png: png, fileName: "Copied.png")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(promise.writableTypes(for: pasteboard).contains(.png))
        #expect(promise.pasteboardPropertyList(forType: .png) as? Data == png)

        let folder = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: promise.fileName)
        var errors: [Error?] = []
        promise.filePromiseProvider(promise, writePromiseTo: url) { errors.append($0) }
        promise.filePromiseProvider(promise, writePromiseTo: url) { errors.append($0) }

        #expect(try Data(contentsOf: url) == png)
        #expect(errors.count == 2)
        #expect(errors.first.map { $0 == nil } == true)
        #expect(errors.last.map { $0 != nil } == true)
    }

    @Test func aNewCopyReplacesThePreviewAndStaleEventsAreIgnored() throws {
        var announcements: [String] = []
        let controller = makeController { announcements.append($0) }
        defer { controller.dismiss() }
        var reopened: [String] = []
        let first = try samplePNG(width: 30)
        let second = try samplePNG(width: 50)

        controller.present(CopyPreview.Item(png: first) { reopened.append("first") })
        let firstPanel = controller.panel
        let stale = controller.events(for: controller.generation)
        controller.present(CopyPreview.Item(png: second) { reopened.append("second") })
        stale.dismiss()
        stale.open()

        #expect(controller.panel === firstPanel)
        #expect(controller.item?.png == second)
        #expect(reopened.isEmpty)
        #expect(announcements.count == 2)

        controller.events(for: controller.generation).open()
        #expect(reopened == ["second"])
        #expect(controller.item == nil)
        #expect(controller.panel?.isVisible == false)
    }

    @Test func aLargeCopyIsDecodedAtThumbnailSize() throws {
        let png = try samplePNG(width: 3000, height: 1000)
        let image = try #require(CopyPreview.thumbnail(of: png, maxPixelSize: 440))
        #expect(max(image.width, image.height) <= 440)
        #expect(abs(Double(image.width) / Double(image.height) - 3) < 0.05)

        let controller = makeController()
        defer { controller.dismiss() }
        controller.present(CopyPreview.Item(png: png) {})
        #expect(controller.item?.png == png)
    }

    @Test(arguments: [true, false])
    func changingEitherSettingWithdrawsTheShownPreview(conceal: Bool) async throws {
        let behavior = AppSettings(defaults: testDefaults()).outputBehavior
        let controller = makeController()
        defer { controller.dismiss() }
        controller.dismissOnPolicyChange(of: behavior)
        controller.present(CopyPreview.Item(png: try samplePNG()) {})
        #expect(controller.item != nil)

        if conceal { behavior.concealClipboard = true } else { behavior.showsCopyPreview = false }
        for _ in 0..<50 where controller.item != nil { await Task.yield() }

        #expect(controller.item == nil)
    }

    @Test func thePreviewFitsItsBoxAndSitsAtTheBottomOfTheScreen() {
        let wide = CopyPreview.displaySize(for: CGSize(width: 2000, height: 500))
        #expect(wide.width <= CopyPreview.maximumSize.width)
        #expect(wide.height <= CopyPreview.maximumSize.height)
        #expect(abs(wide.width / wide.height - 4) < 0.1)
        let small = CGSize(width: 60, height: 40)
        #expect(CopyPreview.displaySize(for: small) == small)

        let visible = CGRect(x: 0, y: 40, width: 1440, height: 835)
        let frame = CopyPreview.frame(for: CGSize(width: 252, height: 182), in: visible)
        #expect(visible.contains(frame))
        #expect(frame.maxY < visible.midY)
        #expect(frame.maxX > visible.midX)
    }

    @Test func thePreviewUsesTheScreenUnderThePointer() {
        let primary = (
            frame: CGRect(x: 0, y: 0, width: 1600, height: 1200),
            visible: CGRect(x: 0, y: 80, width: 1600, height: 1095)
        )
        let side = (
            frame: CGRect(x: 1600, y: -300, width: 1920, height: 1080),
            visible: CGRect(x: 1600, y: -300, width: 1920, height: 1055)
        )
        let screens = [primary, side]
        #expect(
            CopyPreview.visibleFrame(containing: CGPoint(x: 800, y: 600), screens: screens)
                == primary.visible)
        #expect(
            CopyPreview.visibleFrame(containing: CGPoint(x: 2000, y: 0), screens: screens)
                == side.visible)
        #expect(
            CopyPreview.visibleFrame(containing: CGPoint(x: -50, y: 0), screens: screens)
                == primary.visible)
        #expect(CopyPreview.visibleFrame(containing: .zero, screens: []) == nil)
    }

    @Test func thePreviewOutlastsTheHUDAndWaitsLongerForVoiceOver() {
        let regular = CopyPreview.lifetime(voiceOverRunning: false)
        #expect(regular > CaptureHUD.displayDuration(hasActions: false))
        #expect(CopyPreview.lifetime(voiceOverRunning: true) > regular)
    }

    @Test func droppedFileNamesAreDistinctAndFinderSafe() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let name = CopyPreview.fileName(at: now)
        #expect(name.hasSuffix(".png"))
        #expect(!name.contains("/") && !name.contains(":"))
        #expect(name != CopyPreview.fileName(at: now.addingTimeInterval(1)))
    }
}
