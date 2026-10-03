import SwiftUI

// docs/DESIGN.md §6.3: depth that is drawn, not animated.

extension View {
    /// Layered depth for a result group: two faint rims offset under the surface, so a group card reads as a short
    /// stack of sheets (the leftovers beneath the outline). Static, pure strokes, no shadow on the layers themselves.
    /// Apply it after `.surface(Radius.plate)`.
    func layered() -> some View { modifier(Layered()) }
}

private struct Layered: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
        let dark = scheme == .dark
        return content.background {
            if contrast != .increased {
                ZStack {
                    shape.fill(dark ? Color.white.opacity(0.03) : Color.white.opacity(0.6))
                        .overlay(shape.strokeBorder(Color.primary.opacity(dark ? 0.08 : 0.06), lineWidth: 0.5))
                        .padding(.horizontal, 12).offset(y: 6)
                    shape.fill(dark ? Color.white.opacity(0.04) : Color.white.opacity(0.8))
                        .overlay(shape.strokeBorder(Color.primary.opacity(dark ? 0.09 : 0.07), lineWidth: 0.5))
                        .padding(.horizontal, 6).offset(y: 3)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
