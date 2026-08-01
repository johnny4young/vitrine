import Foundation

/// Reads the one recipe file explicitly named by a CLI invocation.
///
/// The loader never searches parent folders, Git metadata, or Application Support.
/// It also bounds the file before decoding so a mistaken large input cannot make a
/// lightweight render command allocate arbitrary JSON data.
enum CLIRecipeLoader {
    static let maximumByteCount = 1_048_576

    static func load(path: String) throws -> WorkspaceRecipe {
        let url = URL(fileURLWithPath: path)
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw CLIError.recipeUnreadable(path: path)
        }
        guard values.isRegularFile == true,
            let fileSize = values.fileSize,
            fileSize <= maximumByteCount
        else {
            if let fileSize = values.fileSize, fileSize > maximumByteCount {
                throw CLIError.invalidRecipe(
                    "The workspace recipe is larger than 1 MB and was not read.")
            }
            throw CLIError.recipeUnreadable(path: path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw CLIError.recipeUnreadable(path: path)
        }
        do {
            return try WorkspaceRecipeDocument.recipe(from: data)
        } catch let error as WorkspaceRecipeDocument.ImportError {
            throw CLIError.invalidRecipe(error.message)
        } catch {
            throw CLIError.invalidRecipe("The workspace recipe could not be decoded.")
        }
    }
}
