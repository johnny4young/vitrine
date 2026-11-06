import SwiftUI
import VitrineDomain
import VitrineRendering

/// One card per association, showing the recipe's look on the sample snippet.
///
/// Recipe files are read when the associations change and previews render one per frame,
/// skipping any whose inputs are unchanged, so a body pass never reads a file or renders.
@Observable
final class RecipeGalleryModel {
    struct Card: Identifiable, Equatable {
        let association: WorkspaceRecipeAssociation
        /// `nil` when the file is missing or no longer a valid recipe.
        let recipe: WorkspaceRecipe?
        /// The recipe of the closest enclosing folder, which this one wins over.
        var overrides: String?
        /// Recipes of nested folders, which win over this one inside them.
        var nested: [String] = []

        var id: UUID { association.id }
        var name: String { recipe?.name ?? association.recipeFilename }
    }

    /// Wider than the preset tiles, so a few cards don't push Manage below the fold.
    static let tileAspect: CGFloat = 2.4
    static let pixelSize = CGSize(width: 384, height: 384 / tileAspect)

    private(set) var cards: [Card] = []
    private(set) var images: [UUID: CGImage] = [:]

    @ObservationIgnored private var renderedConfigs: [UUID: SnapshotConfig] = [:]
    private let frameGap: Duration
    private let render: (SnapshotConfig) -> CGImage?

    init(
        frameGap: Duration = .milliseconds(16),
        render: @escaping (SnapshotConfig) -> CGImage? = {
            ExportManager.renderThumbnail($0, pixels: RecipeGalleryModel.pixelSize)
        }
    ) {
        self.frameGap = frameGap
        self.render = render
    }

    func reload(from store: WorkspaceRecipeStore) {
        let parents = store.enclosingAssociationIDs()
        let loaded = store.associations.map { association in
            let resolved = try? store.resolvedRecipe(id: association.id)
            return Card(association: resolved?.association ?? association, recipe: resolved?.recipe)
        }
        let names = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0.name) })
        let updated = loaded.map { card in
            var card = card
            card.overrides = parents[card.id].flatMap { names[$0] }
            card.nested = loaded.filter { parents[$0.id] == card.id }.map(\.name)
            return card
        }
        if updated != cards { cards = updated }
    }

    func renderPreviews() async {
        let live = Set(cards.compactMap { $0.recipe == nil ? nil : $0.id })
        if images.keys.contains(where: { !live.contains($0) }) {
            images = images.filter { live.contains($0.key) }
        }
        renderedConfigs = renderedConfigs.filter { live.contains($0.key) }
        for card in cards {
            guard let recipe = card.recipe else { continue }
            let config = Self.previewConfig(for: recipe)
            guard renderedConfigs[card.id] != config else { continue }
            guard !Task.isCancelled else { return }
            images[card.id] = render(config)
            renderedConfigs[card.id] = config
            try? await Task.sleep(for: frameGap)
        }
    }

    /// The same snippet for every card, so only the recipe's style differs.
    static func previewConfig(for recipe: WorkspaceRecipe) -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = EditorPreview.sampleCode
        config.language = .swift
        recipe.style.apply(to: &config, resolvingThemeWith: recipe.theme(withID:))
        return config
    }

    /// Values as the JSON spells them, so a chip matches what the file and the CLI say.
    static func chips(for recipe: WorkspaceRecipe) -> [String] {
        let output = recipe.output
        var chips = [recipe.style.themeID]
        if let destination = output.destinationPresetID { chips.append(destination) }
        if let size = output.canvasSize { chips.append("\(size.width)×\(size.height)") }
        if let format = output.format { chips.append(format.rawValue) }
        if let profile = output.colorProfile { chips.append(profile.rawValue) }
        if let scale = output.scale { chips.append("\(scale)×") }
        return chips
    }
}

struct WorkspaceRecipeGallery: View {
    var store: WorkspaceRecipeStore
    @Binding var selection: UUID?

    @State private var model = RecipeGalleryModel()

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 2),
            spacing: 8
        ) {
            ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
                RecipeCard(
                    card: card, image: model.images[card.id], isSelected: selection == card.id
                ) {
                    selection = card.id
                }
                .accessibilityIdentifier("workspace-recipe-card-\(index)")
            }
        }
        .padding(.vertical, VitrineTokens.Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace-recipe-gallery")
        .task(id: store.associations) {
            model.reload(from: store)
            await model.renderPreviews()
        }
    }
}

private struct RecipeCard: View {
    let card: RecipeGalleryModel.Card
    let image: CGImage?
    let isSelected: Bool
    let action: () -> Void

    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                preview
                Text(verbatim: card.name)
                    .font(.system(size: VitrineTokens.FontSize.subhead, weight: .semibold))
                    .foregroundStyle(VitrineTokens.Text.primary)
                    .lineLimit(1)
                if let recipe = card.recipe {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(RecipeGalleryModel.chips(for: recipe), id: \.self) { chip in
                            Text(verbatim: chip)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(VitrineTokens.Text.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(VitrineTokens.Chrome.segmentTrack))
                        }
                    }
                } else {
                    Text("Unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(VitrineTokens.Text.secondary)
                }
                folder
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.shape.fill(VitrineTokens.Surface.card))
            .overlay(
                Self.shape
                    .strokeBorder(
                        isSelected ? VitrineTokens.Accent.system : VitrineTokens.Line.border,
                        lineWidth: isSelected ? 2 : Brand.Stroke.hairline
                    )
                    .allowsHitTesting(false)
            )
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var preview: some View {
        Color.clear
            .aspectRatio(RecipeGalleryModel.tileAspect, contentMode: .fit)
            .background(VitrineTokens.Surface.inset)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if card.recipe == nil {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    /// Nested folders win over their parent, so both cards say which side they're on.
    private var folder: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .accessibilityHidden(true)
            Text(verbatim: card.association.workspaceName)
            if let parent = card.overrides {
                Text("· overrides \(parent)")
            } else if !card.nested.isEmpty {
                Text("· parent of \(card.nested.formatted(.list(type: .and)))")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(VitrineTokens.Text.tertiary)
        .lineLimit(1)
        .truncationMode(.tail)
        .help(
            card.overrides != nil || !card.nested.isEmpty
                ? Text("A file in a nested folder uses that folder's recipe.") : Text(verbatim: ""))
    }
}

#if DEBUG
    extension RecipeGalleryModel {
        /// Writes sample recipes into the app's temporary folder and associates them,
        /// with one folder nested in another, for screenshots and UI tests.
        static func seedDemo(in store: WorkspaceRecipeStore) {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("VitrineRecipeGalleryDemo", isDirectory: true)
            let samples: [(folder: String, file: String, recipe: WorkspaceRecipe)] = [
                (
                    "weather-app", "pr-review.vitrine-recipe.json",
                    WorkspaceRecipe(
                        name: "PR review",
                        style: StyleSnapshot(
                            themeID: Theme.githubDark.id, background: .gradient(.night)),
                        output: .init(destinationPresetID: "docs", scale: 2, format: .png))
                ),
                (
                    "weather-app/docs", "documentation.vitrine-recipe.json",
                    WorkspaceRecipe(
                        name: "Documentation",
                        style: StyleSnapshot(themeID: Theme.nord.id, background: .gradient(.ocean)),
                        output: .init(
                            destinationPresetID: "opengraph", format: .png, colorProfile: .sRGB))
                ),
                (
                    "release-notes", "release-notes.vitrine-recipe.json",
                    WorkspaceRecipe(
                        name: "Release notes",
                        style: StyleSnapshot(
                            themeID: Theme.dracula.id, background: .gradient(.sunset)),
                        output: .init(
                            canvasSize: .init(width: 1600, height: 900), scale: 2, format: .png,
                            colorProfile: .displayP3))
                ),
            ]
            for sample in samples {
                let folder = root.appendingPathComponent(sample.folder, isDirectory: true)
                let file = root.appendingPathComponent(sample.file)
                try? FileManager.default.createDirectory(
                    at: folder, withIntermediateDirectories: true)
                try? WorkspaceRecipeDocument(recipe: sample.recipe).jsonData().write(to: file)
                _ = try? store.associate(workspaceURL: folder, recipeURL: file)
            }
        }
    }
#endif
