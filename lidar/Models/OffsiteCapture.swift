//
//  OffsiteCapture.swift
//  lidar
//
//  Modelo para captura offsite: imagen + mediciones + anotaciones con posiciones 2D normalizadas (0–1).
//

import Foundation
import UIKit

/// Posición 2D normalizada en la imagen (0–1). x = 0 izquierda, 1 derecha; y = 0 arriba, 1 abajo.
struct NormalizedPoint: Codable, Equatable, Hashable {
    let x: Double
    let y: Double
}

/// Una medición guardada para offsite: distancia en metros y puntos 2D en la imagen.
struct OffsiteMeasurement: Codable, Identifiable, Hashable {
    var id: UUID
    let distanceMeters: Double
    let pointA: NormalizedPoint
    let pointB: NormalizedPoint
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
    let topLeft: NormalizedPoint
    let width: Double  // Normalizado 0-1
    let height: Double // Normalizado 0-1
    var label: String?
    var color: String  // Hex color (#RRGGBB)
    
    init(id: UUID = UUID(), topLeft: NormalizedPoint, width: Double, height: Double, label: String? = nil, color: String = "#3B82F6") {
        self.id = id
        self.topLeft = topLeft
        self.width = width
        self.height = height
        self.label = label
        self.color = color
    }
}

/// Anotación de texto sobre la imagen.
struct OffsiteTextAnnotation: Codable, Identifiable, Hashable {
    var id: UUID
    let position: NormalizedPoint
    var text: String
    var color: String  // Hex color
    
    init(id: UUID = UUID(), position: NormalizedPoint, text: String, color: String = "#FFFFFF") {
        self.id = id
        self.position = position
        self.text = text
        self.color = color
    }
}

/// Datos de una captura offsite (JSON). La imagen se guarda con el mismo nombre base y extensión .jpg.
struct OffsiteCaptureData: Codable {
    let capturedAt: Date
    var measurements: [OffsiteMeasurement]
    var frames: [OffsiteFrame]
    var textAnnotations: [OffsiteTextAnnotation]
    var lastModified: Date?

    init(capturedAt: Date = Date(), measurements: [OffsiteMeasurement], frames: [OffsiteFrame] = [], textAnnotations: [OffsiteTextAnnotation] = [], lastModified: Date? = nil) {
        self.capturedAt = capturedAt
        self.measurements = measurements
        self.frames = frames
        self.textAnnotations = textAnnotations
        self.lastModified = lastModified
    }
}
