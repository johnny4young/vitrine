import SwiftUI

/// A compact metadata header drawn above the code, inside the exported card.
///
/// The header gives a screenshot context — the file it came from, a title, a
/// caption, and/or a language badge — without editing the image afterward. It is
/// rendered only when `SnapshotConfig.metadata` is non-empty (see
/// `SnapshotCanvas`), so the signature look is unchanged until the user adds
/// context.
///
/// Like the line-number gutter, the header inherits the active theme rather than
/// the app's light/dark appearance: its text color is derived from the theme's
/// card background luminance and its chips use a luminance-aware tint, so it reads
/// correctly on every theme and even over a transparent canvas background.
/// It uses tight, secondary styling so it frames the code without
/// crowding the body.
struct SnapshotHeader: View {
    let metadata: SnapshotMetadata
    let language: Language
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
            if showsBadgeRow {
                HStack(spacing: Brand.Spacing.xs) {
                    if let filename = metadata.filename {
                        chip(filename)
                            .accessibilityLabel("Filename \(filename)")
                    }
                    if metadata.showLanguageBadge {
                        chip(language.displayName)
                            .accessibilityLabel("Language \(language.displayName)")
                    }
                }
            }
            if let title = metadata.title {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(textColor)
            }
            if let caption = metadata.caption {
                Text(caption)
                    .font(.system(size: captionSize))
                    .foregroundStyle(textColor.opacity(0.7))
            }
        }
        // Combine into one element so VoiceOver reads the header as a single
        // "metadata" unit rather than several disconnected chips/lines.
        .accessibilityElement(children: .combine)
    }

    /// The filename and/or language badge share one row; shown only when at least
    /// one of them is present.
    private var showsBadgeRow: Bool {
        metadata.filename != nil || metadata.showLanguageBadge
    }

    /// A single rounded badge/chip with theme-aware fill and text.
    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: captionSize, weight: .medium))
            .foregroundStyle(textColor.opacity(0.85))
            .padding(.horizontal, Brand.Spacing.xs)
            .padding(.vertical, Brand.Spacing.xxs / 2)
            .background(badgeColor)
            .clipShape(Capsule())
    }

    /// Primary header text color, derived from the theme's own card background so
    /// it stays legible on light and dark themes alike.
    private var textColor: Color {
        HighlightManager.shared.gutterForegroundColor(for: theme)
    }

    private var badgeColor: Color {
        HighlightManager.shared.metadataBadgeColor(for: theme)
    }

    // Sized to read as secondary chrome beside the code body, not to compete with
    // it. Fixed points (not the code font size) so the header keeps a consistent,
    // compact scale regardless of the chosen code size.
    private var titleSize: CGFloat { 14 }
    private var captionSize: CGFloat { 11 }
}
