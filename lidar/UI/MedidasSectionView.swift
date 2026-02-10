//
//  MedidasSectionView.swift
//  lidar
//
//  Sección Medidas: varias mediciones, puntos visibles, etiquetas sobre la línea, borrar y editar.
//

import SwiftUI

struct MedidasSectionView: View {
    var sceneManager: ARSceneManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerBlock
                if sceneManager.isMeasurementMode {
                    measurementModeBlock
                } else {
                    startMeasurementButton
                }
                unitPickerBlock
                if !sceneManager.measurements.isEmpty {
                    measurementsListBlock
                }
                if let result = sceneManager.lastMeasurementResult, sceneManager.measurements.count == 1 {
                    lastMeasurementSummary
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Medidas")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Medidas precisas", systemImage: "ruler")
                .font(.headline)
            Text("Toca «Medir distancia» y luego dos puntos en la escena. Verás un marcador naranja en el primer punto. La distancia aparece sobre la línea.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .glassBackground(cornerRadius: 16)
    }

    private var measurementModeBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text(sceneManager.measurementFirstPoint == nil
                     ? "Toca el primer punto en la escena"
                     : "Toca el segundo punto")
                .font(.subheadline)
                .fontWeight(.medium)
            }
            if sceneManager.measurementFirstPoint != nil {
                Text("Marcador naranja = punto 1")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "plus.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("Zoom para mayor precisión")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.1f×", sceneManager.measurementZoomScale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(sceneManager.measurementZoomScale) },
                    set: { sceneManager.measurementZoomScale = Float($0) }
                ), in: AppConstants.Measurement.zoomRange, step: AppConstants.Measurement.zoomStep)
                .accessibilityLabel("Zoom de medición")
                .accessibilityValue(String(format: "%.1f aumentos", sceneManager.measurementZoomScale))
                .accessibilityHint("Ajusta el zoom de la vista AR para mayor precisión al medir")
            }
            .padding(10)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Button("Cancelar medición") {
                sceneManager.cancelMeasurement()
                HapticService.shared.notification(type: .warning)
            }
            .font(.subheadline)
            .foregroundStyle(.red)
            .accessibilityLabel("Cancelar medición")
            .accessibilityHint("Sale del modo medición sin guardar")
        }
        .padding()
        .glassBackground(cornerRadius: 16)
    }

    private var startMeasurementButton: some View {
        Button {
            sceneManager.startMeasurement()
            HapticService.shared.impact(style: .medium)
        } label: {
            Label("Medir distancia", systemImage: "ruler")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("Iniciar medición")
        .accessibilityHint("Activa el modo medición. Toca dos puntos en la escena AR para medir la distancia entre ellos")
    }

    private var unitPickerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unidad de medida")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Picker("Unidad", selection: Binding(
                get: { sceneManager.measurementUnit },
                set: { newUnit in
                    sceneManager.measurementUnit = newUnit
                    sceneManager.refreshMeasurementDisplays()
                }
            )) {
                Text("Metros (m)").tag(MeasurementUnit.meters)
                Text("Pies (ft)").tag(MeasurementUnit.feet)
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .glassBackground(cornerRadius: 16)
    }

    private var measurementsListBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mediciones")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(sceneManager.measurements.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            ForEach(Array(sceneManager.measurements.enumerated()), id: \.element.id) { index, m in
                MeasurementRowView(
                    index: index + 1,
                    measurement: m,
                    unit: sceneManager.measurementUnit,
                    onDelete: { sceneManager.deleteMeasurement(id: m.id) }
                )
            }
            if sceneManager.measurements.count > 1 {
                Button(role: .destructive) {
                    sceneManager.deleteAllMeasurements()
                    HapticService.shared.notification(type: .warning)
                } label: {
                    Label("Borrar todas las mediciones", systemImage: "trash")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Borrar todas las mediciones")
                .accessibilityHint("Elimina las \(sceneManager.measurements.count) mediciones actuales")
            }
        }
        .padding()
        .glassBackground(cornerRadius: 16)
    }

    private var lastMeasurementSummary: some View {
        Group {
            if let result = sceneManager.lastMeasurementResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Última medida")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text(sceneManager.measurementUnit.format(distanceMeters: result.distance))
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .padding()
                .glassBackground(cornerRadius: 16)
            }
        }
    }
}
