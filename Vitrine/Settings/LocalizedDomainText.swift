import Foundation
import VitrineDomain

// The domain modules carry no String Catalog, so user-facing copy for their values is
// resolved here.

extension ExportFormat {
    var localizedSummary: String {
        switch self {
        case .png:
            String(localized: "Raster image at the chosen resolution. Best for posting and chat.")
        case .pdf:
            String(localized: "Scalable vector document. Best for docs, slides, and print.")
        case .heic:
            String(
                localized:
                    "Compressed raster image, much smaller than PNG. Best for docs sites.")
        case .avif:
            String(
                localized: "Modern compressed raster image with alpha. Best for web publishing.")
        }
    }
}

extension ColorProfile {
    var localizedSummary: String {
        switch self {
        case .sRGB:
            String(
                localized: "Best for the web, Slack, X, and slides. Looks the same everywhere.")
        case .displayP3:
            String(
                localized:
                    "Wider gamut for P3 displays. Can oversaturate in apps that ignore the profile."
            )
        }
    }
}

extension ExportPreset {
    var localizedSummary: String {
        switch id {
        case "twitter": String(localized: "1600×900 (16:9) in-stream card.")
        case "linkedin": String(localized: "1200×628 (1.91:1) feed image.")
        case "keynote": String(localized: "1920×1080 (16:9) slide with generous padding.")
        case "docs": String(localized: "1200×800 (3:2) image for inline docs and blog posts.")
        case "transparent-slide":
            String(localized: "1920×1080 (16:9) transparent layer for any slide.")
        case "opengraph": String(localized: "Exact 1200×630 link-preview card at 1×.")
        case "instagram-story": String(localized: "1080×1920 (9:16) vertical story.")
        case "github-banner": String(localized: "1280×640 (2:1) README header image.")
        default: summary
        }
    }
}

extension StylePresetDocument.ImportError {
    var localizedMessage: String {
        switch self {
        case .notAPresetFile:
            String(localized: "This file is not a Vitrine preset file.")
        case .unsupportedSchemaVersion(let version):
            String(
                localized:
                    "This preset file uses a newer format (version \(version)) this app can't read."
            )
        case .empty:
            String(localized: "This preset file does not contain any presets.")
        case .fileTooLarge:
            String(localized: "This preset file is larger than 1 MB and was not read.")
        case .tooManyPresets:
            String(localized: "This preset file contains more than 1,000 presets.")
        }
    }
}

extension CustomThemeDocument.ImportError {
    var localizedMessage: String {
        switch self {
        case .notAThemeFile:
            String(localized: "This file is not a Vitrine theme file.")
        case .unsupportedSchemaVersion(let version):
            String(
                localized:
                    "This theme file uses a newer format (version \(version)) this app can't read."
            )
        case .invalidPalette(let error):
            error.localizedMessage
        case .empty:
            String(localized: "This theme file does not contain any themes.")
        case .fileTooLarge:
            String(localized: "This theme file is larger than 1 MB and was not read.")
        case .tooManyThemes:
            String(localized: "This theme file contains more than 1,000 themes.")
        }
    }
}

extension ThemePalette.ValidationError {
    var localizedMessage: String {
        switch self {
        case .missingKey(let key):
            String(localized: "The theme is missing the required \"\(key)\" color.")
        case .invalidColor(let key, let value):
            String(
                localized:
                    "The \"\(key)\" color \"\(value)\" is not a valid hex color (e.g. \"#1E1E1E\")."
            )
        }
    }
}

extension WorkspaceRecipeDocument.ValidationError {
    var localizedMessage: String {
        switch self {
        case .emptyName:
            String(localized: "The recipe name cannot be empty.")
        case .unknownDestinationPreset(let id):
            String(localized: "The recipe uses an unknown destination preset \"\(id)\".")
        case .unknownTheme(let id):
            String(
                localized:
                    "The recipe uses an unknown theme \"\(id)\" without embedding its palette.")
        case .unusedCustomTheme(let id):
            String(localized: "The recipe embeds custom theme \"\(id)\" but does not use it.")
        case .customThemeIDMismatch(let expected, let actual):
            String(
                localized:
                    "The recipe theme id \"\(expected)\" does not match embedded theme \"\(actual)\"."
            )
        case .invalidScale(let scale):
            String(localized: "The recipe export scale \(scale) must be between 1 and 3.")
        case .invalidCanvasSize(let width, let height):
            String(
                localized:
                    "The recipe canvas \(width)x\(height) must use dimensions between 64 and 2048."
            )
        }
    }
}

extension WorkspaceRecipeDocument.ImportError {
    var localizedMessage: String {
        switch self {
        case .notARecipeFile:
            String(localized: "This file is not a Vitrine workspace recipe.")
        case .unsupportedSchemaVersion(let version):
            String(
                localized: "This workspace recipe uses unsupported schema version \(version).")
        case .unknownField(let path):
            String(localized: "The workspace recipe contains unknown field \"\(path)\".")
        case .invalidDocument(let detail):
            String(localized: "The workspace recipe is invalid: \(detail)")
        case .invalid(let error):
            error.localizedMessage
        }
    }
}

extension WorkspaceRecipeFile.ReadError {
    var localizedMessage: String {
        switch self {
        case .unreadable:
            String(localized: "The workspace recipe could not be read.")
        case .tooLarge:
            String(localized: "The workspace recipe is larger than 1 MB and was not read.")
        case .invalid(let error):
            error.localizedMessage
        }
    }
}
