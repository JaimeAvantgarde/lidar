//
//  OffsiteSceneRenderer.swift
//  lidar
//
//  Componente de renderizado de la escena offsite: dibuja planos, esquinas,
//  mediciones, cuadros con perspectiva y grids sobre la imagen capturada.
//

import SwiftUI

// MARK: - Plane Overlay

/// Dibuja el contorno de un plano detectado sobre la imagen offsite.
struct PlaneOverlayView: View {
    let plane: OffsitePlaneData
    let isSelected: Bool
    let imageSize: CGSize
    let scale: CGFloat
    let offset: CGPoint
    let showDimensions: Bool
    let onTap: () -> Void
    
    var body: some View {
        let vertices = plane.projectedVertices.map { pt -> CGPoint in
            guard pt.count >= 2 else { return .zero }
            return CGPoint(
                x: pt[0] * imageSize.width * scale + offset.x,
                y: pt[1] * imageSize.height * scale + offset.y
            )
        }
        
        let planeColor: Color = plane.isVertical ? .blue : .green
        
        ZStack {
            // Relleno semitransparente
            if vertices.count >= 3 {
                Path { path in
                    path.move(to: vertices[0])
                    for i in 1..<vertices.count {
                        path.addLine(to: vertices[i])
                    }
                    path.closeSubpath()
                }
                .fill(planeColor.opacity(isSelected ? AppConstants.OffsiteEditor.planeSelectedFillOpacity : AppConstants.OffsiteEditor.planeUnselectedFillOpacity))
                .onTapGesture(perform: onTap)
            }
            
            // Contorno
            if vertices.count >= 2 {
                Path { path in
                    path.move(to: vertices[0])
                    for i in 1..<vertices.count {
                        path.addLine(to: vertices[i])
                    }
                    path.closeSubpath()
                }
                .stroke(
                    planeColor.opacity(isSelected ? 0.9 : 0.5),
                    style: StrokeStyle(
                        lineWidth: isSelected ? 3 : AppConstants.OffsiteEditor.planeOutlineLineWidth,
                        dash: isSelected ? [] : [8, 4]
                    )
                )
            }
            
            // Etiqueta de dimensiones
            if showDimensions, vertices.count >= 2 {
                let center = centroid(vertices)
                VStack(spacing: 2) {
                    Text(plane.classification.displayName)
                        .font(.caption2)
                        .fontWeight(.bold)
                    Text(plane.dimensionsText)
                        .font(.caption)
                        .fontWeight(.semibold)
                    if plane.isVertical {
                        Text(String(format: "%.1f m²", plane.widthMeters * plane.heightMeters))
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(planeColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                .position(center)
            }
        }
    }
    
    private func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}

// MARK: - Corner Overlay

/// Dibuja un marcador de esquina sobre la imagen offsite.
struct CornerOverlayView: View {
    let corner: OffsiteCornerData
    let imageSize: CGSize
    let scale: CGFloat
    let offset: CGPoint
    
    var body: some View {
        let pos = CGPoint(
            x: corner.position2D.x * imageSize.width * scale + offset.x,
            y: corner.position2D.y * imageSize.height * scale + offset.y
        )
        
        ZStack {
            // Marcador de esquina
            Image(systemName: "angle")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.yellow)
                .padding(4)
                .background(Color.black.opacity(0.7), in: Circle())
                .position(pos)
            
            // Etiqueta del ángulo
            Text(String(format: "%.0f°", corner.angleDegrees))
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.yellow)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                .position(x: pos.x + 20, y: pos.y - 16)
        }
    }
}

// MARK: - Wall Dimension Overlay

/// Dibuja las dimensiones de una pared con líneas de cota.
struct WallDimensionOverlayView: View {
    let wall: OffsiteWallDimension
    let imageSize: CGSize
    let scale: CGFloat
    let offset: CGPoint
    let unit: MeasurementUnit
    
    var body: some View {
        let vertices = wall.vertices2D.map { pt -> CGPoint in
            guard pt.count >= 2 else { return .zero }
            return CGPoint(
                x: pt[0] * imageSize.width * scale + offset.x,
                y: pt[1] * imageSize.height * scale + offset.y
            )
        }
        
        if vertices.count >= 4 {
            ZStack {
                // Línea de cota horizontal (ancho)
                let topMid = CGPoint(
                    x: (vertices[0].x + vertices[1].x) / 2,
                    y: min(vertices[0].y, vertices[1].y) - 20
                )
                
                Path { path in
                    path.move(to: CGPoint(x: vertices[0].x, y: topMid.y))
                    path.addLine(to: CGPoint(x: vertices[1].x, y: topMid.y))
                }
                .stroke(Color.orange, style: StrokeStyle(lineWidth: AppConstants.OffsiteEditor.planeDimensionLineWidth))
                
                // Etiqueta ancho
                Text(unit.format(distanceMeters: Float(wall.widthMeters)))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                    .position(topMid)
                
                // Línea de cota vertical (alto)
                let leftMid = CGPoint(
                    x: min(vertices[0].x, vertices[2].x) - 20,
                    y: (vertices[0].y + vertices[2].y) / 2
                )
                
                Path { path in
                    path.move(to: CGPoint(x: leftMid.x, y: vertices[0].y))
                    path.addLine(to: CGPoint(x: leftMid.x, y: vertices[2].y))
                }
                .stroke(Color.orange, style: StrokeStyle(lineWidth: AppConstants.OffsiteEditor.planeDimensionLineWidth))
                
                // Etiqueta alto
                Text(unit.format(distanceMeters: Float(wall.heightMeters)))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                    .position(leftMid)
                
                // Área
                let center = CGPoint(
                    x: (vertices[0].x + vertices[1].x + vertices[2].x + vertices[3].x) / 4,
                    y: (vertices[0].y + vertices[1].y + vertices[2].y + vertices[3].y) / 4
                )
                
                Text(String(format: "%.1f m²", wall.widthMeters * wall.heightMeters))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .position(x: center.x, y: center.y + 20)
            }
        }
    }
}

// MARK: - Perspective Frame Overlay

/// Dibuja un cuadro con perspectiva real del plano.
struct PerspectiveFrameOverlayView: View {
    let frame: OffsiteFramePerspective
    let imageSize: CGSize
    let scale: CGFloat
    let offset: CGPoint
    let isSelected: Bool
    let isEditMode: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        let corners = frame.corners2D.map { pt -> CGPoint in
            guard pt.count >= 2 else { return .zero }
            return CGPoint(
                x: pt[0] * imageSize.width * scale + offset.x,
                y: pt[1] * imageSize.height * scale + offset.y
            )
        }
        
        ZStack {
            if corners.count == 4 {
                // Dibujar cuadro con perspectiva (cuadrilátero)
                if let base64 = frame.imageBase64,
                   let imageData = Data(base64Encoded: base64),
                   let uiImage = UIImage(data: imageData) {
                    // Imagen con perspectiva - usamos el bounding box
                    let minX = corners.map(\.x).min() ?? 0
                    let maxX = corners.map(\.x).max() ?? 0
                    let minY = corners.map(\.y).min() ?? 0
                    let maxY = corners.map(\.y).max() ?? 0
                    
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: maxX - minX, height: maxY - minY)
                        .clipShape(PerspectiveShape(corners: corners))
                        .position(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
                }
                
                // Contorno con perspectiva
                Path { path in
                    path.move(to: corners[0])
                    for i in 1..<4 {
                        path.addLine(to: corners[i])
                    }
                    path.closeSubpath()
                }
                .stroke(
                    Color(hex: frame.color),
                    lineWidth: isSelected ? 4 : 2
                )
                
                // Etiqueta
                let center = CGPoint(
                    x: corners.reduce(0) { $0 + $1.x } / 4,
                    y: corners.reduce(0) { $0 + $1.y } / 4
                )
                
                VStack(spacing: 1) {
                    if let label = frame.label {
                        Text(label)
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    Text(String(format: "%.2f × %.2f m", frame.widthMeters, frame.heightMeters))
                        .font(.caption2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hex: frame.color).opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                .position(x: center.x, y: (corners.map(\.y).min() ?? center.y) - 16)
                
                // Edit mode buttons
                if isEditMode {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                            .background(Circle().fill(.white))
                    }
                    .position(x: corners[1].x + 8, y: corners[1].y - 8)
                }
                
                if isSelected {
                    Path { path in
                        path.move(to: corners[0])
                        for i in 1..<4 {
                            path.addLine(to: corners[i])
                        }
                        path.closeSubpath()
                    }
                    .stroke(Color.yellow, lineWidth: 3)
                }
            }
        }
        .onTapGesture(perform: onSelect)
    }
}

/// Shape que dibuja un cuadrilátero con perspectiva.
struct PerspectiveShape: Shape {
    let corners: [CGPoint]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard corners.count == 4 else { return path }
        
        let minX = corners.map(\.x).min() ?? 0
        let minY = corners.map(\.y).min() ?? 0
        
        let adjusted = corners.map { CGPoint(x: $0.x - minX, y: $0.y - minY) }
        
        path.move(to: adjusted[0])
        for i in 1..<4 {
            path.addLine(to: adjusted[i])
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Enhanced Measurement Overlay

/// Overlay de medición mejorado con indicadores de precisión y snap.
struct EnhancedMeasurementOverlay: View {
    let measurement: OffsiteMeasurement
    let imageSize: CGSize
    let scale: CGFloat
    let offset: CGPoint
    let unit: MeasurementUnit
    let isEditMode: Bool
    let onDelete: () -> Void
    
    var body: some View {
        let pA = CGPoint(
            x: measurement.pointA.x * imageSize.width * scale + offset.x,
            y: measurement.pointA.y * imageSize.height * scale + offset.y
        )
        let pB = CGPoint(
            x: measurement.pointB.x * imageSize.width * scale + offset.x,
            y: measurement.pointB.y * imageSize.height * scale + offset.y
        )
        
        let lineColor: Color = measurement.isFromAR ? .green : .cyan
        let labelBg: Color = measurement.isFromAR ? Color.black.opacity(0.85) : Color.blue.opacity(0.7)
        
        ZStack {
            // Línea de medición con efecto glow
            Path { path in
                path.move(to: pA)
                path.addLine(to: pB)
            }
            .stroke(lineColor.opacity(0.3), lineWidth: measurement.isFromAR ? 6 : 4)
            
            Path { path in
                path.move(to: pA)
                path.addLine(to: pB)
            }
            .stroke(lineColor, lineWidth: measurement.isFromAR ? 2.5 : 2)
            
            // Endpoints mejorados
            MeasurementEndpoint(color: .orange)
                .position(pA)
            
            MeasurementEndpoint(color: lineColor)
                .position(pB)
            
            // Etiqueta con más info
            VStack(spacing: 2) {
                Text(unit.format(distanceMeters: Float(measurement.distanceMeters)))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                HStack(spacing: 4) {
                    Image(systemName: measurement.isFromAR ? "checkmark.seal.fill" : "wave.3.right")
                        .font(.system(size: 8))
                    Text(measurement.isFromAR ? "AR precisa" : "≈ estimada")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(labelBg, in: RoundedRectangle(cornerRadius: 8))
            .position(x: (pA.x + pB.x) / 2, y: (pA.y + pB.y) / 2 - 22)
            
            if isEditMode {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .background(Circle().fill(.white))
                }
                .position(x: (pA.x + pB.x) / 2 + 50, y: (pA.y + pB.y) / 2 - 22)
            }
        }
    }
}

/// Endpoint de medición mejorado.
struct MeasurementEndpoint: View {
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 18, height: 18)
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Circle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 10, height: 10)
        }
    }
}

// MARK: - Scene Info Panel

/// Panel de información de la escena capturada para offsite.
struct OffsiteSceneInfoPanel: View {
    let snapshot: OffsiteSceneSnapshot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.lidarMetadata?.isLiDARAvailable == true ? "sensor.fill" : "sensor")
                    .foregroundStyle(snapshot.lidarMetadata?.isLiDARAvailable == true ? .green : .secondary)
                Text(snapshot.lidarMetadata?.isLiDARAvailable == true ? "LiDAR" : "AR")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            
            HStack(spacing: 16) {
                InfoChip(icon: "rectangle.on.rectangle.angled", value: "\(snapshot.totalPlanes)", label: "planos")
                InfoChip(icon: "rectangle.portrait", value: "\(snapshot.totalWalls)", label: "paredes")
                InfoChip(icon: "angle", value: "\(snapshot.corners.count)", label: "esquinas")
                InfoChip(icon: "ruler", value: "\(snapshot.measurements.count)", label: "medidas")
            }
            
            if let scale = snapshot.metersPerPixelScale {
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                        .font(.caption2)
                    Text(String(format: "Escala: %.4f m/px", scale))
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct InfoChip: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(value)
                    .font(.caption)
                    .fontWeight(.bold)
            }
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
    }
}
