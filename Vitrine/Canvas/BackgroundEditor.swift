import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VitrineDomain
import VitrineRendering

/// The background control shared by the Settings Style pane and the inspectors: the
/// gradient preset swatches, a "+" that switches to a custom kind, and, once the
/// background is no longer a stock preset, the kind picker and per-kind controls.
struct BackgroundControls: View {
    enum Layout {
        /// Settings rows with captions.
        case settings
        /// Compact inspector rows.
        case inspector
    }

    @Binding var background: VitrineDomain.BackgroundStyle
    var layout: Layout = .settings
    var imageStore: BackgroundImageStore = .container

    var body: some View {
        ChipScroll(topPadding: 2, bottomPadding: 6) {
            ForEach(GradientPreset.allCases) { preset in
                GradientSwatch(
                    preset: preset, isSelected: selectedPreset == preset, size: swatchSize
                ) {
                    background = .gradient(preset)
                }
            }
            CustomBackgroundSwatch(size: swatchSize) {
                background = BackgroundKind.solid.makeDefault(
                    from: background, imageStore: imageStore)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gradient preset")
        .accessibilityIdentifier("background-gradient-preset")

        if selectedPreset == nil {
            row(label: Text("Kind"), caption: Text("Gradient preset, solid color, or image")) {
                TokenSegmentedPicker(
                    options: [
                        (BackgroundKind.gradient, Text("Gradient")),
                        (.customGradient, Text("Custom")),
                        (.solid, Text("Solid")),
                        (.image, Text("Image")),
                        (.transparent, Text("Transparent")),
                    ],
                    selection: kindBinding
                )
                .accessibilityLabel("Kind")
                .accessibilityIdentifier("background-kind-picker")
            }
            detail
        }
    }

    /// The controls for the active non-preset kind.
    @ViewBuilder private var detail: some View {
        switch background {
        case .gradient:
            EmptyView()
        case .customGradient(let gradient):
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xs) {
                CustomGradientEditor(
                    gradient: Binding(
                        get: { gradient }, set: { background = .customGradient($0) }))
            }
            .padding(.vertical, layout == .settings ? 9 : 0)
        case .solid(let color):
            row(label: Text("Color"), caption: nil) {
                ColorPicker(
                    "Color",
                    selection: Binding(
                        get: { color.color }, set: { background = .solid(RGBAColor($0)) }),
                    supportsOpacity: true
                )
                .labelsHidden()
                .accessibilityIdentifier("background-solid-color")
            }
        case .image(let image):
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xs) {
                ImageBackgroundEditor(
                    image: Binding(get: { image }, set: { background = .image($0) }),
                    imageStore: imageStore)
            }
            .padding(.vertical, layout == .settings ? 9 : 0)
        case .transparent:
            Text("Exports with a real transparent (alpha) background.")
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.tertiary)
        }
    }

    @ViewBuilder
    private func row<Content: View>(
        label: Text, caption: Text?, @ViewBuilder content: () -> Content
    ) -> some View {
        switch layout {
        case .settings: TokenRow(label: label, caption: caption, content: content)
        case .inspector: InspectorRow(label: label, content: content)
        }
    }

    private var swatchSize: CGFloat { layout == .settings ? 26 : 28 }

    private var selectedPreset: GradientPreset? {
        if case .gradient(let preset) = background { return preset }
        return nil
    }

    /// Switching kind seeds a default from the current style, so the change never
    /// lands on a blank state.
    private var kindBinding: Binding<BackgroundKind> {
        Binding(
            get: { BackgroundKind(background) },
            set: { background = $0.makeDefault(from: background, imageStore: imageStore) }
        )
    }
}

/// The selectable background kinds shown in the editor's kind picker.
///
/// Distinct from `BackgroundStyle` (which carries each kind's payload): this is
/// the flat, `CaseIterable` set the picker needs, plus the logic for switching
/// between kinds with a reasonable default for the newly selected one.
enum BackgroundKind: String, CaseIterable, Identifiable {
    case gradient, customGradient, solid, image, transparent

    var id: String { rawValue }

    /// The kind backing an existing style.
    init(_ style: VitrineDomain.BackgroundStyle) {
        switch style {
        case .gradient: self = .gradient
        case .customGradient: self = .customGradient
        case .solid: self = .solid
        case .image: self = .image
        case .transparent: self = .transparent
        }
    }

    /// A default `BackgroundStyle` for this kind, seeded from the previous style
    /// where it makes sense so switching kinds carries intent forward.
    func makeDefault(
        from previous: VitrineDomain.BackgroundStyle, imageStore: BackgroundImageStore
    )
        -> VitrineDomain.BackgroundStyle
    {
        switch self {
        case .gradient:
            if case .gradient = previous { return previous }
            return .gradient(.aurora)
        case .customGradient:
            switch previous {
            case .customGradient: return previous
            // Seed the editable gradient from the current preset so "tweak this
            // preset" is one step.
            case .gradient(let preset): return .customGradient(preset.asCustomGradient)
            default: return .customGradient(.default)
            }
        case .solid:
            if case .solid = previous { return previous }
            return .solid(RGBAColor(.black))
        case .image:
            if case .image = previous { return previous }
            // No image chosen yet: present an empty reference so the editor shows
            // its "choose image" affordance and the canvas degrades to the safe
            // default until a file is picked.
            return .image(ImageBackground(reference: ImageReference(fileName: "")))
        case .transparent:
            return .transparent
        }
    }
}

/// Editor for a custom gradient: an angle slider plus per-stop color wells, with
/// add/remove for stops. Keeps at least two stops so the gradient stays
/// well-defined.
struct CustomGradientEditor: View {
    @Binding var gradient: CustomGradient

    var body: some View {
        // A live swatch of the gradient being edited.
        RoundedRectangle(cornerRadius: Brand.Radius.sm, style: .continuous)
            .fill(gradient.linearGradient)
            .frame(height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: Brand.Radius.sm, style: .continuous)
                    .strokeBorder(.separator, lineWidth: Brand.Stroke.hairline)
            )
            .accessibilityHidden(true)

        Slider(value: angleBinding, in: 0...360, step: 1) {
            // Surface the live angle next to the label, since the 0°/360°
            // endpoints imply a degree readout that the slider alone omits.
            Text("Angle (\(Int(gradient.angle))°)")
        } minimumValueLabel: {
            // Locale-neutral degree endpoints, shown verbatim.
            Text(verbatim: "0°")
        } maximumValueLabel: {
            Text(verbatim: "360°")
        }
        .help("Gradient direction in degrees")
        .accessibilityValue("\(Int(gradient.angle))°")
        .accessibilityIdentifier("custom-gradient-angle")

        ForEach(Array(zip($gradient.stops.indices, $gradient.stops)), id: \.1.id) { index, $stop in
            HStack {
                // Disambiguate every stop's controls for VoiceOver: without the
                // index, a multi-stop gradient reads as a row of identical
                // "Stop" / unlabeled-slider pairs.
                ColorPicker(
                    "Color stop \(index + 1)",
                    selection: Binding(
                        get: { stop.color.color }, set: { stop.color = RGBAColor($0) }),
                    supportsOpacity: true
                )
                .labelsHidden()
                .accessibilityLabel("Color stop \(index + 1)")
                Slider(value: $stop.location, in: 0...1)
                    .accessibilityLabel("Color stop \(index + 1) position")
                if gradient.stops.count > 2 {
                    Button {
                        removeStop(stop)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove color stop \(index + 1)")
                }
            }
        }

        Button {
            addStop()
        } label: {
            Label("Add color stop", systemImage: "plus")
        }
        .accessibilityIdentifier("custom-gradient-add-stop")
    }

    private var angleBinding: Binding<Double> {
        Binding(get: { gradient.angle }, set: { gradient.angle = $0 })
    }

    private func addStop() {
        // Insert a midpoint stop so the new control starts somewhere sensible.
        let sorted = gradient.stops.sorted { $0.location < $1.location }
        let midpoint = ((sorted.first?.location ?? 0) + (sorted.last?.location ?? 1)) / 2
        let color = sorted.last?.color ?? RGBAColor(.white)
        gradient.stops.append(GradientStop(color: color, location: midpoint))
    }

    private func removeStop(_ stop: GradientStop) {
        guard gradient.stops.count > 2 else { return }
        gradient.stops.removeAll { $0.id == stop.id }
    }
}

/// Editor for an image background: the chosen image, a button to pick another,
/// and fit/blur/dimming controls. Picking uses an `NSOpenPanel`
/// (user-selected access) and imports the file into the app container.
struct ImageBackgroundEditor: View {
    @Binding var image: ImageBackground
    var imageStore: BackgroundImageStore

    @State private var importError: String?
    @State private var urlText = ""
    @State private var isImporting = false
    @State private var importTask: Task<Void, Never>?
    @State private var isDownloading = false
    @State private var downloadTask: Task<Void, Never>?
    /// One generation shared by the local import and the URL download. Only the
    /// latest request may commit `image.reference`, surface an error, or clear the
    /// in-flight state — a slow earlier operation of either kind can therefore
    /// never overwrite the user's later selection, and a drained stale task cannot
    /// nil out the handle of the request that superseded it.
    @State private var imageRequestGeneration = 0

    var body: some View {
        Button(action: chooseImage) {
            if isImporting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Importing image")
            } else {
                Label(hasImage ? "Replace image…" : "Choose image…", systemImage: "photo")
            }
        }
        .disabled(isImporting)
        .accessibilityIdentifier("background-choose-image")
        .onDisappear {
            importTask?.cancel()
            importTask = nil
            isImporting = false
        }

        // Downloading from a URL is a network action, so it appears only in a build
        // that carries the network-client entitlement (the direct-download DMG). In
        // the App Store build the App Sandbox would block the request anyway, so the
        // field is hidden rather than shown disabled.
        if NetworkCapability.isURLCaptureEnabled {
            HStack(spacing: 6) {
                TextField("Image URL", text: $urlText, prompt: Text(verbatim: "https://…"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(startDownload)
                    .accessibilityIdentifier("background-image-url-field")

                Button(action: startDownload) {
                    if isDownloading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .disabled(isDownloading || parsedURL == nil)
                .accessibilityLabel("Download image")
                .accessibilityIdentifier("background-image-url-add")
            }
            .onDisappear {
                downloadTask?.cancel()
                downloadTask = nil
                isDownloading = false
            }

            Text(
                "Vitrine downloads the image directly from the URL you enter — nothing else is sent."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        if let message = importError {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }

        if hasImage {
            Picker("Fit", selection: fitBinding) {
                ForEach(BackgroundFit.allCases) { fit in
                    Text(fit.displayName).tag(fit)
                }
            }
            .accessibilityIdentifier("background-image-fit")

            Slider(value: blurBinding, in: ImageBackground.blurRange, step: 1) {
                Text("Blur")
            }
            .help("Soften the image so code stands out")
            .accessibilityIdentifier("background-image-blur")

            Slider(value: dimmingBinding, in: ImageBackground.dimmingRange) {
                Text("Dimming")
            }
            .help("Darken the image to keep code readable")
            .accessibilityIdentifier("background-image-dimming")
        } else {
            Text("Images stay on your Mac — Vitrine copies the file locally and never uploads it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var hasImage: Bool { imageStore.url(for: image.reference) != nil }

    private var fitBinding: Binding<BackgroundFit> {
        Binding(get: { image.fit }, set: { image.fit = $0 })
    }
    private var blurBinding: Binding<Double> {
        Binding(get: { image.blur }, set: { image.blur = $0 })
    }
    private var dimmingBinding: Binding<Double> {
        Binding(get: { image.dimming }, set: { image.dimming = $0 })
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose an image to use as the background.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        imageRequestGeneration += 1
        let generation = imageRequestGeneration
        importTask?.cancel()
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        isImporting = true
        importError = nil
        importTask = Task {
            defer {
                if generation == imageRequestGeneration {
                    importTask = nil
                    isImporting = false
                }
            }
            do {
                let reference = try await imageStore.importImageConcurrently(from: url)
                guard await imageStore.preloadImage(for: reference) != nil else {
                    throw BackgroundImageStore.ImportError.notAnImage
                }
                try Task.checkCancellation()
                guard generation == imageRequestGeneration else { return }
                image.reference = reference
            } catch is CancellationError {
                return
            } catch let error as BackgroundImageStore.ImportError {
                guard !Task.isCancelled, generation == imageRequestGeneration else { return }
                importError = error.message
            } catch {
                guard !Task.isCancelled, generation == imageRequestGeneration else { return }
                importError = BackgroundImageStore.ImportError.copyFailed.message
            }
        }
    }

    /// The entered text parsed into a fetchable image URL, or `nil` when it is not a
    /// well-formed `http(s)` URL — also the disabled state for the download button.
    private var parsedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            url.host?.isEmpty == false
        else { return nil }
        return url
    }

    private func startDownload() {
        guard let url = parsedURL, !isDownloading else { return }
        imageRequestGeneration += 1
        let generation = imageRequestGeneration
        downloadTask?.cancel()
        importTask?.cancel()
        importTask = nil
        isImporting = false
        isDownloading = true
        importError = nil
        downloadTask = Task {
            defer {
                if generation == imageRequestGeneration {
                    downloadTask = nil
                    isDownloading = false
                }
            }
            do {
                let reference = try await imageStore.importImage(downloadedFrom: url)
                guard await imageStore.preloadImage(for: reference) != nil else {
                    throw BackgroundImageStore.ImportError.notAnImage
                }
                try Task.checkCancellation()
                guard generation == imageRequestGeneration else { return }
                image.reference = reference
                urlText = ""
            } catch is CancellationError {
                return
            } catch let error as BackgroundImageStore.ImportError {
                guard !Task.isCancelled, generation == imageRequestGeneration else { return }
                importError = error.message
            } catch {
                guard !Task.isCancelled, generation == imageRequestGeneration else { return }
                importError = BackgroundImageStore.ImportError.downloadFailed.message
            }
        }
    }
}
