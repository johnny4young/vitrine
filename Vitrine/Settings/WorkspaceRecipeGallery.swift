import SwiftUI
import VitrineDomain
import VitrineRendering

/// One card per association, showing the recipe's look on the sample snippet.
///
/// Recipe files are read off the main actor, without writing back to the store, and previews
/// render one per frame, skipping unchanged ones, so a body pass never reads a file or renders.
@Observable
final class RecipeGalleryModel {
    /// What the loader needs from an association, copied so it can leave the main actor.
    nonisolated struct Entry: Equatable, Sendable {
        let id: UUID
        let workspaceBookmark: Data
        let recipeBookmark: Data
        let workspaceName: String
        let recipeFilename: String
    }

    nonisolated struct Card: Identifiable, Equatable, Sendable {
        let id: UUID
        /// From the resolved bookmark, so a renamed folder or file shows its new name.
        let workspaceName: String
        let recipeFilename: String
        /// `nil` when the file is missing or no longer a valid recipe.
        let recipe: WorkspaceRecipe?
        /// The recipe of the closest enclosing folder, which this one wins over.
        var overrides: String?
        /// Recipes of nested folders, which win over this one inside them.
        var nested: [String] = []

        var name: String { recipe?.name ?? recipeFilename }
    }

    /// A card and its folder's path components, `nil` when it can't take part in nesting.
    nonisolated struct Located: Sendable {
        var card: Card
        var folder: [String]?
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

    static func entries(_ associations: [WorkspaceRecipeAssociation]) -> [Entry] {
        associations.map {
            Entry(
                id: $0.id, workspaceBookmark: $0.workspaceBookmark,
                recipeBookmark: $0.recipeBookmark, workspaceName: $0.workspaceName,
                recipeFilename: $0.recipeFilename)
        }
    }

    /// Applies the loaded cards unless the caller was cancelled while they loaded.
    func reload(_ entries: [Entry]) async {
        let loaded = await Self.load(entries)
        guard !Task.isCancelled else { return }
        update(loaded)
    }

    func update(_ updated: [Card]) {
        if updated != cards { cards = updated }
        let live = Set(cards.compactMap { $0.recipe == nil ? nil : $0.id })
        if images.keys.contains(where: { !live.contains($0) }) {
            images = images.filter { live.contains($0.key) }
        }
        renderedConfigs = renderedConfigs.filter { live.contains($0.key) }
    }

    func renderPreviews() async {
        for card in cards {
            guard let recipe = card.recipe else { continue }
            let config = Self.previewConfig(for: recipe)
            guard renderedConfigs[card.id] != config, isShown(card.id, recipe) else { continue }
            guard !Task.isCancelled else { return }
            let image = render(config)
            // The list can change while a preview renders; never store one it no longer shows.
            guard !Task.isCancelled, isShown(card.id, recipe) else { continue }
            images[card.id] = image
            renderedConfigs[card.id] = config
            try? await Task.sleep(for: frameGap)
        }
    }

    private func isShown(_ id: UUID, _ recipe: WorkspaceRecipe) -> Bool {
        cards.contains { $0.id == id && $0.recipe == recipe }
    }

    /// Resolves each bookmark once, without mounting a volume, and never refreshes a stale
    /// bookmark, so showing the gallery doesn't write to the store.
    @concurrent
    nonisolated static func load(_ entries: [Entry]) async -> [Card] {
        var located: [Located] = []
        for entry in entries {
            if Task.isCancelled { return [] }
            let workspace = resolve(entry.workspaceBookmark)
            let file = resolve(entry.recipeBookmark)
            var recipe: WorkspaceRecipe?
            if let file {
                let accessed = file.startAccessingSecurityScopedResource()
                recipe = try? WorkspaceRecipeFile.load(from: file)
                if accessed { file.stopAccessingSecurityScopedResource() }
            }
            let card = Card(
                id: entry.id,
                workspaceName: workspace.flatMap(displayName) ?? entry.workspaceName,
                recipeFilename: file.flatMap(displayName) ?? entry.recipeFilename,
                recipe: recipe)
            let folder = workspace?.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            located.append(Located(card: card, folder: recipe == nil ? nil : folder))
        }
        return related(located)
    }

    /// Nesting among the cards whose recipe loaded: a drop skips an unavailable nested recipe
    /// and uses its parent, so a broken card neither overrides nor is overridden.
    nonisolated static func related(_ located: [Located]) -> [Card] {
        let folders = located.compactMap { item in item.folder.map { (item.card.id, $0) } }
        var parents: [UUID: UUID] = [:]
        for (id, folder) in folders {
            let closest = folders.filter { $0.1.count < folder.count && folder.starts(with: $0.1) }
                .max { $0.1.count < $1.1.count }
            if let closest { parents[id] = closest.0 }
        }
        let names = Dictionary(located.map { ($0.card.id, $0.card.name) }) { first, _ in first }
        return located.map { item in
            var card = item.card
            card.overrides = parents[card.id].flatMap { names[$0] }
            card.nested = located.filter { parents[$0.card.id] == card.id }.map(\.card.name)
            return card
        }
    }

    private nonisolated static func resolve(_ bookmark: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    private nonisolated static func displayName(_ url: URL) -> String? {
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
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
        .task(id: RecipeGalleryModel.entries(store.associations)) {
            await model.reload(RecipeGalleryModel.entries(store.associations))
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
            Text(verbatim: card.workspaceName)
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
