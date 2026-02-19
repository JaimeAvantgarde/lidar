//
//  FloorPlanGenerator.swift
//  lidar
//
//  Genera un plano 2D (vista cenital) a partir de planos AR detectados o datos offsite.
//

import Foundation
import ARKit
import CoreGraphics

enum FloorPlanGenerator {

    // MARK: - Generación desde sesión AR live

    /// Genera un FloorPlanData desde los planos detectados en la sesión AR.
    static func generate(from planes: [ARPlaneAnchor], classifyPlane: (ARPlaneAnchor) -> PlaneClassification, roomSummary: RoomSummary? = nil) -> FloorPlanData {
        // Filtrar solo planos verticales
        let verticalPlanes = planes.filter { $0.alignment == .vertical }
        guard !verticalPlanes.isEmpty else {
            return FloorPlanData(walls: [], doors: [], windows: [], bounds: .zero, roomSummary: nil)
        }

        var wallSegments: [FloorPlanWallSegment] = []
        var doorSegments: [FloorPlanWallSegment] = []
        var windowSegments: [FloorPlanWallSegment] = []

        for plane in verticalPlanes {
            let t = plane.transform
            // Centro del plano en coordenadas mundo (X, Z para vista cenital)
            let centerX = CGFloat(t.columns.3.x)
            let centerZ = CGFloat(t.columns.3.z)

            // Dirección horizontal del plano (columns.0 = eje X local del anchor)
            let dirX = CGFloat(t.columns.0.x)
            let dirZ = CGFloat(t.columns.0.z)
            let dirLen = hypot(dirX, dirZ)
            guard dirLen > 0.001 else { continue }
            let normDirX = dirX / dirLen
            let normDirZ = dirZ / dirLen

            // Half extent horizontal
            let halfExtent = CGFloat(plane.extent.x) / 2.0

            let start = CGPoint(
                x: centerX - normDirX * halfExtent,
                y: centerZ - normDirZ * halfExtent
            )
            let end = CGPoint(
                x: centerX + normDirX * halfExtent,
                y: centerZ + normDirZ * halfExtent
            )

            let classification = classifyPlane(plane)
            let segment = FloorPlanWallSegment(
                start: start,
                end: end,
                thickness: AppConstants.FloorPlan.defaultWallThickness,
                classification: classification,
                widthMeters: CGFloat(plane.extent.x),
                heightMeters: CGFloat(plane.extent.z)
            )

            switch classification {
            case .door:
                doorSegments.append(segment)
            case .window:
                windowSegments.append(segment)
            default:
                wallSegments.append(segment)
            }
        }

        let allSegments = wallSegments + doorSegments + windowSegments
        let bounds = computeBounds(segments: allSegments)

        let floorPlanSummary: FloorPlanRoomSummary?
        if let rs = roomSummary {
            floorPlanSummary = FloorPlanRoomSummary(
                width: rs.width,
                length: rs.length,
                height: rs.height,
                wallCount: wallSegments.count,
                doorCount: doorSegments.count,
                windowCount: windowSegments.count
            )
        } else {
            floorPlanSummary = FloorPlanRoomSummary(
                width: Float(bounds.width),
                length: Float(bounds.height),
                height: 0,
                wallCount: wallSegments.count,
                doorCount: doorSegments.count,
                windowCount: windowSegments.count
            )
        }

        return FloorPlanData(
            walls: wallSegments,
            doors: doorSegments,
            windows: windowSegments,
            bounds: bounds,
            roomSummary: floorPlanSummary
        )
    }

    // MARK: - Generación desde datos offsite

    /// Genera un FloorPlanData desde datos de planos guardados en una captura offsite.
    static func generate(from planes: [OffsitePlaneData]) -> FloorPlanData {
        // Filtrar solo planos verticales
        let verticalPlanes = planes.filter { $0.isVertical }
        guard !verticalPlanes.isEmpty else {
            return FloorPlanData(walls: [], doors: [], windows: [], bounds: .zero, roomSummary: nil)
        }

        var wallSegments: [FloorPlanWallSegment] = []
        var doorSegments: [FloorPlanWallSegment] = []
        var windowSegments: [FloorPlanWallSegment] = []

        for plane in verticalPlanes {
            guard plane.transform.count == 16 else { continue }

            // Reconstruir la posición y dirección desde el transform
            let centerX = CGFloat(plane.transform[12]) // columns.3.x
            let centerZ = CGFloat(plane.transform[14]) // columns.3.z

            // Dirección horizontal: columns.0 (eje X del anchor)
            let dirX = CGFloat(plane.transform[0])  // columns.0.x
            let dirZ = CGFloat(plane.transform[2])  // columns.0.z
            let dirLen = hypot(dirX, dirZ)
            guard dirLen > 0.001 else { continue }
            let normDirX = dirX / dirLen
            let normDirZ = dirZ / dirLen

            let halfExtent = CGFloat(plane.extentX) / 2.0

            let start = CGPoint(
                x: centerX - normDirX * halfExtent,
                y: centerZ - normDirZ * halfExtent
            )
            let end = CGPoint(
                x: centerX + normDirX * halfExtent,
                y: centerZ + normDirZ * halfExtent
            )

            let segment = FloorPlanWallSegment(
                start: start,
                end: end,
                thickness: AppConstants.FloorPlan.defaultWallThickness,
                classification: plane.classification,
                widthMeters: CGFloat(plane.extentX),
                heightMeters: CGFloat(plane.extentZ)
            )

            switch plane.classification {
            case .door:
                doorSegments.append(segment)
            case .window:
                windowSegments.append(segment)
            default:
                wallSegments.append(segment)
            }
        }

        let allSegments = wallSegments + doorSegments + windowSegments
        let bounds = computeBounds(segments: allSegments)

        let summary = FloorPlanRoomSummary(
            width: Float(bounds.width),
            length: Float(bounds.height),
            height: 0,
            wallCount: wallSegments.count,
            doorCount: doorSegments.count,
            windowCount: windowSegments.count
        )

        return FloorPlanData(
            walls: wallSegments,
            doors: doorSegments,
            windows: windowSegments,
            bounds: bounds,
            roomSummary: summary
        )
    }

    // MARK: - Helpers

    /// Calcula el bounding box de todos los segmentos con padding.
    private static func computeBounds(segments: [FloorPlanWallSegment]) -> CGRect {
        guard !segments.isEmpty else { return .zero }

        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity

        for seg in segments {
            minX = min(minX, seg.start.x, seg.end.x)
            minY = min(minY, seg.start.y, seg.end.y)
            maxX = max(maxX, seg.start.x, seg.end.x)
            maxY = max(maxY, seg.start.y, seg.end.y)
        }

        let padding = AppConstants.FloorPlan.boundsPadding
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + 2 * padding,
            height: (maxY - minY) + 2 * padding
        )
    }
}
