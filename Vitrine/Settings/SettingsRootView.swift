import SwiftUI

/// The redesigned Settings window shell (design/handoff): a 190 pt sidebar of
/// navigation rows on the left and the active pane's scrolling content on the
/// right, replacing the classic toolbar tabs.
///
/// The window is a fixed 720×600 card on `VitrineTokens.Surface.window`; the
/// sidebar carries its own wash and hairline. Pane order is stable (General,
/// Style, Brand Kit, Library, Input, Export, About) — the UI tests address rows
/// by their `settings-nav-*` identifiers and panes by their `settings-*-pane`
/// ones.
struct SettingsRootView: View {
    @Bindable var settings: AppSettings
    var presets: PresetStore
    var themes: CustomThemeStore

    /// The selected pane, remembered across openings like the classic window.
    /// Persisted through `AppDefaults` so the UI tests' isolated suite applies.
    @AppStorage("settings.selectedTab", store: AppDefaults.current)
    private var selectedTab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
                .overlay(VitrineTokens.Line.border)
            detail
        }
        .frame(width: 720)
        .frame(maxHeight: .infinity)
        .background(VitrineTokens.Surface.window)
        .tint(VitrineTokens.Accent.system)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: VitrineTokens.Spacing.xs) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                Text("Settings")
                    .font(.system(size: VitrineTokens.FontSize.body, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.primary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)

            ForEach(SettingsTab.allCases) { tab in
                SettingsSidebarRow(tab: tab, isActive: tab == selectedTab) {
                    selectedTab = tab
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, VitrineTokens.Spacing.sm)
        // Clears the traffic lights overlaying the top of the sidebar; the
        // prototype card has no window controls, the real window does.
        .padding(.top, 44)
        .padding(.bottom, 18)
        .frame(width: 190)
        .background(VitrineTokens.Chrome.sidebar)
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsView(settings: settings, presets: presets)
        case .style:
            StyleSettingsView(settings: settings, themes: themes)
        case .brandKit:
            BrandKitSettingsView()
        case .library:
            LibrarySettingsView(settings: settings, presets: presets, themes: themes)
        case .output:
            OutputSettingsView(settings: settings)
        case .input:
            InputSettingsView(settings: settings)
        case .about:
            AboutSettingsView(settings: settings)
        }
    }
}

/// The settings panes, in their stable order.
enum SettingsTab: String, CaseIterable, Identifiable {
    // Order = sidebar order: app → look → branding → library → input → export → about.
    // `input` precedes `output` so the pipeline reads top-to-bottom (you set how content
    // comes in, then how the image leaves). `output`'s raw value stays "output" so its
    // `settings-nav-output` identifier and UI tests are unaffected by the "Export" title.
    case general, style, brandKit, library, input, output, about

    var id: String { rawValue }

    /// The sidebar row title.
    var title: Text {
        switch self {
        case .general: Text("General")
        case .style: Text("Style")
        case .brandKit: Text("Brand Kit")
        case .library: Text("Library")
        case .input: Text("Input")
        // Titled "Export" (clearer than "Output" for "how the image leaves"); the raw
        // value remains "output" to keep the navigation identifier stable.
        case .output: Text("Export")
        case .about: Text("About")
        }
    }

    /// The sidebar row SF Symbol (per the handoff icon mapping).
    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .style: "paintbrush"
        case .brandKit: "crown"
        case .library: "books.vertical"
        case .input: "doc.on.clipboard"
        case .output: "square.and.arrow.up"
        case .about: "info.circle"
        }
    }

    /// The stable identifier of the sidebar row, addressed by the UI tests.
    var navigationIdentifier: String { "settings-nav-\(rawValue)" }
}

/// One sidebar navigation row: icon + title, accent-filled when active,
/// subtly washed on hover.
private struct SettingsSidebarRow: View {
    let tab: SettingsTab
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, height: 18)
                tab.title
                    .font(
                        .system(
                            size: VitrineTokens.FontSize.body,
                            weight: isActive ? .semibold : .regular)
                    )
            }
            .foregroundStyle(
                isActive ? VitrineTokens.Accent.systemContrast : VitrineTokens.Text.secondary
            )
            .padding(.vertical, VitrineTokens.Spacing.xs)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VitrineTokens.Radius.md, style: .continuous)
                    .fill(rowFill)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: VitrineTokens.Radius.md, style: .continuous)
            )
            .animation(.easeInOut(duration: 0.13), value: isActive)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier(tab.navigationIdentifier)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var rowFill: Color {
        if isActive { return VitrineTokens.Accent.system }
        if isHovered { return VitrineTokens.Chrome.tile }
        return .clear
    }
}

/// The scrolling content column shared by the simple panes: 16 pt group
/// rhythm inside the kit's 22/26/28 content padding.
struct SettingsPaneScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.md) {
                content
            }
            .padding(.top, 22)
            .padding(.horizontal, 26)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
