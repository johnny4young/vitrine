import SwiftUI
import VitrineDomain
import VitrineRendering

/// What the legibility warning shares between its meter and its badge. The stage writes the
/// debounced code here, so only those two views depend on it, never on the live document.
@Observable
final class LegibilityModel {
    var stagedCode: String?
    var report: ThemeLegibility?
}

/// Measures the capture's text from the preview's debounced code, so typing doesn't reach it.
/// It has no children, which keeps the style ticks that re-evaluate it cheap.
struct LegibilityMeter: View {
    let settings: AppSettings
    let model: LegibilityModel

    @State private var measuredCode: String?

    static func input(settings: AppSettings, code: String) -> ThemeLegibility.Input {
        var config = settings.style
        config.code = code
        return ThemeLegibility.Input(config)
    }

    var body: some View {
        let code = model.stagedCode
        let input = code.map { Self.input(settings: settings, code: $0) }
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: input) {
                guard let code, let input else { return }
                // New text waits for quiet. A style change answers at once from cached text.
                if code != measuredCode {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    measuredCode = code
                }
                let measured = ThemeLegibility.measure(input)
                if model.report != measured { model.report = measured }
            }
            .accessibilityHidden(true)
    }
}

/// The Theme header's warning. It only appears for weak text and never changes anything
/// unless the user presses the offered button.
struct LegibilityBadge: View {
    let settings: AppSettings
    let model: LegibilityModel

    @State private var betterTheme: Theme?
    @State private var isShowingDetails = false

    var body: some View {
        if let report = model.report, report.isWeak {
            let ratio = Self.ratioText(report.lowInks.first?.ratio ?? report.threshold)
            Button {
                isShowingDetails = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(verbatim: ratio)
                        .foregroundStyle(VitrineTokens.Text.primary)
                }
                .font(.system(size: VitrineTokens.FontSize.caption))
                .monospacedDigit()
                .fixedSize()
            }
            .buttonStyle(.plain)
            .help("Low code contrast")
            .accessibilityLabel("Low code contrast")
            .accessibilityValue(Text(verbatim: ratio))
            .accessibilityIdentifier("theme-legibility-badge")
            .popover(isPresented: $isShowingDetails, arrowEdge: .leading) {
                details(report)
                    .task(id: report) {
                        var config = settings.style
                        config.code = model.stagedCode ?? ""
                        betterTheme = ThemeLegibility.betterTheme(for: config)
                    }
            }
        }
    }

    private func details(_ report: ThemeLegibility) -> some View {
        VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xs) {
            Text("Low code contrast")
                .font(.system(size: VitrineTokens.FontSize.body, weight: .semibold))
            ForEach(report.lowInks.prefix(3)) { ink in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: ink.hex))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(VitrineTokens.Line.border))
                    Text(verbatim: Self.ratioText(ink.ratio))
                        .monospacedDigit()
                    Text("\(Int((ink.share * 100).rounded(.up)))% of the text")
                        .foregroundStyle(VitrineTokens.Text.secondary)
                }
                .font(.system(size: VitrineTokens.FontSize.caption))
                .accessibilityElement(children: .combine)
            }
            if let betterTheme {
                Button("Use \(betterTheme.displayName)") {
                    settings.style.theme = betterTheme
                    isShowingDetails = false
                }
                .accessibilityIdentifier("theme-legibility-fix-button")
            }
        }
        .padding(VitrineTokens.Spacing.sm)
        .frame(width: 240, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("theme-legibility-details")
    }

    private static func ratioText(_ ratio: Double) -> String {
        String(format: "%.1f : 1", ratio)
    }
}
