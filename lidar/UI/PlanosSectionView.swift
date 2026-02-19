//
//  PlanosSectionView.swift
//  lidar
//
//  Sección Planos: dimensiones de paredes, LiDAR, detección de esquinas, lista de planos detectados.
//

import SwiftUI
import ARKit

struct PlanosSectionView: View {
    var sceneManager: ARSceneManager
    @State private var showFloorPlan = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Estado LiDAR
                lidarStatusBlock
                
                // Controles de visualización
                visualizationControls
                
                // Plano actual con dimensiones
                currentPlaneBlock
                
                // Lista de todos los planos detectados
                if !sceneManager.detectedPlanes.isEmpty {
                    allPlanesBlock
                }
                
                // Botón plano 2D
                if sceneManager.detectedPlanes.contains(where: { $0.alignment == .vertical }) {
                    Button {
                        showFloorPlan = true
                    } label: {
                        Label("Generar plano 2D", systemImage: "map")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .sheet(isPresented: $showFloorPlan) {
                        FloorPlanView(floorPlanData: FloorPlanGenerator.generate(
                            from: sceneManager.detectedPlanes,
                            classifyPlane: { sceneManager.classifyPlane($0) },
                            roomSummary: sceneManager.estimateRoomSummary()
                        ))
                    }
                }

                // Esquinas detectadas
                if !sceneManager.detectedCorners.isEmpty {
                    cornersBlock
                }
                
                // Estadísticas
                statsBlock
            }
            .padding(.horizontal)
        }
        .navigationTitle("Planos")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - LiDAR Status
    
    private var lidarStatusBlock: some View {
        HStack(spacing: 12) {
            Image(systemName: sceneManager.isLiDARAvailable ? "sensor.fill" : "sensor")
                .font(.title2)
                .foregroundStyle(sceneManager.isLiDARAvailable ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("LiDAR")
                    .font(.headline)
                Text(sceneManager.isLiDARAvailable ? "Activo · Mesh + Scene Depth" : "No disponible en este dispositivo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Contadores rápidos
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(sceneManager.detectedPlanes.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Text("\(sceneManager.detectedCorners.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Image(systemName: "angle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .glassBackground(cornerRadius: 16)
    }
    
    // MARK: - Visualization Controls
    
    private var visualizationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Visualización AR", systemImage: "eye")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { sceneManager.showPlaneOverlays },
                    set: { sceneManager.showPlaneOverlays = $0; sceneManager.updatePlaneOverlays() }
                )) {
                    Label("Planos", systemImage: "rectangle.dashed")
                        .font(.subheadline)
                }
                .toggleStyle(.switch)
                .tint(.blue)
            }
            
            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { sceneManager.showCornerMarkers },
                    set: { sceneManager.showCornerMarkers = $0; sceneManager.detectAllCorners() }
                )) {
                    Label("Esquinas", systemImage: "angle")
                        .font(.subheadline)
                }
                .toggleStyle(.switch)
                .tint(.yellow)
            }
            
            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { sceneManager.snapToEdgesEnabled },
                    set: { sceneManager.snapToEdgesEnabled = $0 }
                )) {
                    Label("Snap a bordes", systemImage: "target")
                        .font(.subheadline)
                }
                .toggleStyle(.switch)
                .tint(.cyan)
            }
            
            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { sceneManager.useFramePerspective },
                    set: { sceneManager.useFramePerspective = $0 }
                )) {
                    Label("Perspectiva cuadros", systemImage: "cube")
                        .font(.subheadline)
                }
                .toggleStyle(.switch)
                .tint(.purple)
            }

            if sceneManager.isLiDARAvailable {
                Divider()

                HStack(spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { sceneManager.showMeshWireframe },
                        set: { sceneManager.showMeshWireframe = $0; sceneManager.updateMeshVisibility() }
                    )) {
                        Label("Malla 3D", systemImage: "line.3.crossed.swirl.circle")
                            .font(.subheadline)
                    }
                    .toggleStyle(.switch)
                    .tint(.cyan)
                }

                HStack(spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { sceneManager.showDepthColorMesh },
                        set: { sceneManager.showDepthColorMesh = $0; sceneManager.updateDepthMeshVisibility() }
                    )) {
                        Label("Nube de puntos", systemImage: "cloud.fill")
                            .font(.subheadline)
                    }
                    .toggleStyle(.switch)
                    .tint(.red)
                }
            }

            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { sceneManager.showFeaturePoints },
                    set: { sceneManager.showFeaturePoints = $0; sceneManager.updateFeaturePointsVisibility() }
                )) {
                    Label("Puntos de tracking", systemImage: "sparkles")
                        .font(.subheadline)
                }
                .toggleStyle(.switch)
                .tint(.orange)
            }
        }
        .padding()
        .glassBackground(cornerRadius: 16)
    }
    
    // MARK: - Current Plane
    
    private var currentPlaneBlock: some View {
        Group {
            if let dims = sceneManager.lastPlaneDimensions {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Plano actual", systemImage: "rectangle.on.rectangle.angled")
                        .font(.headline)
                    HStack(spacing: 24) {
                        DimensionRowView(value: dims.width, unit: "m", label: "Ancho")
                        DimensionRowView(value: dims.height, unit: "m", label: "Alto")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Área")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f m²", dims.width * dims.height))
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                    }
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
        }
    }
    
    // MARK: - All Planes List
    
    private var allPlanesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Planos detectados", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(sceneManager.detectedPlanes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            
            let walls = sceneManager.detectedPlanes.filter { $0.alignment == .vertical }
            let floors = sceneManager.detectedPlanes.filter { $0.alignment == .horizontal }
            
            if !walls.isEmpty {
                Text("Paredes (\(walls.count))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                
                ForEach(Array(walls.enumerated()), id: \.element.identifier) { index, plane in
                    PlaneRowView(
                        index: index + 1,
                        plane: plane,
                        classification: sceneManager.classifyPlane(plane),
                        isSelected: sceneManager.selectedPlaneAnchor?.identifier == plane.identifier
                    )
                    .onTapGesture {
                        sceneManager.selectedPlaneAnchor = plane
                        sceneManager.lastPlaneDimensions = PlaneDimensions(
                            width: plane.extent.x, height: plane.extent.z, extent: plane.extent
                        )
                    }
                }
            }
            
            if !floors.isEmpty {
                Text("Suelos/Techos (\(floors.count))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                
                ForEach(Array(floors.enumerated()), id: \.element.identifier) { index, plane in
                    PlaneRowView(
                        index: index + 1,
                        plane: plane,
                        classification: sceneManager.classifyPlane(plane),
                        isSelected: false
                    )
                }
            }
        }
        .padding()
        .glassBackground(cornerRadius: 16)
    }
    
    // MARK: - Corners
    
    private var cornersBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Esquinas detectadas", systemImage: "angle")
                    .font(.headline)
                Spacer()
                Text("\(sceneManager.detectedCorners.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.2))
                    .clipShape(Capsule())
            }
            
            ForEach(Array(sceneManager.detectedCorners.enumerated()), id: \.offset) { index, corner in
                HStack(spacing: 12) {
                    Image(systemName: "angle")
                        .foregroundStyle(.yellow)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "Esquina %d · %.0f°", index + 1, corner.angle))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Entre 2 paredes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.yellow.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .glassBackground(cornerRadius: 16)
    }
    
    // MARK: - Stats
    
    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Información de escena", systemImage: "info.circle")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 20) {
                StatItem(value: "\(sceneManager.detectedPlanes.count)", label: "Planos")
                StatItem(value: "\(sceneManager.detectedCorners.count)", label: "Esquinas")
                StatItem(value: "\(sceneManager.measurements.count)", label: "Medidas")
                StatItem(value: "\(sceneManager.placedFrames.count)", label: "Cuadros")
            }
        }
        .padding()
        .glassBackground(cornerRadius: 16)
    }
}

// MARK: - Subcomponents

private struct PlaneRowView: View {
    let index: Int
    let plane: ARPlaneAnchor
    let classification: PlaneClassification
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: classification.icon)
                .foregroundStyle(plane.alignment == .vertical ? .blue : .green)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(classification.displayName) \(index)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(String(format: "%.2f × %.2f m (%.2f m²)", plane.extent.x, plane.extent.z, plane.extent.x * plane.extent.z))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(10)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatItem: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// PlaneClassification is in Models/SceneExportModels.swift
// DimensionRow → Extraído a UI/Components/DimensionRowView.swift
