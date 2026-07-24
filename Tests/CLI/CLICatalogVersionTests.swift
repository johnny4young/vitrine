import Foundation
import Testing

@testable import Vitrine

/// Stable version and catalog invocation, text, JSON, and project-metadata contracts.
@Suite("CLI version and catalog")
struct CLICatalogVersionTests: CLITestSupport {
    @Test func versionInvocationAcceptsTopLevelCommandsAndJson() {
        #expect(CLIVersion.invocation(for: ["--version"]) == .version(format: .text))
        #expect(CLIVersion.invocation(for: ["-v"]) == .version(format: .text))
        #expect(CLIVersion.invocation(for: ["version"]) == .version(format: .text))
        #expect(CLIVersion.invocation(for: ["version", "--json"]) == .version(format: .json))
        #expect(CLIVersion.invocation(for: ["--version", "--json"]) == .version(format: .json))
        #expect(CLIVersion.invocation(for: ["version", "--help"]) == .help)
        #expect(CLIVersion.invocation(for: ["version", "--bad"]) == .unknownFlag("--bad"))
        #expect(CLIVersion.invocation(for: ["version", "extra"]) == .extraArguments(["extra"]))
        #expect(CLIVersion.invocation(for: ["render"]) == nil)
    }

    @Test func versionOutputUsesBundleValuesAndFallbackConstants() throws {
        let output = CLIVersion.output(
            format: .text,
            infoDictionary: ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "456"],
            executablePath: "/missing/vitrine-cli")
        #expect(output == "vitrine 1.2.3 (456)\n")

        let jsonData = Data(
            CLIVersion.output(
                format: .json,
                infoDictionary: [
                    "CFBundleShortVersionString": "1.2.3",
                    "CFBundleVersion": "456",
                ],
                executablePath: "/missing/vitrine-cli"
            ).utf8)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: jsonData) as? [String: String])
        #expect(decoded == ["build": "456", "product": "vitrine", "version": "1.2.3"])

        let fallback = CLIVersion.output(
            format: .text, infoDictionary: [:], executablePath: "/missing/vitrine-cli")
        #expect(fallback == "vitrine 0.24.0 (25)\n")
    }

    @Test func versionFallbackConstantsMatchProjectSettings() throws {
        let project = try String(contentsOf: repoFile("project.yml"), encoding: .utf8)
        #expect(project.contains("MARKETING_VERSION: \"\(CLIVersion.fallbackMarketingVersion)\""))
        #expect(project.contains("CURRENT_PROJECT_VERSION: \"\(CLIVersion.fallbackBuildNumber)\""))
    }

    // MARK: - Catalog listing

    @Test func catalogListInvocationAcceptsTextJsonAndSingularAliases() {
        #expect(CLICatalog.invocation(for: ["all"]) == .listing(.all, format: .text))
        #expect(CLICatalog.invocation(for: ["all", "--json"]) == .listing(.all, format: .json))
        #expect(CLICatalog.invocation(for: ["themes"]) == .listing(.themes, format: .text))
        #expect(
            CLICatalog.invocation(for: ["theme", "--json"]) == .listing(.themes, format: .json))
        #expect(
            CLICatalog.invocation(for: ["--json", "language"])
                == .listing(.languages, format: .json))
        #expect(CLICatalog.invocation(for: ["preset"]) == .listing(.presets, format: .text))
        #expect(
            CLICatalog.invocation(for: ["style-preset"])
                == .listing(.stylePresets, format: .text))
        #expect(CLICatalog.invocation(for: ["font"]) == .listing(.fonts, format: .text))
        #expect(
            CLICatalog.invocation(for: ["backgrounds"])
                == .listing(.backgrounds, format: .text))
        #expect(
            CLICatalog.invocation(for: ["background-fit"])
                == .listing(.backgroundFits, format: .text))
        #expect(CLICatalog.invocation(for: ["frame"]) == .listing(.frames, format: .text))
        #expect(
            CLICatalog.invocation(for: ["frame-appearances", "--json"])
                == .listing(.frameAppearances, format: .json))
        #expect(
            CLICatalog.invocation(for: ["watermark-position"])
                == .listing(.watermarkPositions, format: .text))
        #expect(CLICatalog.invocation(for: ["format"]) == .listing(.formats, format: .text))
        #expect(CLICatalog.invocation(for: ["profiles"]) == .listing(.profiles, format: .text))
        #expect(CLICatalog.invocation(for: []) == .help)
    }

    @Test func catalogListRejectsUnknownTargetsFlagsAndExtraArguments() {
        #expect(CLICatalog.invocation(for: ["colors"]) == .unknownCatalog("colors"))
        #expect(CLICatalog.invocation(for: ["themes", "--bad"]) == .unknownFlag("--bad"))
        #expect(
            CLICatalog.invocation(for: ["themes", "languages"]) == .extraArguments(["languages"]))
    }

    @Test func catalogListPrintsStableTextAndJsonFromTheModelCatalogs() throws {
        let themeText = CLICatalog.output(for: .themes, format: .text)
        #expect(themeText.contains("dracula\tDracula\n"))
        #expect(themeText.contains("one-dark\tOne Dark\n"))

        let presetText = CLICatalog.output(for: .presets, format: .text)
        #expect(presetText.contains("opengraph\tOpenGraph 1200×630\n"))
        #expect(presetText.contains("transparent-slide\tTransparent Slide\n"))

        let stylePresetText = CLICatalog.output(for: .stylePresets, format: .text)
        #expect(
            stylePresetText
                == "builtin.aurora\tAurora\nbuiltin.midnight\tMidnight\nbuiltin.sunset\tSunset\nbuiltin.minimal\tMinimal Light\n"
        )

        let formatText = CLICatalog.output(for: .formats, format: .text)
        #expect(formatText == "png\tPNG\npdf\tPDF\nheic\tHEIC\navif\tAVIF\n")

        let profileText = CLICatalog.output(for: .profiles, format: .text)
        #expect(profileText == "srgb\tsRGB\np3\tDisplay P3 (advanced)\n")

        let fontText = CLICatalog.output(for: .fonts, format: .text)
        #expect(fontText.contains("JetBrains Mono\tJetBrains Mono\n"))
        #expect(fontText.contains("Fira Code\tFira Code\n"))

        let backgroundText = CLICatalog.output(for: .backgrounds, format: .text)
        #expect(
            backgroundText
                == "aurora\tAurora\nocean\tOcean\nsunset\tSunset\nforest\tForest\nnight\tNight\ncarbon\tCarbon\n"
        )

        let backgroundFitText = CLICatalog.output(for: .backgroundFits, format: .text)
        #expect(backgroundFitText == "fill\tFill\nfit\tFit\n")

        let watermarkPositionText = CLICatalog.output(for: .watermarkPositions, format: .text)
        #expect(
            watermarkPositionText
                == "bottom-right\tBottom right\nbottom-left\tBottom left\ntop-right\tTop right\ntop-left\tTop left\nfree\tFree\n"
        )

        let frameText = CLICatalog.output(for: .frames, format: .text)
        #expect(
            frameText
                == "none\tNone\nmacos-window\tmacOS window\nbrowser\tBrowser\nmacbook\tMacBook\niphone\tiPhone\n"
        )

        let appearanceText = CLICatalog.output(for: .frameAppearances, format: .text)
        #expect(appearanceText == "auto\tAuto\nlight\tLight\ndark\tDark\n")

        let data = Data(CLICatalog.output(for: .languages, format: .json).utf8)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: data) as? [[String: String]])
        #expect(decoded.contains { $0["id"] == "swift" && $0["name"] == "Swift" })
        #expect(decoded.contains { $0["id"] == "terminal" && $0["name"] == "Terminal" })

        let profileData = Data(CLICatalog.output(for: .profiles, format: .json).utf8)
        let profiles = try #require(
            JSONSerialization.jsonObject(with: profileData) as? [[String: String]])
        #expect(profiles.contains { $0["id"] == "srgb" && $0["name"] == "sRGB" })
        #expect(profiles.contains { $0["id"] == "p3" && $0["name"] == "Display P3 (advanced)" })
    }

    @Test func catalogListAllPrintsEveryCatalogAsTextAndJson() throws {
        let allText = CLICatalog.output(for: .all, format: .text)
        #expect(allText.contains("themes:\n"))
        #expect(allText.contains("  one-dark\tOne Dark\n"))
        #expect(allText.contains("languages:\n"))
        #expect(allText.contains("  swift\tSwift\n"))
        #expect(allText.contains("style-presets:\n  builtin.aurora\tAurora\n"))
        #expect(allText.contains("fonts:\n  JetBrains Mono\tJetBrains Mono\n"))
        #expect(allText.contains("backgrounds:\n  aurora\tAurora\n"))
        #expect(allText.contains("background-fits:\n  fill\tFill\n"))
        #expect(allText.contains("frames:\n  none\tNone\n"))
        #expect(allText.contains("frame-appearances:\n  auto\tAuto\n"))
        #expect(allText.contains("watermark-positions:\n  bottom-right\tBottom right\n"))
        #expect(allText.contains("formats:\n  png\tPNG\n"))
        #expect(allText.contains("profiles:\n  srgb\tsRGB\n"))

        let data = Data(CLICatalog.output(for: .all, format: .json).utf8)
        let decoded = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let themes = try #require(decoded["themes"] as? [[String: String]])
        let languages = try #require(decoded["languages"] as? [[String: String]])
        let presets = try #require(decoded["presets"] as? [[String: String]])
        let stylePresets = try #require(decoded["stylePresets"] as? [[String: String]])
        let fonts = try #require(decoded["fonts"] as? [[String: String]])
        let backgrounds = try #require(decoded["backgrounds"] as? [[String: String]])
        let backgroundFits = try #require(decoded["backgroundFits"] as? [[String: String]])
        let frames = try #require(decoded["frames"] as? [[String: String]])
        let frameAppearances = try #require(
            decoded["frameAppearances"] as? [[String: String]])
        let watermarkPositions = try #require(
            decoded["watermarkPositions"] as? [[String: String]])
        let formats = try #require(decoded["formats"] as? [[String: String]])
        let profiles = try #require(decoded["profiles"] as? [[String: String]])
        #expect(themes.contains { $0["id"] == "one-dark" })
        #expect(languages.contains { $0["id"] == "swift" })
        #expect(presets.contains { $0["id"] == "opengraph" })
        #expect(
            stylePresets.contains {
                $0["id"] == "builtin.minimal" && $0["name"] == "Minimal Light"
            })
        #expect(fonts.contains { $0["id"] == "Fira Code" && $0["name"] == "Fira Code" })
        #expect(backgrounds.contains { $0["id"] == "aurora" && $0["name"] == "Aurora" })
        #expect(backgroundFits.contains { $0["id"] == "fit" && $0["name"] == "Fit" })
        #expect(frames.contains { $0["id"] == "macos-window" && $0["name"] == "macOS window" })
        #expect(frameAppearances.contains { $0["id"] == "dark" && $0["name"] == "Dark" })
        #expect(
            watermarkPositions.contains {
                $0["id"] == "top-left" && $0["name"] == "Top left"
            })
        #expect(formats.contains { $0["id"] == "png" })
        #expect(profiles.contains { $0["id"] == "p3" })
    }
}
