import Foundation
import VitrineDomain

/// A named social-card layout with typed slots, filled from the command palette or a
/// `vitrine://card` link and drawn by the existing ``SocialCardModel`` renderer.
///
/// Slot values are plain local text: no slot is resolved as a file path or a URL, and
/// the accent picks a built-in gradient, so filling a template never reads or fetches
/// anything.
public struct CardTemplate: Identifiable, Equatable, Sendable {
    /// A typed value a template accepts.
    public enum Slot: String, CaseIterable, Sendable {
        case title, subtitle, code, language, handle, project, theme, accent

        /// Style slots every template accepts on top of its content slots.
        public static let styleSlots: [Slot] = [.theme, .accent]

        /// The longest accepted value, in characters, checked before trimming.
        public var maxLength: Int {
            switch self {
            case .title: 100
            case .subtitle: 160
            case .code: 2000
            case .handle, .project: 64
            case .language, .theme, .accent: 32
            }
        }

        /// Bounds combining-mark stacks that a character count alone lets through.
        public var maxScalars: Int { maxLength * 4 }
    }

    /// Why a template could not be filled.
    public enum FillError: Error, Equatable {
        case malformedLink
        case unknownTemplate
        case unsupportedSlot(String)
        case duplicateSlot(String)
        case invalidValue(Slot)

        /// A log-safe description: the case and slot, never a value from the link.
        public var logLabel: String {
            switch self {
            case .malformedLink: "malformedLink"
            case .unknownTemplate: "unknownTemplate"
            case .unsupportedSlot: "unsupportedSlot"
            case .duplicateSlot: "duplicateSlot"
            case .invalidValue(let slot): "invalidValue(\(slot.rawValue))"
            }
        }
    }

    public let id: String
    /// The renderer layout this template draws with.
    public let layout: SocialCardTemplate
    public let contentSlots: [Slot]

    public var slots: [Slot] { contentSlots + Slot.styleSlots }

    public var displayName: String {
        switch id {
        case "release": String(localized: "Release")
        case "snippet": String(localized: "Snippet")
        default: String(localized: "Announcement")
        }
    }

    public static let release = CardTemplate(
        id: "release", layout: .standard,
        contentSlots: [.title, .subtitle, .code, .language, .handle, .project])
    public static let snippet = CardTemplate(
        id: "snippet", layout: .codeFocus,
        contentSlots: [.title, .subtitle, .code, .language, .handle, .project])
    public static let announcement = CardTemplate(
        id: "announcement", layout: .headline,
        contentSlots: [.title, .subtitle, .handle, .project])

    public static let builtIns: [CardTemplate] = [release, snippet, announcement]

    public static func named(_ id: String) -> CardTemplate? {
        builtIns.first { $0.id == id }
    }
}

extension CardTemplate {
    /// Slot values for one template. Untrusted input goes through the validating
    /// initializer; a blank value counts as absent.
    public struct Fill: Equatable, Sendable {
        public let template: CardTemplate
        public private(set) var values: [Slot: String]

        public init(template: CardTemplate, values: [Slot: String]) throws {
            self.template = template
            self.values = [:]
            for (slot, raw) in values {
                guard template.slots.contains(slot) else {
                    throw FillError.unsupportedSlot(slot.rawValue)
                }
                if let value = try Self.validated(raw, for: slot) { self.values[slot] = value }
            }
        }

        /// The palette's fill: the card's own copy carried into `template`, with the
        /// editor's code when it has some. Terminal output becomes plain text.
        public init(template: CardTemplate, card: SocialCardModel, editor: SnapshotConfig) {
            var source = card
            let excerpt = SocialCardModel.truncatedExcerpt(editor.sidecarText)
            if !excerpt.isEmpty {
                source.codeExcerpt = excerpt
                source.language = editor.language == .terminal ? .plaintext : editor.language
            }
            self.init(template: template, carrying: source)
        }

        /// Local, already normalized card data, so it is not re-validated.
        init(template: CardTemplate, carrying card: SocialCardModel) {
            self.template = template
            let all: [Slot: String?] = [
                .title: card.title, .subtitle: card.subtitle,
                .code: card.codeExcerpt.isEmpty ? nil : card.codeExcerpt,
                .language: card.language.rawValue, .handle: card.author, .project: card.project,
            ]
            values = all.compactMapValues { $0 }.filter { template.contentSlots.contains($0.key) }
        }

        /// The card this fill draws. A slot the template owns comes from the fill (absent
        /// means cleared); anything else, including style, stays as it is on `base`.
        public func card(onto base: SocialCardModel) -> SocialCardModel {
            func owned(_ slot: Slot, _ current: String?) -> String? {
                template.contentSlots.contains(slot) ? values[slot] : current
            }
            let code =
                template.contentSlots.contains(.code) ? values[.code] ?? "" : base.codeExcerpt
            // Code from a fill without a language is not assumed to be the card's language.
            let language =
                values[.language].flatMap(Language.init(rawValue:))
                ?? (values[.code] != nil ? .plaintext : base.language)
            return SocialCardModel(
                title: owned(.title, base.title), subtitle: owned(.subtitle, base.subtitle),
                codeExcerpt: code, language: language,
                author: owned(.handle, base.author), project: owned(.project, base.project),
                showLogo: base.showLogo, template: template.layout,
                theme: values[.theme].map(Theme.theme(withID:)) ?? base.theme,
                background: values[.accent].flatMap(GradientPreset.init(rawValue:))
                    .map { .gradient($0) } ?? base.background,
                fontName: base.fontName, fontSize: base.fontSize)
        }

        /// The canonical value for `slot`, `nil` when blank, or an error for an
        /// over-long value, a control character or a choice outside the allow-list.
        static func validated(_ raw: String, for slot: Slot) throws -> String? {
            guard raw.count <= slot.maxLength, raw.unicodeScalars.count <= slot.maxScalars else {
                throw FillError.invalidValue(slot)
            }
            let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let allowed: Set<Unicode.Scalar> = slot == .code ? ["\n", "\t"] : []
            // Bidirectional controls can make a card read differently from its text;
            // line separators and direction marks are accepted only inside code.
            let lineAndMarks: Set<UInt32> = [0x2028, 0x2029, 0x200E, 0x200F, 0x061C]
            let rejected = text.unicodeScalars.contains {
                ($0.properties.generalCategory == .control && !allowed.contains($0))
                    || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value)
                    || (slot != .code && lineAndMarks.contains($0.value))
            }
            guard !rejected else { throw FillError.invalidValue(slot) }
            let choice = text.lowercased()
            switch slot {
            case .language:
                guard let language = Language(rawValue: choice), language != .terminal else {
                    throw FillError.invalidValue(slot)
                }
                return language.rawValue
            case .theme:
                guard Theme.builtInIDs.contains(choice) else { throw FillError.invalidValue(slot) }
                return choice
            case .accent:
                guard
                    let preset = GradientPreset.allCases.first(where: {
                        $0.rawValue.lowercased() == choice
                    })
                else { throw FillError.invalidValue(slot) }
                return preset.rawValue
            case .title, .subtitle, .code, .handle, .project:
                return text
            }
        }
    }
}

/// Reads `vitrine://card?template=release&title=…` links.
///
/// The link is untrusted input: only the `template` key and the template's own slots
/// are accepted, each once, within a bounded length, and nothing else in the URL
/// (path, fragment, credentials, port) is allowed. `+` reads as a space, as in a form.
public enum CardTemplateLink {
    public static let host = "card"
    public static let templateKey = "template"
    public static let maxLength = 16 * 1024

    public static func fill(from url: URL) throws -> CardTemplate.Fill {
        guard url.absoluteString.utf8.count <= maxLength,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == SnapshotShareLink.scheme,
            components.host?.lowercased() == host,
            components.user == nil, components.password == nil, components.port == nil,
            components.path.isEmpty, components.fragment == nil,
            let items = components.percentEncodedQueryItems,
            items.count <= CardTemplate.Slot.allCases.count + 1
        else { throw CardTemplate.FillError.malformedLink }

        var seen = Set<String>()
        var templateID: String?
        var values: [CardTemplate.Slot: String] = [:]
        for item in items {
            guard
                let value = item.value?.replacingOccurrences(of: "+", with: " ")
                    .removingPercentEncoding
            else { throw CardTemplate.FillError.malformedLink }
            guard seen.insert(item.name).inserted else {
                throw CardTemplate.FillError.duplicateSlot(item.name)
            }
            if item.name == templateKey {
                templateID = value
            } else if let slot = CardTemplate.Slot(rawValue: item.name) {
                values[slot] = value
            } else {
                throw CardTemplate.FillError.unsupportedSlot(item.name)
            }
        }
        guard let template = templateID.flatMap(CardTemplate.named) else {
            throw CardTemplate.FillError.unknownTemplate
        }
        return try CardTemplate.Fill(template: template, values: values)
    }
}
