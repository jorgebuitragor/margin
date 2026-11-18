import SwiftUI
import AppKit

/// Superficie de Liquid Glass para tarjetas y paneles. Con «Reducir transparencia» de macOS usa un fondo sólido, y con
/// «más contraste» (ajuste de Margin) añade un borde.
struct Surface: ViewModifier {
    var cornerRadius: CGFloat = 18
    var tint: Color? = nil
    var interactive = false
    var highContrast = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(highContrast ? 0.45 : 0.1)))
        } else {
            content
                .glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
                .overlay { if highContrast { shape.strokeBorder(Color.primary.opacity(0.4)) } }
        }
    }
}

extension View {
    func surface(cornerRadius: CGFloat = 18, tint: Color? = nil, interactive: Bool = false, highContrast: Bool = false) -> some View {
        modifier(Surface(cornerRadius: cornerRadius, tint: tint, interactive: interactive, highContrast: highContrast))
    }

    /// Se eleva un poco al pasar el ratón (las tarjetas parecen pulsables).
    func hoverLift(_ enabled: Bool = true) -> some View { modifier(HoverLift(enabled: enabled)) }
}

struct HoverLift: ViewModifier {
    var enabled: Bool
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(enabled && hovering ? 1.015 : 1)
            .shadow(color: .black.opacity(enabled && hovering ? 0.12 : 0), radius: 12, y: 6)
            .animation(.smooth(duration: 0.25), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Fondo de la ventana: un degradado de malla muy suave con el color de acento. Cada pestaña desplaza la luz, de modo
/// que cambiar de sección se nota sin distraer. El cristal de las tarjetas lo refracta.
struct Backdrop: View {
    var index: Int
    var accent: Color
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            let shift = Float(index % 5) / 4 // 0…1
            let strength = scheme == .dark ? 0.32 : 0.22
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.25 + 0.5 * shift, 0.35 + 0.3 * (1 - shift)], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ], colors: [
                    accent.opacity(strength), .clear, Color.blue.opacity(strength * 0.6),
                    .clear, accent.opacity(strength * 0.5), .clear,
                    Color.purple.opacity(strength * 0.45), .clear, accent.opacity(strength * 0.7)
                ])
            }
        }
    }
}

/// Barra de acciones flotante (cristal en cápsula) al pie de una pestaña: aparece solo cuando hay algo que hacer.
struct ActionBar<Content: View>: View {
    var highContrast = false
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 14) { content }
            .padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 8)
            .surface(cornerRadius: 26, highContrast: highContrast)
            .padding(.horizontal, 28).padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Pulso suave para los marcadores de carga (esqueletos).
struct Pulse: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([0.45, 1]) { view, phase in view.opacity(phase) } animation: { _ in .easeInOut(duration: 0.9) }
        } else {
            content
        }
    }
}
