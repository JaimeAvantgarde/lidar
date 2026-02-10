//
//  GlassModifiers.swift
//  lidar
//
//  Estilo Liquid Glass (iOS 26): paneles translúcidos con .glassEffect() y fallback a materiales.
//

import SwiftUI

// MARK: - Panel tipo Liquid Glass

struct GlassPanelStyle: ViewModifier {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

/// Fondo tipo glass: .glassEffect() en iOS 26, .ultraThinMaterial en versiones anteriores.
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// Capsula pequeña tipo pill para badges y chips.
struct GlassPillStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .modifier(GlassBackground(cornerRadius: 20))
    }
}

// MARK: - Botones con estilo glass

struct GlassButtonStyle: ButtonStyle {
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.clear)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 14))
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Extensiones de uso rápido

extension View {
    /// Panel tipo Liquid Glass con esquinas redondeadas.
    func glassPanel(cornerRadius: CGFloat = 24, padding: CGFloat = 20) -> some View {
        modifier(GlassPanelStyle(cornerRadius: cornerRadius, padding: padding))
    }

    /// Fondo glass solo (sin padding extra).
    func glassBackground(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }

    /// Chip / pill con estilo glass.
    func glassPill() -> some View {
        modifier(GlassPillStyle())
    }
}
