//
//  CuadroRowView.swift
//  lidar
//
//  Fila reutilizable para mostrar un cuadro en la lista de cuadros colocados.
//

import SwiftUI

struct CuadroRowView: View {
    let frame: PlacedFrame
    let isSelected: Bool
    let onSelect: () -> Void
    let onChangePhoto: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    framePreview
                    frameInfo
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(12)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cuadro\(frame.isCornerFrame ? " esquina" : "")")
            .accessibilityValue(isSelected ? "Seleccionado" : "No seleccionado")
            .accessibilityHint("Toca para seleccionar este cuadro")

            Button(action: onChangePhoto) {
                Image(systemName: "photo.badge.plus")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cambiar foto del cuadro")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var framePreview: some View {
        if let img = frame.image {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "photo.artframe")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var frameInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Cuadro")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if frame.isCornerFrame {
                    Text("Esquina")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            Text(String(format: "%.2f × %.2f m", frame.size.width, frame.size.height))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
