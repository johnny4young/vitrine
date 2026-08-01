import Foundation
import OSLog
import Observation

/// A machine-local association between one folder and one portable recipe file.
///
/// Only security-scoped bookmark bytes and display names persist. Absolute paths
/// never enter the portable recipe, logs, diagnostics, or exported JSON. The source
/// file is matched only after the user explicitly drops it into Vitrine.
struct WorkspaceRecipeAssociation: Codable, Equatable, Identifiable {
    var id: UUID
    var workspaceBookmark: Data
    var recipeBookmark: Data
    var workspaceName: String
    var recipeFilename: String
}

/// Owns local folder-to-recipe associations and resolves them on explicit file input.
@Observable
final class WorkspaceRecipeStore {
    static var shared: WorkspaceRecipeStore { AppEnvironment.shared.workspaceRecipes }
    static let storageKey = "workspaceRecipeAssociations"

    struct ResolvedRecipe: Equatable {
        var association: WorkspaceRecipeAssociation
        var recipe: WorkspaceRecipe
    }

    enum StoreError: Error, Equatable {
        case workspaceIsNotFolder
        case recipe(WorkspaceRecipeFile.ReadError)
        case bookmarkCreationFailed
        case associationUnavailable

        var message: String {
            switch self {
            case .workspaceIsNotFolder:
                "Choose a folder or repository for this association."
            case .recipe(let error):
                error.message
            case .bookmarkCreationFailed:
                "Vitrine could not retain access to that folder or recipe file."
            case .associationUnavailable:
                "The associated folder or recipe is no longer available. Add it again to renew access."
            }
        }
    }

    private(set) var associations: [WorkspaceRecipeAssociation] {
        didSet {
            guard !isReloading else { return }
            persist()
        }
    }

    private let defaults: UserDefaults
    private var isReloading = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        associations = Self.readAssociations(from: defaults)
    }

    /// Adds or replaces the association for one explicitly chosen workspace.
    @discardableResult
    func associate(workspaceURL: URL, recipeURL: URL) throws -> WorkspaceRecipeAssociation {
        let workspaceAccessed = workspaceURL.startAccessingSecurityScopedResource()
        defer { if workspaceAccessed { workspaceURL.stopAccessingSecurityScopedResource() } }
        let recipeAccessed = recipeURL.startAccessingSecurityScopedResource()
        defer { if recipeAccessed { recipeURL.stopAccessingSecurityScopedResource() } }

        let values = try? workspaceURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else { throw StoreError.workspaceIsNotFolder }
        do {
            _ = try WorkspaceRecipeFile.load(from: recipeURL)
        } catch let error as WorkspaceRecipeFile.ReadError {
            throw StoreError.recipe(error)
        } catch {
            throw StoreError.recipe(.unreadable)
        }

        let workspaceBookmark: Data
        let recipeBookmark: Data
        do {
            workspaceBookmark = try makeBookmark(for: workspaceURL)
            recipeBookmark = try makeBookmark(for: recipeURL)
        } catch {
            throw StoreError.bookmarkCreationFailed
        }

        let normalizedWorkspace = canonicalURL(workspaceURL)
        let existingIndex = associations.firstIndex { association in
            guard let url = try? resolve(association.workspaceBookmark).url else { return false }
            return canonicalURL(url) == normalizedWorkspace
        }
        let association = WorkspaceRecipeAssociation(
            id: existingIndex.map { associations[$0].id } ?? UUID(),
            workspaceBookmark: workspaceBookmark,
            recipeBookmark: recipeBookmark,
            workspaceName: displayName(for: workspaceURL, fallback: "Workspace"),
            recipeFilename: displayName(for: recipeURL, fallback: "Recipe"))
        if let existingIndex {
            associations[existingIndex] = association
        } else {
            associations.append(association)
        }
        Log.settings.info(
            "Saved a workspace recipe association (count \(self.associations.count, privacy: .public))"
        )
        return association
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        let previousCount = associations.count
        associations.removeAll { $0.id == id }
        return associations.count != previousCount
    }

    /// Loads one selected association for an explicit Apply action.
    func resolvedRecipe(id: UUID) throws -> ResolvedRecipe {
        guard let index = associations.firstIndex(where: { $0.id == id }) else {
            throw StoreError.associationUnavailable
        }
        return try resolvedRecipe(at: index)
    }

    /// Resolves the most-specific associated ancestor for a source file the user
    /// explicitly dropped. Unavailable nested associations fall through to
    /// a usable parent instead of blocking the source entirely.
    func resolvedRecipe(for sourceURL: URL) -> ResolvedRecipe? {
        let source = canonicalURL(sourceURL)
        let candidates = associations.indices.compactMap { index -> (Int, Int)? in
            guard let workspace = try? resolve(associations[index].workspaceBookmark).url,
                contains(source, within: canonicalURL(workspace))
            else { return nil }
            return (index, canonicalURL(workspace).pathComponents.count)
        }.sorted { lhs, rhs in lhs.1 > rhs.1 }

        for (index, _) in candidates {
            if let resolved = try? resolvedRecipe(at: index) { return resolved }
        }
        return nil
    }

    /// Applies the most-specific association for one explicit file input. Keeping
    /// this policy in the store makes editor drag-and-drop a thin adapter and keeps
    /// automatic application independently testable.
    @discardableResult
    func applyRecipe(for sourceURL: URL, to settings: AppSettings) -> ResolvedRecipe? {
        guard let resolved = resolvedRecipe(for: sourceURL) else { return nil }
        _ = settings.applyWorkspaceRecipe(resolved.recipe)
        return resolved
    }

    func reload() {
        let reloaded = Self.readAssociations(from: defaults)
        guard reloaded != associations else { return }
        isReloading = true
        defer { isReloading = false }
        associations = reloaded
    }

    private func resolvedRecipe(at index: Int) throws -> ResolvedRecipe {
        var association = associations[index]
        let workspaceResolution: BookmarkResolution
        let recipeResolution: BookmarkResolution
        do {
            workspaceResolution = try resolve(association.workspaceBookmark)
            recipeResolution = try resolve(association.recipeBookmark)
        } catch {
            throw StoreError.associationUnavailable
        }

        let workspaceAccessed = workspaceResolution.url.startAccessingSecurityScopedResource()
        defer {
            if workspaceAccessed { workspaceResolution.url.stopAccessingSecurityScopedResource() }
        }
        let recipeAccessed = recipeResolution.url.startAccessingSecurityScopedResource()
        defer { if recipeAccessed { recipeResolution.url.stopAccessingSecurityScopedResource() } }

        let recipe: WorkspaceRecipe
        do {
            recipe = try WorkspaceRecipeFile.load(from: recipeResolution.url)
        } catch let error as WorkspaceRecipeFile.ReadError {
            throw StoreError.recipe(error)
        } catch {
            throw StoreError.recipe(.unreadable)
        }

        var refreshed = false
        if workspaceResolution.isStale,
            let bookmark = try? makeBookmark(for: workspaceResolution.url)
        {
            association.workspaceBookmark = bookmark
            refreshed = true
        }
        if recipeResolution.isStale,
            let bookmark = try? makeBookmark(for: recipeResolution.url)
        {
            association.recipeBookmark = bookmark
            refreshed = true
        }
        if refreshed { associations[index] = association }
        return ResolvedRecipe(association: association, recipe: recipe)
    }

    private struct BookmarkResolution {
        var url: URL
        var isStale: Bool
    }

    private func resolve(_ data: Data) throws -> BookmarkResolution {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale)
        return BookmarkResolution(url: url, isStale: isStale)
    }

    private func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: [.isDirectoryKey, .isRegularFileKey],
            relativeTo: nil)
    }

    private func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func contains(_ source: URL, within workspace: URL) -> Bool {
        let sourceComponents = source.pathComponents
        let workspaceComponents = workspace.pathComponents
        guard sourceComponents.count > workspaceComponents.count else { return false }
        return sourceComponents.prefix(workspaceComponents.count).elementsEqual(workspaceComponents)
    }

    private func displayName(for url: URL, fallback: String) -> String {
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallback : name
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(associations), forKey: Self.storageKey)
        } catch {
            Log.settings.error("Failed to persist workspace recipe associations")
        }
    }

    private static func readAssociations(
        from defaults: UserDefaults
    ) -> [WorkspaceRecipeAssociation] {
        guard let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(
                [FailableDecodable<WorkspaceRecipeAssociation>].self, from: data)
        else { return [] }
        var seen = Set<UUID>()
        return decoded.compactMap(\.value).filter { association in
            !association.workspaceBookmark.isEmpty && !association.recipeBookmark.isEmpty
                && seen.insert(association.id).inserted
        }
    }
}
