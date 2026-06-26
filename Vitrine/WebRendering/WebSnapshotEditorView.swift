import AppKit
import SwiftUI

/// The Web Snapshot composer (CS-042/CS-043): a live preview beside an inspector that
/// switches between **URL** capture and **HTML** rendering, with copy / save / share
/// export in a glass toolbar.
///
/// Both paths are local: HTML renders in an offscreen `WKWebView` with remote
/// subresources blocked, and a URL is loaded on this Mac and rasterized on-device —
/// there is no remote render service. URL capture additionally reaches the network, so
/// the first attempt presents the privacy disclosure (`WebPrivacyDisclosureView`) and
/// only proceeds once the user confirms; a build without the network entitlement shows
/// the same disclosure with the action disabled and an explanation.
///
/// The view is organized across focused extensions in sibling files —
/// `WebSnapshotEditorView+Toolbar`, `+Preview`, `+Inspector`, and `+Actions` — that
/// share this type's stored state, so those properties are module-internal rather than
/// `private`; nothing outside this type references them.
struct WebSnapshotEditorView: View {
    @ObservedObject var model: WebSnapshotModel
    @EnvironmentObject var settings: AppSettings

    @State var showDisclosure = false
    /// Which captured viewport the big preview is showing (the highlighted filmstrip
    /// tile) in a multi-resolution batch.
    @State var previewedKind: WebSnapshotConfig.ViewportPreset.Kind?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    previewStage
                    resultsFilmstrip
                }
                inspector
                    .frame(width: 340)
            }
        }
        // Merge the toolbar into the title bar so the title sits in the traffic-light row
        // (the editor pattern, CS-037): extending into the top safe area pulls the glass
        // toolbar to the window edge, with the traffic lights floating over its leading 86 pt.
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 900, minHeight: 580)
        .onChange(of: model.results.map(\.id)) {
            // A multi-size batch defaults to the composite board (previewedKind == nil);
            // a single capture selects its one viewport.
            previewedKind = model.results.count > 1 ? nil : model.results.first?.kind
        }
        .background(VitrineTokens.Surface.window)
        .tint(VitrineTokens.Accent.system)
        .sheet(isPresented: $showDisclosure) {
            WebPrivacyDisclosureView(
                onConfirm: {
                    // Record consent and proceed with the capture the user asked for.
                    settings.webCapture.consentGiven = true
                    showDisclosure = false
                    Task { await capture() }
                },
                onCancel: { showDisclosure = false }
            )
            // The disclosure card already pads itself (Brand.Spacing.xl) over its own
            // background; no extra outer padding, which would double the inset.
        }
    }

    var hasResult: Bool { model.renderedAsset != nil }

    /// Wraps a rendered asset's `CGImage` in an `NSImage` at its pixel size, for the
    /// preview, the filmstrip tiles, and the share sheet.
    func nsImage(from asset: RenderedAsset) -> NSImage {
        NSImage(
            cgImage: asset.cgImage,
            size: NSSize(width: asset.cgImage.width, height: asset.cgImage.height))
    }
}
