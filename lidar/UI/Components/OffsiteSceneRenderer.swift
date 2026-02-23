//
//  OffsiteSceneRenderer.swift
//  lidar
//
//  Componente de renderizado de la escena offsite: dibuja planos, esquinas,
//  mediciones, cuadros con perspectiva y grids sobre la imagen capturada.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Perspective Image Transform

/// Cache de imagenes transformadas con perspectiva para evitar recalculos cada render.
@MainActor
final class PerspectiveImageCache {
    static let shared = PerspectiveImageCache()
    private var cache: [UUID: UIImage] = [:]
    private var cornerKeys: [UUID: String] = [:]
    private var accessOrder: [UUID] = []
    private let maxEntries = 20
    private let context = CIContext()

    func image(for frameId: UUID, sourceImage: UIImage, corners: [CGPoint], boundingRect: CGRect) -> UIImage? {
        let key = corners.map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: "|")
        if let cached = cache[frameId], cornerKeys[frameId] == key {
            // Mover al final (más reciente)
            if let idx = accessOrder.firstIndex(of: frameId) {
                accessOrder.remove(at: idx)
                accessOrder.append(frameId)
            }
            return cached
        }

        guard let result = applyPerspectiveTransform(sourceImage, to: corners, in: boundingRect) else {
            return nil
        }

        // Evict si se supera el límite
        if cache.count >= maxEntries, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            cornerKeys.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }

        cache[frameId] = result
        cornerKeys[frameId] = key
        accessOrder.append(frameId)
        return result
    }

    func invalidate(frameId: UUID) {
        cache.removeValue(forKey: frameId)
        cornerKeys.removeValue(forKey: frameId)
        accessOrder.removeAll { $0 == frameId }
    }

    /// Verifica que 4 puntos forman un cuadrilátero convexo (producto cruzado mismo signo en todos los edges).
    private func isConvexQuadrilateral(_ corners: [CGPoint]) -> Bool {
        guard corners.count == 4 else { return false }
        var sign: Bool?
        for i in 0..<4 {
            let a = corners[i]
            let b = corners[(i + 1) % 4]
            let c = corners[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cross) < 1e-6 { continue } // colineales, ignorar
            let positive = cross > 0
            if let s = sign {
                if s != positive { return false }
            } else {
                sign = positive
            }
        }
        return sign != nil
    }

    private func applyPerspectiveTransform(_ image: UIImage, to corners: [CGPoint], in rect: CGRect) -> UIImage? {
        guard corners.count == 4,
              isConvexQuadrilateral(corners),
              let ciImage = CIImage(image: image) else { return nil }

        let imgW = ciImage.extent.width
        let imgH = ciImage.extent.height

        // Corners relativos al bounding rect, convertidos a coordenadas CI (Y invertida)
        let minX = rect.minX
        let minY = rect.minY
        let h = rect.height

        let tl = CIVector(x: CGFloat(corners[0].x - minX), y: CGFloat(h - (corners[0].y - minY)))
        let tr = CIVector(x: CGFloat(corners[1].x - minX), y: CGFloat(h - (corners[1].y - minY)))
        let br = CIVector(x: CGFloat(corners[2].x - minX), y: CGFloat(h - (corners[2].y - minY)))
        let bl = CIVector(x: CGFloat(corners[3].x - minX), y: CGFloat(h - (corners[3].y - minY)))

        // Primero escalar la imagen al tamano del bounding rect
        let scaleX = rect.width / imgW
        let scaleY = rect.height / imgH
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let filter = CIFilter(name: "CIPerspectiveTransform") else { return nil }
        filter.setValue(scaled, forKey: kCIInputImageKey)
        filter.setValue(tl, forKey: "inputTopLeft")
        filter.setValue(tr, forKey: "inputTopRight")
        filter.setValue(br, forKey: "inputBottomRight")
        filter.setValue(bl, forKey: "inputBottomLeft")

        guard let output = filter.outputImage else { return nil }
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Plane Overlay

/// Dibuja el contorno de un plano detectado sobre la imagen offsite.
struct PlaneOverlayView: View {
    let plane: OffsitePlaneData
    let isSelected: Bool
    let imageSize: CGSize
    let scale: CGFloat
    let offset: CGPoint
    let showDimensions: Bool
    var overlayScale: CGFloat = 1.0
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
                        lineWidth: (isSelected ? 3 : AppConstants.OffsiteEditor.planeOutlineLineWidth) * overlayScale,
                        dash: isSelected ? [] : [8 * overlayScale, 4 * overlayScale]
                    )
                )
            }
            
            // Etiqueta de dimensiones
            if showDimensions, vertices.count >= 2 {
                let center = centroid(vertices)
                VStack(spacing: 2) {
                    Text(plane.classification.displayName)
                        .font(.system(size: 10 * overlayScale))
                        .fontWeight(.bold)
                    Text(plane.dimensionsText)
                        .font(.system(size: 12 * overlayScale))
                        .fontWeight(.semibold)
                    if plane.isVertical {
                        Text(String(format: "%.1f m²", plane.widthMeters * plane.heightMeters))
                            .font(.system(size: 10 * overlayScale))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8 * overlayScale)
                .padding(.vertical, 4 * overlayScale)
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
    var overlayScale: CGFloat = 1.0

    var body: some View {
        let pos = CGPoint(
            x: corner.position2D.x * imageSize.width * scale + offset.x,
            y: corner.position2D.y * imageSize.height * scale + offset.y
        )

        ZStack {
            Image(systemName: "angle")
                .font(.system(size: 14 * overlayScale, weight: .bold))
                .foregroundStyle(.yellow)
                .padding(4 * overlayScale)
                .background(Color.black.opacity(0.7), in: Circle())
                .position(pos)

            Text(String(format: "%.0f°", corner.angleDegrees))
                .font(.system(size: 10 * overlayScale, weight: .bold))
                .foregroundStyle(.yellow)
                .padding(.horizontal, 4 * overlayScale)
                .padding(.vertical, 2 * overlayScale)
                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                .position(x: pos.x + 20 * overlayScale, y: pos.y - 16 * overlayScale)
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
    var overlayScale: CGFloat = 1.0
    
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
                .stroke(Color.orange, style: StrokeStyle(lineWidth: AppConstants.OffsiteEditor.planeDimensionLineWidth * overlayScale))

                // Etiqueta ancho
                Text(unit.format(distanceMeters: Float(wall.widthMeters)))
                    .font(.system(size: 10 * overlayScale, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4 * overlayScale)
                    .padding(.vertical, 2 * overlayScale)
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
                .stroke(Color.orange, style: StrokeStyle(lineWidth: AppConstants.OffsiteEditor.planeDimensionLineWidth * overlayScale))

                // Etiqueta alto
                Text(unit.format(distanceMeters: Float(wall.heightMeters)))
                    .font(.system(size: 10 * overlayScale, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4 * overlayScale)
                    .padding(.vertical, 2 * overlayScale)
                    .background(Color.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                    .position(leftMid)

                // Área
                let center = CGPoint(
                    x: (vertices[0].x + vertices[1].x + vertices[2].x + vertices[3].x) / 4,
                    y: (vertices[0].y + vertices[1].y + vertices[2].y + vertices[3].y) / 4
                )

                Text(String(format: "%.1f m²", wall.widthMeters * wall.heightMeters))
                    .font(.system(size: 10 * overlayScale, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6 * overlayScale)
                    .padding(.vertical, 3 * overlayScale)
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
    let loadedImage: UIImage?
    var overlayScale: CGFloat = 1.0
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
                if let uiImage = loadedImage {
                    let minX = corners.map(\.x).min() ?? 0
                    let maxX = corners.map(\.x).max() ?? 0
                    let minY = corners.map(\.y).min() ?? 0
                    let maxY = corners.map(\.y).max() ?? 0
                    let boundingRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

                    // Intentar transformacion con perspectiva real via Core Image
                    if let transformed = PerspectiveImageCache.shared.image(
                        for: frame.id, sourceImage: uiImage,
                        corners: corners, boundingRect: boundingRect
                    ) {
                        Image(uiImage: transformed)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: boundingRect.width, height: boundingRect.height)
                            .clipShape(PerspectiveShape(corners: corners))
                            .position(x: boundingRect.midX, y: boundingRect.midY)
                    } else {
                        // Fallback: clip sin transformacion
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: boundingRect.width, height: boundingRect.height)
                            .clipShape(PerspectiveShape(corners: corners))
                            .position(x: boundingRect.midX, y: boundingRect.midY)
                    }
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
                    lineWidth: (isSelected ? 4 : 2) * overlayScale
                )

                // Etiqueta
                let center = CGPoint(
                    x: corners.reduce(0) { $0 + $1.x } / 4,
                    y: corners.reduce(0) { $0 + $1.y } / 4
                )

                VStack(spacing: 1) {
                    if let label = frame.label {
                        Text(label)
                            .font(.system(size: 10 * overlayScale))
                            .fontWeight(.semibold)
                    }
                    Text(String(format: "%.2f × %.2f m", frame.widthMeters, frame.heightMeters))
                        .font(.system(size: 10 * overlayScale))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6 * overlayScale)
                .padding(.vertical, 3 * overlayScale)
                .background(Color(hex: frame.color).opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                .position(x: center.x, y: (corners.map(\.y).min() ?? center.y) - 16 * overlayScale)

                // Edit mode buttons
                if isEditMode {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20 * overlayScale))
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
                    .stroke(Color.yellow, lineWidth: 3 * overlayScale)
                }
            }
        }
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

/// Overlay de medicion mejorado con indicadores de precision, snap y seleccion.
struct EnhancedMeasurementOverlay: View {
    let measurement: OffsiteMeasurement
    let imageSize: CGSize
    let scale: CGFloat
    let offset: CGPoint
    let unit: MeasurementUnit
    let isEditMode: Bool
    var isSelected: Bool = false
    var overlayScale: CGFloat = 1.0
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
        let glowColor: Color = isSelected ? .yellow : lineColor

        ZStack {
            // Glow / selection highlight
            Path { path in
                path.move(to: pA)
                path.addLine(to: pB)
            }
            .stroke(glowColor.opacity(isSelected ? 0.6 : 0.3), lineWidth: (isSelected ? 8 : (measurement.isFromAR ? 6 : 4)) * overlayScale)

            Path { path in
                path.move(to: pA)
                path.addLine(to: pB)
            }
            .stroke(isSelected ? Color.yellow : lineColor, lineWidth: (measurement.isFromAR ? 2.5 : 2) * overlayScale)

            // Endpoints
            if isSelected {
                DragHandleView(overlayScale: overlayScale)
                    .position(pA)
                DragHandleView(overlayScale: overlayScale)
                    .position(pB)
                // Handle de rotación (perpendicular al midpoint)
                RotationHandleView(overlayScale: overlayScale)
                    .position(rotationHandlePosition(pA: pA, pB: pB))
            } else {
                MeasurementEndpoint(color: .orange, overlayScale: overlayScale)
                    .position(pA)
                MeasurementEndpoint(color: lineColor, overlayScale: overlayScale)
                    .position(pB)
            }

            // Label
            VStack(spacing: 2) {
                Text(unit.format(distanceMeters: Float(measurement.distanceMeters)))
                    .font(.system(size: 12 * overlayScale, weight: .bold))
                    .foregroundStyle(isSelected ? .black : .white)

                HStack(spacing: 4 * overlayScale) {
                    Image(systemName: measurement.isFromAR ? "checkmark.seal.fill" : "wave.3.right")
                        .font(.system(size: 8 * overlayScale))
                    Text(measurement.isFromAR ? "AR precisa" : "~ estimada")
                        .font(.system(size: 9 * overlayScale))
                }
                .foregroundStyle(isSelected ? .black.opacity(0.7) : .white.opacity(0.85))
            }
            .padding(.horizontal, 10 * overlayScale)
            .padding(.vertical, 5 * overlayScale)
            .background(isSelected ? Color.yellow.opacity(0.9) : labelBg, in: RoundedRectangle(cornerRadius: 8))
            .position(x: (pA.x + pB.x) / 2, y: (pA.y + pB.y) / 2 - 22 * overlayScale)

            // Línea punteada desde midpoint al handle de rotación
            if isSelected {
                let mid = CGPoint(x: (pA.x + pB.x) / 2, y: (pA.y + pB.y) / 2)
                let rPos = rotationHandlePosition(pA: pA, pB: pB)
                Path { path in
                    path.move(to: mid)
                    path.addLine(to: rPos)
                }
                .stroke(Color.orange.opacity(0.5), style: StrokeStyle(lineWidth: 1.5 * overlayScale, dash: [4 * overlayScale, 3 * overlayScale]))
            }

            if isEditMode && !isSelected {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20 * overlayScale))
                        .foregroundStyle(.red)
                        .background(Circle().fill(.white))
                }
                .position(x: (pA.x + pB.x) / 2 + 50 * overlayScale, y: (pA.y + pB.y) / 2 - 22 * overlayScale)
            }
        }
    }

    private func rotationHandlePosition(pA: CGPoint, pB: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (pA.x + pB.x) / 2, y: (pA.y + pB.y) / 2)
        let dx = pB.x - pA.x
        let dy = pB.y - pA.y
        let len = hypot(dx, dy)
        guard len > 1 else { return CGPoint(x: mid.x, y: mid.y - 30) }
        let perpX = -dy / len * 30  // 30pt perpendicular
        let perpY = dx / len * 30
        return CGPoint(x: mid.x + perpX, y: mid.y + perpY)
    }
}

/// Handle de rotación para mediciones.
struct RotationHandleView: View {
    var overlayScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.3))
                .frame(width: 28 * overlayScale, height: 28 * overlayScale)
            Circle()
                .fill(Color.orange)
                .frame(width: 18 * overlayScale, height: 18 * overlayScale)
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10 * overlayScale, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// Endpoint de medición mejorado.
struct MeasurementEndpoint: View {
    let color: Color
    var overlayScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 18 * overlayScale, height: 18 * overlayScale)
            Circle()
                .fill(color)
                .frame(width: 10 * overlayScale, height: 10 * overlayScale)
            Circle()
                .stroke(Color.white, lineWidth: 1.5 * overlayScale)
                .frame(width: 10 * overlayScale, height: 10 * overlayScale)
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

// MARK: - Drag Handle

/// Handle visual de drag: circulo amarillo con icono de flechas.
struct DragHandleView: View {
    var overlayScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.yellow)
                .frame(
                    width: AppConstants.OffsiteEditor.dragHandleSize * overlayScale,
                    height: AppConstants.OffsiteEditor.dragHandleSize * overlayScale
                )
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 12 * overlayScale, weight: .bold))
                .foregroundStyle(.black)
        }
    }
}

// MARK: - Resize Handle

/// Handle visual de resize: circulo blanco con icono de diagonal.
struct ResizeHandleView: View {
    var overlayScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 22 * overlayScale, height: 22 * overlayScale)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10 * overlayScale, weight: .bold))
                .foregroundStyle(.blue)
        }
    }
}
