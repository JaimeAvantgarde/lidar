//
//  MedidasSectionView.swift
//  lidar
//
//  Sección Medidas: varias mediciones, puntos visibles, etiquetas sobre la línea, borrar y editar.
//

import SwiftUI

struct MedidasSectionView: View {
    var sceneManager: ARSceneManager
    @State private var showShareSheet = false
    @State private var pdfURL: URL?
    @State private var isGeneratingPDF = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerBlock
                // Resumen de habitación
                roomSummaryBlock
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
                // Exportar PDF
                exportPDFBlock
            }
            .padding(.horizontal)
        }
        .navigationTitle("Medidas")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(activityItems: [url])
            }
        }
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

    // MARK: - Resumen de habitación

    private var roomSummaryBlock: some View {
        Group {
            if let room = sceneManager.estimateRoomSummary() {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Dimensiones estimadas", systemImage: "house.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ancho")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f m", room.width))
                                .font(.callout)
                                .fontWeight(.bold)
                                .monospacedDigit()
                        }
                        
                        Text("×")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Largo")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f m", room.length))
                                .font(.callout)
                                .fontWeight(.bold)
                                .monospacedDigit()
                        }
                        
                        Text("×")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alto")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f m", room.height))
                                .font(.callout)
                                .fontWeight(.bold)
                                .monospacedDigit()
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f m²", room.area))
                                .font(.callout)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                            Text(String(format: "%.1f m³", room.volume))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .glassBackground(cornerRadius: 16)
            }
        }
    }

    // MARK: - Exportar PDF

    private var exportPDFBlock: some View {
        VStack(spacing: 12) {
            Button {
                isGeneratingPDF = true
                // Pequeño delay para que la UI muestre el loading
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pdfURL = sceneManager.generatePDFReport()
                    isGeneratingPDF = false
                    if pdfURL != nil {
                        showShareSheet = true
                        HapticService.shared.notification(type: .success)
                    } else {
                        HapticService.shared.notification(type: .error)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isGeneratingPDF {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "doc.richtext")
                    }
                    Text(isGeneratingPDF ? "Generando informe..." : "Exportar informe PDF")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(isGeneratingPDF || !hasDataToExport)
            .opacity(hasDataToExport ? 1.0 : 0.5)
            
            if !hasDataToExport {
                Text("Necesitas al menos una medición o superficie detectada para generar el informe")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .glassBackground(cornerRadius: 16)
    }
    
    private var hasDataToExport: Bool {
        !sceneManager.measurements.isEmpty || !sceneManager.detectedPlanes.isEmpty
    }
}

// MARK: - ShareSheet UIKit wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
