import AppKit
import SwiftUI
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@Suite("Stage regions")
@MainActor
struct StageRegionTests {
    private let canvas = CGRect(x: 0, y: 0, width: 400, height: 300)
    private let card = CGRect(x: 40, y: 40, width: 320, height: 220)

    @Test func theCardSplitsIntoBandsAtTheMidpointsBetweenItsParts() throws {
        let layout = StageRegionLayout(
            canvas: canvas, card: card,
            chrome: CGRect(x: 60, y: 60, width: 280, height: 12),
            header: CGRect(x: 60, y: 84, width: 280, height: 20),
            code: CGRect(x: 60, y: 120, width: 200, height: 100))
        #expect(layout.rect(for: .chrome) == CGRect(x: 40, y: 40, width: 320, height: 38))
        #expect(layout.rect(for: .header) == CGRect(x: 40, y: 78, width: 320, height: 34))
        #expect(layout.rect(for: .content) == CGRect(x: 40, y: 112, width: 320, height: 148))
        #expect(layout.rect(for: .shadow) == nil)
        #expect(layout.region(at: CGPoint(x: 45, y: 45)) == .chrome)
        #expect(layout.region(at: CGPoint(x: 350, y: 100)) == .header)
        #expect(layout.region(at: CGPoint(x: 300, y: 250)) == .content)
        #expect(layout.region(at: CGPoint(x: 10, y: 10)) == .background)
        #expect(layout.region(at: CGPoint(x: 10, y: 310)) == nil, "A legend band is no region")
    }

    @Test func aCardWithoutPartsIsAllContent() {
        let layout = StageRegionLayout(canvas: canvas, card: card)
        #expect(layout.rect(for: .content) == card)
        #expect(
            StageRegionLayout(canvas: canvas, card: nil).region(at: CGPoint(x: 200, y: 150))
                == .background)
        #expect(StageRegionLayout().region(at: .zero) == nil)
    }

    @Test func theShadowHugsTheCardOnItsOffsetSideAndYieldsToTheCard() throws {
        let layout = StageRegionLayout(
            canvas: canvas, card: card,
            shadow: Brand.ShadowStyle(color: .black, radius: 20, x: 0, y: 8))
        let shadow = try #require(layout.rect(for: .shadow))
        #expect(shadow == CGRect(x: 30, y: 38, width: 340, height: 240))
        #expect(layout.region(at: CGPoint(x: 200, y: 270)) == .shadow)
        #expect(layout.region(at: CGPoint(x: 200, y: 150)) == .content)
        #expect(layout.region(at: CGPoint(x: 200, y: 285)) == .background)
        let flat = StageRegionLayout(
            canvas: canvas, card: card,
            shadow: Brand.ShadowStyle(color: .black, radius: 0, x: 0, y: 8))
        #expect(flat.rect(for: .shadow) == nil)
    }

    @Test func eachRegionOpensTheSectionThatStylesIt() {
        #expect(StageRegion.background.target(usesImageContent: false) == .pane(.background))
        #expect(StageRegion.shadow.target(usesImageContent: false) == .pane(.canvas))
        #expect(StageRegion.chrome.target(usesImageContent: false) == .pane(.canvas))
        #expect(StageRegion.header.target(usesImageContent: false) == .header)
        #expect(StageRegion.content.target(usesImageContent: false) == .pane(.typography))
        #expect(StageRegion.content.target(usesImageContent: true) == .pane(.frame))
        #expect(StageRegion.chrome.target(usesImageContent: true) == .pane(.frame))
        for image in [false, true] {
            let dock = InspectorPane.dockPanes(usesImageContent: image)
            for region in StageRegion.allCases {
                guard case .pane(let pane) = region.target(usesImageContent: image) else {
                    #expect(!region.isRoutable(usesImageContent: image, isCanvasMode: true))
                    #expect(region.isRoutable(usesImageContent: image, isCanvasMode: false))
                    continue
                }
                #expect(dock.contains(pane), "Canvas mode's dock must open \(region)")
            }
        }
        for region in StageRegion.allCases {
            #expect(!region.actionName(usesImageContent: false).isEmpty)
        }
        #expect(
            StageRegion.content.actionName(usesImageContent: true)
                != StageRegion.content.actionName(usesImageContent: false))
    }

    @Test func accessibilityActionsListOnlyTheRegionsTheCaptureDraws() {
        var config = SnapshotConfig()
        config.showChrome = false
        config.showShadow = false
        #expect(StageRegion.drawn(by: config) == [.content, .background])
        config.showChrome = true
        config.showShadow = true
        config.metadata.title = "Title"
        #expect(
            StageRegion.drawn(by: config) == [.chrome, .header, .content, .shadow, .background])
    }

    @Test func theModelRepeatsARequestForTheSameRegion() {
        let model = StageRegionModel()
        model.route(.background, usesImageContent: false)
        let first = model.reveal
        model.route(.background, usesImageContent: false)
        #expect(model.reveal?.target == .pane(.background))
        #expect(model.reveal != first, "A second click on the same region must still reveal")
        model.hover(.content)
        #expect(model.hovered == .content)
    }

    @Test func aStageClickThatClosedAPopoverOpensNoOther() {
        let closed = DockPopoverClose(pane: .typography, uptime: 100)
        #expect(
            DockPopoverClose.pane(
                afterStageReveal: .background, open: nil, lastClose: closed, now: 100.1) == nil)
        #expect(
            DockPopoverClose.pane(
                afterStageReveal: .background, open: nil, lastClose: closed, now: 100.6)
                == .background)
        #expect(
            DockPopoverClose.pane(
                afterStageReveal: .background, open: .typography, lastClose: nil, now: 100)
                == .background)
    }

    // MARK: - Real clicks

    private struct Harness {
        let window: NSWindow
        let hosting: NSView
        let model: StageRegionModel
    }

    /// Scaled and pinned to the scaled size, as the stage fits a card.
    private func makeHarness(
        _ config: SnapshotConfig, isEnabled: Bool = true, scale: CGFloat = 1
    ) -> Harness {
        let size = NSHostingView(rootView: SnapshotCanvas(config: config)).fittingSize
        let scaled = CGSize(width: size.width * scale, height: size.height * scale)
        let model = StageRegionModel()
        let hosting = FirstMouseHostingView(
            rootView: SnapshotCanvas(config: config)
                .fixedSize()
                .modifier(
                    StageRegionRouting(
                        model: model, config: config, canvasSize: size, isCanvasMode: false,
                        isEnabled: isEnabled)
                )
                .scaleEffect(scale)
                .frame(width: scaled.width, height: scaled.height))
        hosting.frame = NSRect(origin: .zero, size: scaled)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        return Harness(window: window, hosting: hosting, model: model)
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(200)) }

    /// The mouse-up waits in the queue: selectable text tracks the drag in its own loop.
    private func click(
        _ harness: Harness, at point: CGPoint, releasingAt end: CGPoint? = nil
    )
        throws
    {
        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try #require(
                NSEvent.mouseEvent(
                    with: type, location: harness.hosting.convert(point, to: nil),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: harness.window.windowNumber, context: nil, eventNumber: 0,
                    clickCount: 1, pressure: 1))
        }
        let down = try event(.leftMouseDown, at: point)
        let release = end ?? point
        if release != point {
            NSApp.postEvent(try event(.leftMouseDragged, at: release), atStart: false)
        }
        NSApp.postEvent(try event(.leftMouseUp, at: release), atStart: false)
        NSApp.sendEvent(down)
    }

    private func codeConfig() -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "let greeting = \"Hello\"\nprint(greeting)\nprint(greeting)"
        config.language = .swift
        config.showChrome = true
        config.showShadow = true
        config.metadata.title = "Greeting"
        return config
    }

    @Test(arguments: [1.0, 0.5])
    func clicksOnTheRenderedPartsReachTheirSections(scale: Double) async throws {
        let harness = makeHarness(codeConfig(), scale: scale)
        defer { harness.window.orderOut(nil) }
        try await settle()
        let layout = harness.model.layout
        let expected: [(StageRegion, InspectorReveal.Target)] = [
            (.background, .pane(.background)), (.chrome, .pane(.canvas)), (.header, .header),
            (.content, .pane(.typography)),
        ]
        for (region, target) in expected {
            let rect = try #require(layout.rect(for: region), "\(region) was laid out")
            // Corners clear of the card and of text: the code region routes from the card's
            // inset beside the code.
            let local =
                region == .background
                ? CGPoint(x: rect.minX + 4, y: rect.minY + 4)
                : CGPoint(x: rect.minX + 6, y: rect.midY)
            try click(harness, at: CGPoint(x: local.x * scale, y: local.y * scale))
            try await settle()
            #expect(harness.model.reveal?.target == target, "\(region) at \(scale)")
        }
    }

    @Test func aClickOnTheCodeTextKeepsSelectingWithoutRouting() async throws {
        let harness = makeHarness(codeConfig())
        defer { harness.window.orderOut(nil) }
        try await settle()
        let code = try #require(harness.model.layout.rect(for: .content))
        try click(harness, at: CGPoint(x: code.midX, y: code.midY))
        try await settle()
        #expect(harness.model.reveal == nil)
    }

    @Test func noClickRoutesWhileAMarkOrToolOwnsTheStage() async throws {
        let harness = makeHarness(codeConfig(), isEnabled: false)
        defer { harness.window.orderOut(nil) }
        try await settle()
        try click(harness, at: CGPoint(x: 4, y: 4))
        try await settle()
        #expect(harness.model.reveal == nil)
    }
}

/// The test host stays inactive, and a click there is a first mouse that only activates.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
