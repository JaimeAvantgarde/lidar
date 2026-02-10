//
//  ContentView.swift
//  lidar
//
//  Vista principal: AR a pantalla completa + UI Liquid Glass con secciones (Planos, Cuadros, Medidas).
//

import SwiftUI

struct ContentView: View {
    @State private var sceneManager = ARSceneManager()
    @State private var selectedSection: AppSection = .cuadros
    @State private var showPlaneInfo = false
    @State private var panelExpanded = true
    @State private var showOffsiteSheet = false
    @State private var offsiteCaptureAlert: String?

    enum AppSection: String, CaseIterable {
        case planos = "Planos"
        case cuadros = "Cuadros"
        case medidas = "Medidas"

        var icon: String {
            switch self {
            case .planos: return "rectangle.on.rectangle.angled"
            case .cuadros: return "photo.artframe"
            case .medidas: return "ruler"
            }
        }
    }

    var body: some View {
        ZStack {
            ARViewRepresentable(sceneManager: sceneManager)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Barra superior tipo Liquid Glass con fondo que captura toques
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                    )

                Spacer(minLength: 0)

                // Panel principal con secciones
                if panelExpanded {
                    mainPanel
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                }
            }
            // Permitir que la UI capture toques (no pasen a AR)
            .allowsHitTesting(true)

            if let error = sceneManager.errorMessage {
                errorBanner(message: error)
            }

            // Hint flotante cuando el panel está colapsado, modo mover o modo medidas
            if !panelExpanded || sceneManager.moveModeForFrameId != nil || sceneManager.isMeasurementMode {
                floatingHint
            }
        }
        .sheet(isPresented: $showPlaneInfo) {
            planeInfoSheet
        }
        .fullScreenCover(isPresented: $showOffsiteSheet) {
            OffsiteCapturesListView()
        }
        .alert("Offsite", isPresented: Binding(
            get: { offsiteCaptureAlert != nil },
            set: { if !$0 { offsiteCaptureAlert = nil } }
        )) {
            Button("Ver capturas") {
                offsiteCaptureAlert = nil
                showOffsiteSheet = true
            }
            Button("OK", role: .cancel) {
                offsiteCaptureAlert = nil
            }
        } message: {
            if let msg = offsiteCaptureAlert { Text(msg) }
        }
    }

    // MARK: - Top bar (Liquid Glass)

    private var topBar: some View {
        HStack(spacing: 12) {
            // LiDAR badge
            HStack(spacing: 6) {
                Image(systemName: sceneManager.isLiDARAvailable ? "sensor.fill" : "sensor")
                    .font(.subheadline)
                    .foregroundStyle(sceneManager.isLiDARAvailable ? .green : .secondary)
                Text(sceneManager.isLiDARAvailable ? "LiDAR" : "AR")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .glassPill()

            // Dimensiones del plano
            if let dims = sceneManager.lastPlaneDimensions {
                Button {
                    showPlaneInfo = true
                } label: {
                    HStack(spacing: 6) {
                        Text(String(format: "%.2f × %.2f m", dims.width, dims.height))
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .glassPill()
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            // Capturar para offsite
            Button {
                do {
                    _ = try sceneManager.captureForOffsite()
                    HapticService.shared.notification(type: .success)
                    let measurementCount = sceneManager.measurements.count
                    let frameCount = sceneManager.placedFrames.count
                    let measurementText = measurementCount == 1 ? "1 medición" : "\(measurementCount) mediciones"
                    let frameText = frameCount == 1 ? "1 cuadro" : "\(frameCount) cuadros"
                    offsiteCaptureAlert = "✓ Captura guardada con \(measurementText)\(frameCount > 0 ? " y \(frameText)" : ""). Puedes verla en «Ver capturas»."
                } catch ARSceneManager.CaptureError.noSceneView {
                    HapticService.shared.notification(type: .error)
                    offsiteCaptureAlert = "Error: Vista AR no disponible"
                } catch ARSceneManager.CaptureError.invalidBounds {
                    HapticService.shared.notification(type: .error)
                    offsiteCaptureAlert = "Error: Tamaño de vista inválido"
                } catch ARSceneManager.CaptureError.imageEncodingFailed {
                    HapticService.shared.notification(type: .error)
                    offsiteCaptureAlert = "Error: No se pudo codificar la imagen"
                } catch {
                    HapticService.shared.notification(type: .error)
                    offsiteCaptureAlert = "Error al guardar: \(error.localizedDescription)"
                }
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.subheadline)
                    .glassPill()
            }
            .disabled(sceneManager.measurements.isEmpty)
            .opacity(sceneManager.measurements.isEmpty ? 0.5 : 1.0)
            .accessibilityLabel("Capturar para offsite")
            .accessibilityHint(sceneManager.measurements.isEmpty ? "Necesitas al menos una medición para capturar" : "Guarda una foto con las \(sceneManager.measurements.count) medición\(sceneManager.measurements.count == 1 ? "" : "es") actuales")
            .buttonStyle(.plain)

            // Ver capturas offsite
            Button {
                showOffsiteSheet = true
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.subheadline)
                    .glassPill()
            }
            .accessibilityLabel("Ver capturas offsite")
            .accessibilityHint("Abre la lista de capturas guardadas")
            .buttonStyle(.plain)

            // Expandir / colapsar panel
            Button {
                withAnimation(.spring(response: AppConstants.Animation.springResponse, dampingFraction: AppConstants.Animation.springDamping)) {
                    panelExpanded.toggle()
                }
            } label: {
                Image(systemName: panelExpanded ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .glassPill()
            }
            .accessibilityLabel(panelExpanded ? "Ocultar panel" : "Mostrar panel")
            .accessibilityHint(panelExpanded ? "Colapsa el panel inferior para ver más AR" : "Expande el panel inferior para acceder a los controles")
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: panelExpanded)
    }

    // MARK: - Panel principal con pestañas

    private var mainPanel: some View {
        VStack(spacing: 0) {
            // Selector de sección (segmented style con glass)
            Picker("Sección", selection: $selectedSection) {
                ForEach(AppSection.allCases, id: \.self) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Contenido de la sección
            Group {
                switch selectedSection {
                case .planos:
                    PlanosSectionView(sceneManager: sceneManager)
                case .cuadros:
                    CuadrosSectionView(sceneManager: sceneManager)
                case .medidas:
                    MedidasSectionView(sceneManager: sceneManager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: AppConstants.Layout.panelContentHeight)
        }
        .glassPanel(cornerRadius: AppConstants.Layout.panelCornerRadius, padding: 0)
        .padding(.horizontal, AppConstants.Layout.panelHorizontalPadding)
        .padding(.bottom, AppConstants.Layout.panelBottomPadding)
    }

    // MARK: - Sheet dimensiones plano

    private var planeInfoSheet: some View {
        NavigationStack {
            Group {
                if let dims = sceneManager.lastPlaneDimensions {
                    VStack(alignment: .leading, spacing: 20) {
                        Label("Dimensiones del plano (pared)", systemImage: "rectangle.on.rectangle.angled")
                            .font(.title2)
                            .fontWeight(.semibold)
                        HStack(spacing: 32) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ancho")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f m", dims.width))
                                    .font(.title)
                                    .fontWeight(.bold)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Alto")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f m", dims.height))
                                    .font(.title)
                                    .fontWeight(.bold)
                            }
                        }
                        Text("LiDAR: \(sceneManager.isLiDARAvailable ? "Disponible" : "No disponible")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { showPlaneInfo = false }
                }
            }
        }
    }

    // MARK: - Hint flotante

    private var floatingHint: some View {
        VStack {
            Spacer()
            Text(hintText)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassBackground(cornerRadius: AppConstants.Layout.glassPillCornerRadius)
                .padding(.bottom, panelExpanded ? AppConstants.Layout.expandedHintBottomPadding : AppConstants.Layout.collapsedHintBottomPadding)
        }
        .allowsHitTesting(false)
    }

    private var hintText: String {
        if sceneManager.isMeasurementMode {
            return sceneManager.measurementFirstPoint == nil
                ? "Toca el primer punto para medir"
                : "Toca el segundo punto para medir"
        }
        if sceneManager.moveModeForFrameId != nil {
            return "Toca un plano para colocar el cuadro aquí"
        }
        return "Toca un plano para colocar un cuadro"
    }

    // MARK: - Banner de error

    private func errorBanner(message: String) -> some View {
        VStack {
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 60)
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
