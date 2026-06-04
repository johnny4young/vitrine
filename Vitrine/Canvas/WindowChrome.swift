import SwiftUI

/// Decorative macOS-style "traffic light" dots drawn atop the code card (CS-005).
struct WindowChrome: View {
    var body: some View {
        HStack(spacing: 8) {
            dot(Color(hex: "#FF5F56"))
            dot(Color(hex: "#FFBD2E"))
            dot(Color(hex: "#27C93F"))
            Spacer()
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
    }
}
