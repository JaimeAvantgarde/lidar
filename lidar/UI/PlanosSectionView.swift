//
//  PlanosSectionView.swift
//  lidar
//
//  Sección Planos: dimensiones de paredes, LiDAR, detección de esquinas (info).
//

import SwiftUI

struct PlanosSectionView: View {
    var sceneManager: ARSceneManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Estado LiDAR
                HStack(spacing: 12) {
                    Image(systemName: sceneManager.isLiDARAvailable ? "sensor.fill" : "sensor")
                        .font(.title2)
                        .foregroundStyle(sceneManager.isLiDARAvailable ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LiDAR")
                            .font(.headline)
                        Text(sceneManager.isLiDARAvailable ? "Activo · Mesh disponible" : "No disponible en este dispositivo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .glassBackground(cornerRadius: 16)

                // Dimensiones del plano actual
                if let dims = sceneManager.lastPlaneDimensions {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Plano detectado", systemImage: "rectangle.on.rectangle.angled")
                            .font(.headline)
                        HStack(spacing: 24) {
                            DimensionRow(value: dims.width, unit: "m", label: "Ancho")
                            DimensionRow(value: dims.height, unit: "m", label: "Alto")
                        }
                        Text("Mueve el dispositivo para que se actualicen las dimensiones del plano.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .glassBackground(cornerRadius: 16)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Sin plano", systemImage: "rectangle.dashed")
                            .font(.headline)
                        Text("Apunta a una pared o superficie para detectar un plano.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .glassBackground(cornerRadius: 16)
                }

                // Esquinas / ángulos (informativo)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Esquinas y ángulos", systemImage: "angle")
                        .font(.headline)
                    Text("La detección de esquinas entre paredes permite medidas más precisas. Disponible en modo online con LiDAR.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .glassBackground(cornerRadius: 16)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Planos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DimensionRow: View {
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
    }
}
