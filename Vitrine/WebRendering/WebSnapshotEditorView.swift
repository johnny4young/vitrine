import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
struct WebSnapshotEditorView: View {
    @ObservedObject var model: WebSnapshotModel
    @EnvironmentObject private var settings: AppSettings

    @State private var showDisclosure = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                previewStage
                inspector
                    .frame(width: 340)
            }
        }
        .frame(minWidth: 900, minHeight: 580)
        .background(VitrineTokens.Surface.window)
        .tint(VitrineTokens.Accent.base)
        .sheet(isPresented: $showDisclosure) {
            WebPrivacyDisclosureView(
                onConfirm: {
                    // Record consent and proceed with the capture the user asked for.
                    settings.urlCaptureConsentGiven = true
                    showDisclosure = false
                    Task { await capture() }
                },
                onCancel: { showDisclosure = false }
            )
            // The disclosure card already pads itself (Brand.Spacing.xl) over its own
            // background; no extra outer padding, which would double the inset.
        }
    }

    private var hasResult: Bool { model.renderedAsset != nil }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: VitrineTokens.Spacing.xs) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(verbatim: "Web Snapshot")
                    .font(.system(size: VitrineTokens.FontSize.headline, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.primary)
            }

            Spacer(minLength: 0)

            iconButton(
                "web-snapshot-save-button", label: VitrineCommand.saveImage.accessibilityLabel,
                help: "Save the snapshot as a file", systemImage: "square.and.arrow.down",
                shortcut: KeyboardShortcut("s", modifiers: .command), action: saveImage)
            iconButton(
                "web-snapshot-share-button", label: VitrineCommand.shareImage.accessibilityLabel,
                help: "Share the snapshot", systemImage: "square.and.arrow.up", action: shareImage)

            GradientCTAButton {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                Text("Copy image")
            } action: {
                copyImage()
            }
            .help("Copy the snapshot to the clipboard")
            .disabled(!hasResult)
            // ⇧⌘C, matching the editor's image-copy command (the menu's image commands
            // are gated to editor windows, so this window provides its own shortcut).
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .accessibilityLabel(VitrineCommand.copyImage.accessibilityLabel)
            .accessibilityIdentifier("web-snapshot-copy-button")
        }
        .padding(.vertical, 10)
        .padding(.trailing, VitrineTokens.Spacing.md)
        .padding(.leading, 86)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VitrineTokens.Line.border)
                .frame(height: Brand.Stroke.hairline)
        }
        .accessibilityContainerIdentifier("web-snapshot-toolbar")
        .accessibilityLabel("Toolbar")
    }

    @ViewBuilder
    private func iconButton(
        _ identifier: String, label: String, help: String, systemImage: String,
        shortcut: KeyboardShortcut? = nil, action: @escaping () -> Void
    ) -> some View {
        let button = GlassIconButton(systemImage: systemImage, action: action)
            .help(help)
            .disabled(!hasResult)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
        if let shortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    // MARK: - Preview

    private var previewStage: some View {
        GeometryReader { _ in
            ZStack {
                if model.isRendering {
                    loadingView
                } else if let asset = model.renderedAsset {
                    Image(nsImage: nsImage(from: asset))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(36)
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 16)
                } else if let error = model.errorMessage {
                    messageView(systemImage: "exclamationmark.triangle", text: error)
                } else {
                    emptyView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .background(VitrineTokens.Surface.stage)
        .layoutPriority(2)
        .accessibilityIdentifier("web-snapshot-preview-stage")
    }

    /// The in-flight state: a spinner, a localized "loading locally" line, and — for a
    /// URL — the host shown verbatim, so it is always transparent which page is loading
    /// over the network (the non-invasive in-context network notice).
    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(
                model.mode == .url
                    ? "Loading the page locally in WebKit…" : "Rendering locally…"
            )
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(VitrineTokens.Text.secondary)
            if let host = model.loadingHost {
                Text(verbatim: host)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
            }
        }
        // Announce the in-progress state as one element (the spinner alone says
        // nothing useful), and mark it live so VoiceOver re-reads it.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var emptyView: some View {
        messageView(
            systemImage: model.mode == .url ? "globe" : "chevron.left.forwardslash.chevron.right",
            text: model.mode == .url
                ? String(localized: "Enter a URL, then Capture to snapshot the page.")
                : String(localized: "Paste HTML, then Render to snapshot it."))
    }

    private func messageView(systemImage: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(VitrineTokens.Text.tertiary)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(40)
    }

    // MARK: - Inspector

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xl - 8) {
                modeSection
                inputSection
                optionsSection
                captureSection
            }
            .padding(.top, 18)
            .padding(.horizontal, VitrineTokens.Spacing.xl - 12)
            .padding(.bottom, VitrineTokens.Spacing.lg)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(VitrineTokens.Line.border)
                .frame(width: Brand.Stroke.hairline)
        }
        .tint(VitrineTokens.Accent.base)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
        .accessibilityIdentifier("web-snapshot-inspector")
    }

    private var modeSection: some View {
        section("Source") {
            TokenSegmentedPicker(
                options: [
                    (WebInputMode.url, Text(verbatim: "URL")),
                    (WebInputMode.html, Text(verbatim: "HTML")),
                ],
                selection: $model.mode,
                fillsWidth: true,
                optionIdentifiers: ["web-snapshot-mode-url", "web-snapshot-mode-html"]
            )
            .accessibilityLabel("Source")
            .accessibilityIdentifier("web-snapshot-mode-picker")
        }
    }

    @ViewBuilder private var inputSection: some View {
        switch model.mode {
        case .url:
            section("URL") {
                InspectorTextField(
                    prompt: Text(verbatim: "https://example.com"), text: $model.urlText,
                    onSubmit: attemptCapture, disablesAutocorrection: true
                )
                .accessibilityIdentifier("web-snapshot-url-field")
                if !NetworkCapability.isURLCaptureEnabled {
                    Text(
                        "URL capture runs only in the direct-download build. HTML rendering works here."
                    )
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .html:
            section("HTML") {
                InspectorCodeField(
                    text: $model.htmlText, placeholder: "<h1>Hello</h1>", height: 160
                )
                .accessibilityIdentifier("web-snapshot-html-editor")
            }
        }
    }

    private var optionsSection: some View {
        section("Output") {
            WebCaptureControls(settings: settings)
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GradientCTAButton {
                Image(systemName: model.mode == .url ? "camera.viewfinder" : "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                Text(model.mode == .url ? "Capture" : "Render")
            } action: {
                attemptCapture()
            }
            .disabled(!model.canRender || model.isRendering)
            // ⌘Return triggers the primary action, the macOS convention for a window's
            // default button.
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("web-snapshot-capture-button")

            if model.mode == .url {
                Label {
                    Text("Loads the page locally in WebKit — nothing is sent to a server.")
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    /// Starts a capture. For a URL, the first attempt (or any attempt on a build that
    /// cannot reach the network) routes through the privacy disclosure before any load;
    /// HTML renders immediately since it never reaches the network.
    private func attemptCapture() {
        if model.mode == .url,
            !settings.urlCaptureConsentGiven || !NetworkCapability.isURLCaptureEnabled
        {
            showDisclosure = true
            return
        }
        Task { await capture() }
    }

    private func capture() async {
        await model.render(settings: settings)
        if let error = model.errorMessage {
            CaptureHUDController.shared.present(Notifier.failure(error))
        }
    }

    // MARK: - Export

    private func nsImage(from asset: RenderedAsset) -> NSImage {
        NSImage(
            cgImage: asset.cgImage,
            size: NSSize(width: asset.cgImage.width, height: asset.cgImage.height))
    }

    private func copyImage() {
        guard let asset = model.renderedAsset else { return }
        guard let png = ExportManager.pngData(from: asset.cgImage) else {
            CaptureHUDController.shared.present(
                Notifier.failure(String(localized: "Couldn't copy the image")))
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setData(png, forType: .png)
        CaptureHUDController.shared.present(
            copied
                ? Notifier.confirmation(String(localized: "Image copied to clipboard"))
                : Notifier.failure(String(localized: "Couldn't copy the image")))
    }

    private func saveImage() {
        guard let asset = model.renderedAsset else { return }
        // Honor the user's chosen export format (PNG/PDF) through the same ladder the
        // rest of the app uses, rather than always writing PNG.
        guard
            let payload = ExportManager.encodedPayload(
                settings.exportFormat,
                png: { asset.cgImage },
                pdf: { ExportManager.pdfData(from: asset.cgImage) })
        else {
            CaptureHUDController.shared.present(
                Notifier.failure(String(localized: "Couldn't save the image")))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [payload.type]
        panel.nameFieldStringValue = "vitrine-web.\(payload.ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try payload.data.write(to: url)
            CaptureHUDController.shared.present(
                Notifier.confirmation(String(localized: "Image saved")))
        } catch {
            CaptureHUDController.shared.present(
                Notifier.failure(String(localized: "Couldn't save the image")))
        }
    }

    private func shareImage() {
        guard let asset = model.renderedAsset, let view = NSApp.keyWindow?.contentView else {
            return
        }
        ShareManager.share(nsImage(from: asset), relativeTo: view)
    }

    // MARK: - Chrome helpers

    private func section<Content: View>(
        _ title: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            TokenGroupLabel(title: Text(title))
            content()
        }
    }

}
