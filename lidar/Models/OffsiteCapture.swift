//
//  OffsiteCapture.swift
//  lidar
//
//  Modelo para captura offsite: imagen + mediciones + anotaciones con posiciones 2D normalizadas (0–1).
//

import Foundation
import UIKit

// MARK: - Offsite Capture Entry

/// Entrada de una captura offsite (imagen + JSON con mismo nombre base).
/// Usado para listar capturas en la UI.
struct OffsiteCaptureEntry: Identifiable, Hashable {
    let id: String
    let imageURL: URL
    let jsonURL: URL
    let capturedAt: Date

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: OffsiteCaptureEntry, rhs: OffsiteCaptureEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Normalized Point

/// Posición 2D normalizada en la imagen (0–1). x = 0 izquierda, 1 derecha; y = 0 arriba, 1 abajo.
struct NormalizedPoint: Codable, Equatable, Hashable {
    let x: Double
    let y: Double

    /// Valida que el punto esté dentro del rango normalizado [0, 1].
    var isValid: Bool {
        (0...1).contains(x) && (0...1).contains(y)
    }
}

// MARK: - Offsite Measurement
struct OffsiteMeasurement: Codable, Identifiable, Hashable {
    var id: UUID
    var distanceMeters: Double
    var pointA: NormalizedPoint
    var pointB: NormalizedPoint
    let isFromAR: Bool  // true = medición AR original (precisa), false = añadida offsite (aproximada)

    init(id: UUID = UUID(), distanceMeters: Double, pointA: NormalizedPoint, pointB: NormalizedPoint, isFromAR: Bool = true) {
        self.id = id
        self.distanceMeters = distanceMeters
        self.pointA = pointA
        self.pointB = pointB
        self.isFromAR = isFromAR
    }
}

/// Rectángulo/cuadro anotado sobre la imagen offsite.
struct OffsiteFrame: Codable, Identifiable, Hashable {
    var id: UUID
    var topLeft: NormalizedPoint
    var width: Double  // Normalizado 0-1 (posición en imagen)
    var height: Double // Normalizado 0-1 (posición en imagen)
    var label: String?
    var color: String  // Hex color (#RRGGBB)
    
    // Nuevos campos: dimensiones reales del cuadro
    var widthMeters: Double?  // Ancho real en metros
    var heightMeters: Double? // Alto real en metros
    var imageBase64: String?  // Imagen del cuadro en base64 (legacy)
    var imageFilename: String?  // Nombre del archivo de imagen separado
    var isCornerFrame: Bool   // Si es cuadro de esquina
    
    init(id: UUID = UUID(), topLeft: NormalizedPoint, width: Double, height: Double, label: String? = nil, color: String = "#3B82F6", widthMeters: Double? = nil, heightMeters: Double? = nil, imageBase64: String? = nil, imageFilename: String? = nil, isCornerFrame: Bool = false) {
        self.id = id
        self.topLeft = topLeft
        self.width = width
        self.height = height
        self.label = label
        self.color = color
        self.widthMeters = widthMeters
        self.heightMeters = heightMeters
        self.imageBase64 = imageBase64
        self.imageFilename = imageFilename
        self.isCornerFrame = isCornerFrame
    }
}

/// Anotación de texto sobre la imagen.
struct OffsiteTextAnnotation: Codable, Identifiable, Hashable {
    var id: UUID
    var position: NormalizedPoint
    var text: String
    var color: String  // Hex color
    
    init(id: UUID = UUID(), position: NormalizedPoint, text: String, color: String = "#FFFFFF") {
        self.id = id
        self.position = position
        self.text = text
        self.color = color
    }
}

/// Dimensiones de un plano detectado por LiDAR
struct PlaneDimension: Codable, Equatable, Hashable {
    let width: Double
    let height: Double
}

/// Metadata del LiDAR capturado (dimensiones de planos detectados)
struct OffsiteLiDARMetadata: Codable, Equatable, Hashable {
    let isLiDARAvailable: Bool
    let planeCount: Int
    let planeDimensions: [PlaneDimension]  // En metros
    
    init(isLiDARAvailable: Bool, planeCount: Int, planeDimensions: [PlaneDimension]) {
        self.isLiDARAvailable = isLiDARAvailable
        self.planeCount = planeCount
        self.planeDimensions = planeDimensions
    }
}

/// Datos de una captura offsite (JSON). La imagen se guarda con el mismo nombre base y extensión .jpg.
struct OffsiteCaptureData: Codable, Equatable {
    let capturedAt: Date
    var measurements: [OffsiteMeasurement]
    var frames: [OffsiteFrame]
    var textAnnotations: [OffsiteTextAnnotation]
    var lastModified: Date?
    var lidarMetadata: OffsiteLiDARMetadata?  // Metadata del LiDAR
    var imageScale: Double  // Escala de la imagen capturada
    /// Snapshot completo de la escena 3D (planos, esquinas, cámara, cuadros con perspectiva)
    var sceneSnapshot: OffsiteSceneSnapshot?

    init(capturedAt: Date = Date(), measurements: [OffsiteMeasurement], frames: [OffsiteFrame] = [], textAnnotations: [OffsiteTextAnnotation] = [], lastModified: Date? = nil, lidarMetadata: OffsiteLiDARMetadata? = nil, imageScale: Double = 1.0, sceneSnapshot: OffsiteSceneSnapshot? = nil) {
        self.capturedAt = capturedAt
        self.measurements = measurements
        self.frames = frames
        self.textAnnotations = textAnnotations
        self.lastModified = lastModified
        self.lidarMetadata = lidarMetadata
        self.imageScale = imageScale
        self.sceneSnapshot = sceneSnapshot
    }
    
    /// Acceso rápido a planos del snapshot
    var detectedPlanes: [OffsitePlaneData] {
        sceneSnapshot?.planes ?? []
    }
    
    /// Acceso rápido a esquinas del snapshot
    var detectedCorners: [OffsiteCornerData] {
        sceneSnapshot?.corners ?? []
    }
    
    /// Acceso rápido a paredes
    var detectedWalls: [OffsitePlaneData] {
        sceneSnapshot?.walls ?? []
    }
    
    /// Acceso rápido a cuadros con perspectiva
    var perspectiveFrames: [OffsiteFramePerspective] {
        sceneSnapshot?.perspectiveFrames ?? []
    }
    
    /// Escala metros/pixel
    var metersPerPixelScale: Double? {
        sceneSnapshot?.metersPerPixelScale
    }
}

// MARK: - Selectable Item Type

/// Tipo de elemento seleccionable en el editor offsite.
enum SelectableItemType: Equatable {
    case measurement(UUID)
    case measurementEndpointA(UUID)
    case measurementEndpointB(UUID)
    case frame(UUID)
    case frameResizeBottomRight(UUID)
    case perspectiveFrame(UUID)
    case textAnnotation(UUID)

    /// UUID del elemento asociado (compartido entre variantes del mismo item).
    var itemId: UUID {
        switch self {
        case .measurement(let id), .measurementEndpointA(let id), .measurementEndpointB(let id),
             .frame(let id), .frameResizeBottomRight(let id),
             .perspectiveFrame(let id), .textAnnotation(let id):
            return id
        }
    }
}
