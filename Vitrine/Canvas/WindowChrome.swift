import SwiftUI

/// Decorative macOS-style "traffic light" dots drawn atop the code card (CS-005),
/// optionally with a centered window title (e.g. `ContentView.swift`).
///
/// With no title it sizes to its dots (the signature, golden-stable look). With a
/// title it spans the card width and centers the title between the dots and the
/// trailing edge, like ray.so / Snappify.
struct WindowChrome: View {
    /// The centered title; empty for the dots-only chrome.
    var title: String = ""
    /// The title color, supplied by the canvas so it reads on the active theme.
    var titleColor: Color = .secondary

    var body: some View {
        if title.isEmpty {
            dots
        } else {
            ZStack {
                HStack(spacing: 0) {
                    dots
                    Spacer(minLength: 0)
                }
                Text(verbatim: title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // Keep the title clear of the dots on the leading side.
                    .padding(.horizontal, 44)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: Brand.Spacing.xs) {
            dot(Color(hex: "#FF5F56"))
            dot(Color(hex: "#FFBD2E"))
            dot(Color(hex: "#27C93F"))
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
    }
}
