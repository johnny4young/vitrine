import Foundation

/// Reads the one recipe file explicitly named by a CLI invocation.
///
/// The loader never searches parent folders, Git metadata, or Application Support.
/// It also bounds the file before decoding so a mistaken large input cannot make a
/// lightweight render command allocate arbitrary JSON data.
enum CLIRecipeLoader {
    static let maximumByteCount = WorkspaceRecipeFile.maximumByteCount

    static func load(path: String) throws -> WorkspaceRecipe {
        let url = URL(fileURLWithPath: path)
        do {
            return try WorkspaceRecipeFile.load(from: url)
        } catch let error as WorkspaceRecipeFile.ReadError {
            switch error {
            case .unreadable:
                throw CLIError.recipeUnreadable(path: path)
            case .tooLarge:
                throw CLIError.invalidRecipe(error.message)
            case .invalid(let importError):
                throw CLIError.invalidRecipe(importError.message)
            }
        }
    }
}
