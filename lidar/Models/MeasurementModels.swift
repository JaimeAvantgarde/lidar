//
//  MeasurementModels.swift
//  lidar
//
//  Modelos relacionados con mediciones AR: unidades, mediciones 3D, dimensiones de planos.
//

import Foundation
import simd

// MARK: - Unidad de medida

/// Unidad de medida para distancias
enum MeasurementUnit: String, CaseIterable, Identifiable {
    case meters = "m"
    case feet = "ft"

    var id: String { rawValue }

    /// Formatea una distancia en metros a la unidad seleccionada.
    func format(distanceMeters: Float) -> String {
        switch self {
        case .meters:
            return String(format: "%.2f m", distanceMeters)
        case .feet:
            let ft = distanceMeters * AppConstants.Measurement.feetConversionFactor
            return String(format: "%.2f ft", ft)
        }
    }

    /// Convierte metros a la unidad seleccionada.
    func value(fromMeters meters: Float) -> Float {
        switch self {
        case .meters: return meters
        case .feet: return meters * AppConstants.Measurement.feetConversionFactor
        }
    }
}

// MARK: - Medición AR

/// Una medición entre dos puntos 3D en la escena AR.
struct ARMeasurement: Identifiable, Equatable {
    let id: UUID
    let pointA: SIMD3<Float>
    let pointB: SIMD3<Float>
    let distance: Float

    init(id: UUID = UUID(), pointA: SIMD3<Float>, pointB: SIMD3<Float>, distance: Float) {
        self.id = id
        self.pointA = pointA
        self.pointB = pointB
        self.distance = distance
    }

    static func == (lhs: ARMeasurement, rhs: ARMeasurement) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Dimensiones de plano

/// Dimensiones detectadas de un plano (pared).
struct PlaneDimensions: Equatable {
    let width: Float  // metros
    let height: Float
    let extent: SIMD3<Float>

    static func == (lhs: PlaneDimensions, rhs: PlaneDimensions) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height
    }
}
