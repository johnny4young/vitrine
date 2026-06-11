import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Style-pane editor for the canvas background (CS-051).
///
/// Surfaces every background kind — gradient preset, custom gradient (stops +
/// angle), solid color, user image (fit/blur/dimming), and transparent — behind
/// a single kind picker, then shows the controls for the active kind. It edits a
/// `BackgroundStyle` binding directly, so changes flow straight into the live
/// `SnapshotConfig` and persist through `AppSettings`.
struct BackgroundEditor: View {
    @Binding var background: BackgroundStyle

    /// Imports/resolves image backgrounds in the app container. Injectable so the
    /// editor can be previewed/tested against an isolated store.
    var imageStore: BackgroundImageStore = .container

    var body: some View {
        Picker("Kind", selection: kindBinding) {
            ForEach(BackgroundKind.allCases) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        .accessibilityIdentifier("background-kind-picker")

        switch background {
        case .gradient:
            presetPicker
        case .customGradient(let gradient):
            CustomGradientEditor(
                gradient: Binding(
                    get: { gradient },
                    set: { background = .customGradient($0) }))
        case .solid(let color):
            ColorPicker(
                "Color",
                selection: Binding(
                    get: { color }, set: { background = .solid($0) }),
                supportsOpacity: true
            )
            .accessibilityIdentifier("background-solid-color")
        case .image(let image):
            ImageBackgroundEditor(
                image: Binding(
                    get: { image }, set: { background = .image($0) }),
                imageStore: imageStore)
        case .transparent:
            Text("Exports with a real transparent (alpha) background.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var presetPicker: some View {
        Picker("Preset", selection: presetBinding) {
            ForEach(GradientPreset.allCases) { preset in
                Text(preset.rawValue).tag(preset)
            }
        }
        .accessibilityIdentifier("background-gradient-preset")
    }

    // MARK: - Bindings

    /// The active background kind. Switching kind seeds a sensible default for the
    /// new kind from whatever is on screen, so the change is never a jarring blank
    /// state (e.g. switching to Custom Gradient pre-fills from the current preset).
    private var kindBinding: Binding<BackgroundKind> {
        Binding(
            get: { BackgroundKind(background) },
            set: { background = $0.makeDefault(from: background, imageStore: imageStore) }
        )
    }

    private var presetBinding: Binding<GradientPreset> {
        Binding(
            get: {
                if case .gradient(let preset) = background { return preset }
                return .aurora
            },
            set: { background = .gradient($0) }
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

    var displayName: String {
        switch self {
        case .gradient: "Gradient preset"
        case .customGradient: "Custom gradient"
        case .solid: "Solid color"
        case .image: "Image"
        case .transparent: "Transparent"
        }
    }

    /// The kind backing an existing style.
    init(_ style: BackgroundStyle) {
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
        from previous: BackgroundStyle, imageStore: BackgroundImageStore
    )
        -> BackgroundStyle
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
            return .solid(.black)
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
/// add/remove for stops (CS-051). Keeps at least two stops so the gradient stays
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
            // Locale-neutral degree endpoints, shown verbatim (CS-047).
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
                    "Color stop \(index + 1)", selection: $stop.color, supportsOpacity: true
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
        let color = sorted.last?.color ?? .white
        gradient.stops.append(GradientStop(color: color, location: midpoint))
    }

    private func removeStop(_ stop: GradientStop) {
        guard gradient.stops.count > 2 else { return }
        gradient.stops.removeAll { $0.id == stop.id }
    }
}

/// Editor for an image background: the chosen image, a button to pick another,
/// and fit/blur/dimming controls (CS-051). Picking uses an `NSOpenPanel`
/// (user-selected access) and imports the file into the app container.
struct ImageBackgroundEditor: View {
    @Binding var image: ImageBackground
    var imageStore: BackgroundImageStore

    @State private var importError: String?

    var body: some View {
        Button {
            chooseImage()
        } label: {
            Label(hasImage ? "Replace image…" : "Choose image…", systemImage: "photo")
        }
        .accessibilityIdentifier("background-choose-image")

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
        panel.message = "Choose an image to use as the background."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let reference = try imageStore.importImage(from: url)
            image.reference = reference
            importError = nil
        } catch {
            importError = "That file could not be used as a background image."
        }
    }
}
