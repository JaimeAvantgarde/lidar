//
//  FloorPlanModels.swift
//  lidar
//
//  Modelos de datos para la generación de planos 2D (vista cenital).
//

import Foundation
import CoreGraphics

// MARK: - Wall Segment

/// Segmento de pared en el plano XZ (vista cenital, coordenadas en metros).
struct FloorPlanWallSegment: Identifiable, Equatable {
    let id: UUID
    /// Punto inicial en metros (plano XZ)
    var start: CGPoint
    /// Punto final en metros (plano XZ)
    var end: CGPoint
    /// Grosor de la pared en metros
    let thickness: CGFloat
    /// Clasificación semántica del plano original
    let classification: PlaneClassification
    /// Ancho real del plano (metros)
    let widthMeters: CGFloat
    /// Alto real del plano (metros)
    let heightMeters: CGFloat
    /// ID del plano AR original (para corner snapping)
    let planeId: String?

    init(id: UUID = UUID(), start: CGPoint, end: CGPoint, thickness: CGFloat = 0.15, classification: PlaneClassification = .wall, widthMeters: CGFloat = 0, heightMeters: CGFloat = 0, planeId: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.thickness = thickness
        self.classification = classification
        self.widthMeters = widthMeters
        self.heightMeters = heightMeters
        self.planeId = planeId
    }

    /// Longitud del segmento en metros.
    var length: CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    /// Punto medio del segmento.
    var midpoint: CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    /// Ángulo del segmento en radianes.
    var angle: CGFloat {
        atan2(end.y - start.y, end.x - start.x)
    }
}

// MARK: - Room Summary (for Floor Plan)

/// Resumen de la habitación calculado desde los planos detectados.
struct FloorPlanRoomSummary: Equatable {
    /// Ancho estimado en metros
    let width: Float
    /// Largo estimado en metros
    let length: Float
    /// Alto estimado en metros
    let height: Float
    /// Número de paredes detectadas
    let wallCount: Int
    /// Número de puertas detectadas
    let doorCount: Int
    /// Número de ventanas detectadas
    let windowCount: Int

    /// Área estimada en m²
    var area: Float { width * length }
    /// Perímetro estimado en metros
    var perimeter: Float { 2 * (width + length) }

    var description: String {
        String(format: "%.1f × %.1f m · %.1f m²", width, length, area)
    }
}

// MARK: - Floor Plan Data

/// Datos completos del plano 2D generado.
struct FloorPlanData: Equatable {
    /// Segmentos de pared
    var walls: [FloorPlanWallSegment]
    /// Segmentos clasificados como puerta
    var doors: [FloorPlanWallSegment]
    /// Segmentos clasificados como ventana
    var windows: [FloorPlanWallSegment]
    /// Bounding box en metros (plano XZ)
    let bounds: CGRect
    /// Resumen de habitación (opcional)
    let roomSummary: FloorPlanRoomSummary?

    /// Todos los segmentos combinados.
    var allSegments: [FloorPlanWallSegment] {
        walls + doors + windows
    }

    /// True si hay datos suficientes para mostrar.
    var isEmpty: Bool {
        walls.isEmpty && doors.isEmpty && windows.isEmpty
    }
}
