//
//  MeasurementRowView.swift
//  lidar
//
//  Fila reutilizable para mostrar una medición en la lista.
//

import SwiftUI

struct MeasurementRowView: View {
    let index: Int
    let measurement: ARMeasurement
    let unit: MeasurementUnit
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.2))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(unit.format(distanceMeters: measurement.distance))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Punto A → Punto B")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Medición \(index): \(unit.format(distanceMeters: measurement.distance))")

            Spacer(minLength: 0)

            Button(role: .destructive) {
                onDelete()
                HapticService.shared.impact(style: .light)
            } label: {
                Image(systemName: "trash")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Eliminar medición \(index)")
            .accessibilityHint("Elimina esta medición de la escena")
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
