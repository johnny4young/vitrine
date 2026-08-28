import Foundation

/// Bounded, platform-neutral file loading for one portable workspace recipe.
///
/// Callers own authorization: the CLI receives an explicit path, while the app
/// brackets user-selected URLs with security-scoped access. Centralizing the file
/// checks keeps both surfaces on the same size and schema contract without coupling
/// the app store to CLI-specific errors.
enum WorkspaceRecipeFile {
    static let maximumByteCount = 1_048_576

    enum ReadError: Error, Equatable {
        case unreadable
        case tooLarge
        case invalid(WorkspaceRecipeDocument.ImportError)

        var message: String {
            switch self {
            case .unreadable:
                "The workspace recipe could not be read."
            case .tooLarge:
                "The workspace recipe is larger than 1 MB and was not read."
            case .invalid(let error):
                error.message
            }
        }
    }

    static func load(from url: URL) throws -> WorkspaceRecipe {
        let data: Data
        do {
            data = try BoundedFileReader.read(from: url, limit: maximumByteCount)
        } catch BoundedFileReader.ReadError.tooLarge {
            throw ReadError.tooLarge
        } catch {
            throw ReadError.unreadable
        }
        do {
            return try WorkspaceRecipeDocument.recipe(from: data)
        } catch let error as WorkspaceRecipeDocument.ImportError {
            throw ReadError.invalid(error)
        } catch {
            throw ReadError.invalid(.notARecipeFile)
        }
    }
}
