//
//  FloorPlanView.swift
//  lidar
//
//  Vista 2D cenital del plano generado desde planos AR detectados.
//  Usa Canvas para dibujar paredes, puertas, ventanas y dimensiones.
//

import SwiftUI

struct FloorPlanView: View {
    let floorPlanData: FloorPlanData
    @Environment(\.dismiss) private var dismiss
    @State private var showDimensions = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if floorPlanData.isEmpty {
                    ContentUnavailableView(
                        "Sin datos de plano",
                        systemImage: "rectangle.dashed",
                        description: Text("No se detectaron suficientes planos verticales para generar un plano 2D.")
                    )
                } else {
                    GeometryReader { geo in
                        Canvas { context, size in
                            let scale = computeScale(bounds: floorPlanData.bounds, canvasSize: size)
                            let transform = computeTransform(bounds: floorPlanData.bounds, canvasSize: size, scale: scale)

                            // Grid de fondo
                            drawGrid(context: &context, size: size, bounds: floorPlanData.bounds, transform: transform, scale: scale)

                            // Paredes
                            for wall in floorPlanData.walls {
                                drawWallSegment(context: &context, segment: wall, transform: transform, scale: scale, color: .black, lineWidth: max(AppConstants.FloorPlan.minWallLineWidth, CGFloat(wall.thickness) * scale))
                            }

                            // Puertas
                            for door in floorPlanData.doors {
                                drawDoorSegment(context: &context, segment: door, transform: transform, scale: scale)
                            }

                            // Ventanas
                            for window in floorPlanData.windows {
                                drawWindowSegment(context: &context, segment: window, transform: transform, scale: scale)
                            }

                            // Dimensiones
                            if showDimensions {
                                for segment in floorPlanData.allSegments {
                                    drawDimensionLabel(context: &context, segment: segment, transform: transform, scale: scale)
                                }
                            }
                        }
                        .padding(AppConstants.FloorPlan.canvasPadding)

                        // Leyenda
                        VStack(alignment: .leading, spacing: 6) {
                            legendItem(color: .black, label: "Pared")
                            if !floorPlanData.doors.isEmpty {
                                legendItem(color: .brown, label: "Puerta")
                            }
                            if !floorPlanData.windows.isEmpty {
                                legendItem(color: .cyan, label: "Ventana")
                            }
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .position(x: 80, y: geo.size.height - 60)

                        // Resumen de habitación
                        if let summary = floorPlanData.roomSummary {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(summary.description)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                HStack(spacing: 8) {
                                    Label("\(summary.wallCount) paredes", systemImage: "rectangle.portrait")
                                    if summary.doorCount > 0 {
                                        Label("\(summary.doorCount) puertas", systemImage: "door.left.hand.open")
                                    }
                                    if summary.windowCount > 0 {
                                        Label("\(summary.windowCount) ventanas", systemImage: "window.vertical.open")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .position(x: geo.size.width - 100, y: geo.size.height - 60)
                        }
                    }
                }
            }
            .navigationTitle("Plano 2D")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $showDimensions) {
                        Label("Cotas", systemImage: "ruler")
                    }
                    .toggleStyle(.button)
                }

                ToolbarItem(placement: .secondaryAction) {
                    ShareLink(item: renderToImage(), preview: SharePreview("Plano 2D", image: Image(systemName: "map"))) {
                        Label("Exportar", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: - Legend

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 16, height: 3)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Scale & Transform

    /// Calcula la escala para ajustar el bounding box al canvas.
    private func computeScale(bounds: CGRect, canvasSize: CGSize) -> CGFloat {
        guard bounds.width > 0, bounds.height > 0 else { return 1 }
        let padding = AppConstants.FloorPlan.canvasPadding * 2
        let availableW = canvasSize.width - padding
        let availableH = canvasSize.height - padding
        return min(availableW / bounds.width, availableH / bounds.height)
    }

    /// Crea un transform de metros a puntos de canvas.
    private func computeTransform(bounds: CGRect, canvasSize: CGSize, scale: CGFloat) -> CGAffineTransform {
        let padding = AppConstants.FloorPlan.canvasPadding
        let scaledW = bounds.width * scale
        let scaledH = bounds.height * scale
        let offsetX = (canvasSize.width - scaledW) / 2 - bounds.minX * scale
        let offsetY = (canvasSize.height - scaledH) / 2 - bounds.minY * scale
        return CGAffineTransform(translationX: offsetX + padding / 2, y: offsetY + padding / 2)
            .scaledBy(x: scale, y: scale)
    }

    // MARK: - Drawing

    /// Transforma un punto de metros a coordenadas canvas.
    private func transformPoint(_ point: CGPoint, transform: CGAffineTransform, scale: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scale + transform.tx, y: point.y * scale + transform.ty)
    }

    /// Dibuja un segmento de pared como línea gruesa.
    private func drawWallSegment(context: inout GraphicsContext, segment: FloorPlanWallSegment, transform: CGAffineTransform, scale: CGFloat, color: Color, lineWidth: CGFloat) {
        let start = transformPoint(segment.start, transform: transform, scale: scale)
        let end = transformPoint(segment.end, transform: transform, scale: scale)

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    /// Dibuja un segmento de puerta: línea discontinua marrón + arco.
    private func drawDoorSegment(context: inout GraphicsContext, segment: FloorPlanWallSegment, transform: CGAffineTransform, scale: CGFloat) {
        let start = transformPoint(segment.start, transform: transform, scale: scale)
        let end = transformPoint(segment.end, transform: transform, scale: scale)
        let doorWidth = hypot(end.x - start.x, end.y - start.y)

        // Línea discontinua
        var linePath = Path()
        linePath.move(to: start)
        linePath.addLine(to: end)
        context.stroke(linePath, with: .color(.brown), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 4]))

        // Arco de apertura
        let startAngle = Angle(radians: Double(atan2(end.y - start.y, end.x - start.x)))
        var arcPath = Path()
        arcPath.addArc(center: start, radius: doorWidth, startAngle: startAngle, endAngle: startAngle - .degrees(90), clockwise: true)
        context.stroke(arcPath, with: .color(.brown.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5))
    }

    /// Dibuja un segmento de ventana: 3 líneas paralelas cyan.
    private func drawWindowSegment(context: inout GraphicsContext, segment: FloorPlanWallSegment, transform: CGAffineTransform, scale: CGFloat) {
        let start = transformPoint(segment.start, transform: transform, scale: scale)
        let end = transformPoint(segment.end, transform: transform, scale: scale)

        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = hypot(dx, dy)
        guard len > 0 else { return }

        // Perpendicular normalizada
        let perpX = -dy / len * 3
        let perpY = dx / len * 3

        for offset in [-1.0, 0.0, 1.0] {
            let ox = perpX * CGFloat(offset)
            let oy = perpY * CGFloat(offset)
            var path = Path()
            path.move(to: CGPoint(x: start.x + ox, y: start.y + oy))
            path.addLine(to: CGPoint(x: end.x + ox, y: end.y + oy))
            context.stroke(path, with: .color(.cyan), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    /// Dibuja una etiqueta de dimensión perpendicular al segmento.
    private func drawDimensionLabel(context: inout GraphicsContext, segment: FloorPlanWallSegment, transform: CGAffineTransform, scale: CGFloat) {
        let start = transformPoint(segment.start, transform: transform, scale: scale)
        let end = transformPoint(segment.end, transform: transform, scale: scale)

        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = hypot(dx, dy)
        guard len > 20 else { return } // No mostrar si el segmento es muy corto en pantalla

        // Offset perpendicular al segmento
        let perpX = -dy / len * AppConstants.FloorPlan.dimensionLabelOffset
        let perpY = dx / len * AppConstants.FloorPlan.dimensionLabelOffset
        let labelPos = CGPoint(x: mid.x + perpX, y: mid.y + perpY)

        let label = String(format: "%.2f m", segment.length)
        let text = Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.secondary)

        context.draw(context.resolve(text), at: labelPos, anchor: .center)
    }

    /// Dibuja la cuadrícula de fondo (1m de espaciado).
    private func drawGrid(context: inout GraphicsContext, size: CGSize, bounds: CGRect, transform: CGAffineTransform, scale: CGFloat) {
        let spacing = AppConstants.FloorPlan.gridSpacing
        let gridColor = Color.gray.opacity(0.15)

        let startX = floor(bounds.minX / spacing) * spacing
        let endX = ceil(bounds.maxX / spacing) * spacing
        let startY = floor(bounds.minY / spacing) * spacing
        let endY = ceil(bounds.maxY / spacing) * spacing

        // Líneas verticales
        var x = startX
        while x <= endX {
            let screenX = x * scale + transform.tx
            var path = Path()
            path.move(to: CGPoint(x: screenX, y: 0))
            path.addLine(to: CGPoint(x: screenX, y: size.height))
            context.stroke(path, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5))
            x += spacing
        }

        // Líneas horizontales
        var y = startY
        while y <= endY {
            let screenY = y * scale + transform.ty
            var path = Path()
            path.move(to: CGPoint(x: 0, y: screenY))
            path.addLine(to: CGPoint(x: size.width, y: screenY))
            context.stroke(path, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5))
            y += spacing
        }
    }

    // MARK: - Export

    /// Renderiza el plano a una imagen para compartir.
    @MainActor
    private func renderToImage() -> Image {
        let exportSize = AppConstants.FloorPlan.exportImageSize
        let renderer = ImageRenderer(content:
            Canvas { context, size in
                let scale = computeScale(bounds: floorPlanData.bounds, canvasSize: size)
                let transform = computeTransform(bounds: floorPlanData.bounds, canvasSize: size, scale: scale)

                drawGrid(context: &context, size: size, bounds: floorPlanData.bounds, transform: transform, scale: scale)

                for wall in floorPlanData.walls {
                    drawWallSegment(context: &context, segment: wall, transform: transform, scale: scale, color: .black, lineWidth: max(AppConstants.FloorPlan.minWallLineWidth, CGFloat(wall.thickness) * scale))
                }
                for door in floorPlanData.doors {
                    drawDoorSegment(context: &context, segment: door, transform: transform, scale: scale)
                }
                for window in floorPlanData.windows {
                    drawWindowSegment(context: &context, segment: window, transform: transform, scale: scale)
                }
                if showDimensions {
                    for segment in floorPlanData.allSegments {
                        drawDimensionLabel(context: &context, segment: segment, transform: transform, scale: scale)
                    }
                }
            }
            .frame(width: exportSize, height: exportSize)
            .background(Color.white)
        )
        renderer.scale = 2.0

        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "map")
    }
}
