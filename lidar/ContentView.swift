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
    @State private var isCapturing = false
    @State private var showPoorQualityConfirmation = false

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
                    .onAppear {
                        // Auto-dismiss error after 4 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                sceneManager.errorMessage = nil
                            }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Hint flotante cuando el panel está colapsado, modo mover o modo medidas
            if !panelExpanded || sceneManager.moveModeForFrameId != nil || sceneManager.isMeasurementMode || sceneManager.isVinylMode {
                floatingHint
            }

            // Spinner de captura
            if isCapturing {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Capturando escena\u{2026}")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .sheet(isPresented: $showPlaneInfo) {
            planeInfoSheet
        }
        .fullScreenCover(isPresented: $showOffsiteSheet) {
            OffsiteCapturesListView()
        }
        .confirmationDialog(
            "Calidad de captura baja",
            isPresented: $showPoorQualityConfirmation,
            titleVisibility: .visible
        ) {
            Button("Capturar de todas formas") {
                performCapture()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La escena tiene pocos datos (planos, mediciones o tracking limitado). La captura puede tener menos precision.")
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

            // Planos y esquinas detectados
            if !sceneManager.detectedPlaneAnchors.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.caption2)
                    Text("\(sceneManager.detectedPlaneAnchors.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                    if !sceneManager.detectedCorners.isEmpty {
                        Text("·")
                            .font(.caption2)
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.caption2)
                        Text("\(sceneManager.detectedCorners.count)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .glassPill()
            }

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
                if sceneManager.captureQualityLevel == .poor {
                    showPoorQualityConfirmation = true
                } else {
                    performCapture()
                }
            } label: {
                HStack(spacing: 4) {
                    // Indicador de calidad
                    Circle()
                        .fill(qualityColor)
                        .frame(width: 8, height: 8)
                    Image(systemName: "camera.viewfinder")
                        .font(.subheadline)
                    if captureDataCount > 0 {
                        Text("\(captureDataCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                }
                .glassPill()
            }
            .disabled(!canCapture || isCapturing)
            .opacity(canCapture ? 1.0 : 0.5)
            .accessibilityLabel("Capturar para offsite")
            .accessibilityHint(canCapture ? "Guarda la escena actual con \(captureDataCount) elementos" : "Necesitas al menos una medición o plano detectado para capturar")
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Área")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f m²", dims.width * dims.height))
                                    .font(.title)
                                    .fontWeight(.bold)
                            }
                        }

                        Divider()

                        // Resumen escena
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Escena detectada")
                                .font(.headline)
                            HStack(spacing: 20) {
                                Label("\(sceneManager.detectedPlaneAnchors.count) planos", systemImage: "square.3.layers.3d")
                                Label("\(sceneManager.detectedCorners.count) esquinas", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            HStack(spacing: 20) {
                                Label("\(sceneManager.measurements.count) mediciones", systemImage: "ruler")
                                Label("\(sceneManager.placedFrames.count) cuadros", systemImage: "photo.artframe")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }

                        // Toggles rápidos
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Visualización")
                                .font(.headline)
                            Toggle("Contornos de planos", isOn: $sceneManager.showPlaneOverlays)
                            Toggle("Marcadores de esquinas", isOn: $sceneManager.showCornerMarkers)
                            Toggle("Snap a bordes/esquinas", isOn: $sceneManager.snapToEdgesEnabled)
                            Toggle("Perspectiva en cuadros", isOn: $sceneManager.useFramePerspective)
                        }

                        Text("LiDAR: \(sceneManager.isLiDARAvailable ? "Disponible ✓" : "No disponible ✗")")
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
            if sceneManager.lastSnapPoint != nil {
                return sceneManager.measurementFirstPoint == nil
                    ? "⊕ Snap detectado · Toca para fijar punto 1"
                    : "⊕ Snap detectado · Toca para fijar punto 2"
            }
            return sceneManager.measurementFirstPoint == nil
                ? "Toca el primer punto para medir"
                : "Toca el segundo punto para medir"
        }
        if sceneManager.moveModeForFrameId != nil {
            return "Toca un plano para colocar el cuadro aquí"
        }
        if sceneManager.isVinylMode {
            return "Toca una pared para cubrir con vinilo"
        }
        if sceneManager.useFramePerspective {
            return "Toca una pared para colocar con perspectiva"
        }
        return "Toca un plano para colocar un cuadro"
    }

    // MARK: - Computed helpers

    private var canCapture: Bool {
        !sceneManager.measurements.isEmpty || !sceneManager.detectedPlaneAnchors.isEmpty || !sceneManager.placedFrames.isEmpty
    }

    private var captureDataCount: Int {
        sceneManager.measurements.count + sceneManager.placedFrames.count + sceneManager.detectedPlaneAnchors.count
    }

    private var qualityColor: Color {
        switch sceneManager.captureQualityLevel {
        case .poor: return .red
        case .fair: return .yellow
        case .good: return .green
        }
    }

    private func performCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            do {
                _ = try await sceneManager.captureForOffsite()
                HapticService.shared.notification(type: .success)
                let measurementCount = sceneManager.measurements.count
                let frameCount = sceneManager.placedFrames.count
                let planeCount = sceneManager.detectedPlaneAnchors.count
                let cornerCount = sceneManager.detectedCorners.count
                var parts: [String] = []
                if measurementCount > 0 {
                    parts.append(measurementCount == 1 ? "1 medición" : "\(measurementCount) mediciones")
                }
                if frameCount > 0 {
                    parts.append(frameCount == 1 ? "1 cuadro" : "\(frameCount) cuadros")
                }
                if planeCount > 0 {
                    parts.append(planeCount == 1 ? "1 plano" : "\(planeCount) planos")
                }
                if cornerCount > 0 {
                    parts.append(cornerCount == 1 ? "1 esquina" : "\(cornerCount) esquinas")
                }
                let summary = parts.isEmpty ? "datos de escena" : parts.joined(separator: ", ")
                offsiteCaptureAlert = "✓ Captura guardada con \(summary). Puedes verla en «Ver capturas»."
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
            isCapturing = false
        }
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
