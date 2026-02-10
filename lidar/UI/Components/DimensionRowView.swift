//
//  DimensionRowView.swift
//  lidar
//
//  Fila reutilizable para mostrar una dimensión (ancho, alto, etc.).
//

import SwiftUI

struct DimensionRowView: View {
    let value: Float
    let unit: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f %@", value, unit))
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(String(format: "%.2f", value)) \(unit)")
    }
}
