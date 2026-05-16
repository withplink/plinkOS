import SwiftUI

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// Tinted accent glass for action buttons
struct AccentGlass: ViewModifier {
    var color: Color
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.tint(color.opacity(0.15)), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(color.opacity(0.25), lineWidth: 1))
        }
    }
}

extension View {
    func accentGlass(color: Color, cornerRadius: CGFloat = 12) -> some View {
        modifier(AccentGlass(color: color, cornerRadius: cornerRadius))
    }
}

// Loading spinner
struct LoadingSpinner: View {
    @State private var rotation = 0.0

    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
