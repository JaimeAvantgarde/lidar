//
//  SceneExportModels.swift
//  lidar
//
//  Modelos para exportar toda la escena 3D capturada (planos, esquinas, cámara, etc.)
//  para uso offsite con perspectiva real y medidas precisas.
//

import Foundation
import simd

// MARK: - Camera Data

/// Datos de la cámara al momento de la captura.
/// Permite reconstruir la proyección 3D→2D y calcular perspectiva.
struct OffsiteCameraData: Codable, Equatable {
    /// Intrínsecos de la cámara (3x3 matrix aplanada row-major)
    let intrinsics: [Float]       // 9 valores
    /// Transform de la cámara en el mundo (4x4 matrix aplanada row-major)
    let transform: [Float]        // 16 valores
    /// Resolución de la imagen capturada
    let imageWidth: Int
    let imageHeight: Int
    /// Field of view horizontal en radianes
    let fovHorizontal: Double
    /// Field of view vertical en radianes
    let fovVertical: Double
    
    init(intrinsics: simd_float3x3, transform: simd_float4x4, imageWidth: Int, imageHeight: Int) {
        self.intrinsics = Self.flatten3x3(intrinsics)
        self.transform = Self.flatten4x4(transform)
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        // Calcular FOV a partir de los intrínsecos
        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        self.fovHorizontal = Double(2 * atan(Float(imageWidth) / (2 * fx)))
        self.fovVertical = Double(2 * atan(Float(imageHeight) / (2 * fy)))
    }
    
    // Convenience for re-creating matrices
    var intrinsicsMatrix: simd_float3x3 {
        Self.unflatten3x3(intrinsics)
    }
    
    var transformMatrix: simd_float4x4 {
        Self.unflatten4x4(transform)
    }
    
    private static func flatten3x3(_ m: simd_float3x3) -> [Float] {
        [m.columns.0.x, m.columns.0.y, m.columns.0.z,
         m.columns.1.x, m.columns.1.y, m.columns.1.z,
         m.columns.2.x, m.columns.2.y, m.columns.2.z]
    }
    
    private static func flatten4x4(_ m: simd_float4x4) -> [Float] {
        [m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w,
         m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w,
         m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w,
         m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w]
    }
    
    private static func unflatten3x3(_ a: [Float]) -> simd_float3x3 {
        guard a.count == 9 else { return matrix_identity_float3x3 }
        return simd_float3x3(
            SIMD3<Float>(a[0], a[1], a[2]),
            SIMD3<Float>(a[3], a[4], a[5]),
            SIMD3<Float>(a[6], a[7], a[8])
        )
    }
    
    private static func unflatten4x4(_ a: [Float]) -> simd_float4x4 {
        guard a.count == 16 else { return matrix_identity_float4x4 }
        return simd_float4x4(
            SIMD4<Float>(a[0], a[1], a[2], a[3]),
            SIMD4<Float>(a[4], a[5], a[6], a[7]),
            SIMD4<Float>(a[8], a[9], a[10], a[11]),
            SIMD4<Float>(a[12], a[13], a[14], a[15])
        )
    }
}

// MARK: - Plane Data (Full 3D)

/// Clasificación semántica del plano
enum PlaneClassification: String, Codable, CaseIterable {
    case wall = "wall"
    case floor = "floor"
    case ceiling = "ceiling"
    case door = "door"
    case window = "window"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .wall: return "Pared"
        case .floor: return "Suelo"
        case .ceiling: return "Techo"
        case .door: return "Puerta"
        case .window: return "Ventana"
        case .unknown: return "Desconocido"
        }
    }
    
    var icon: String {
        switch self {
        case .wall: return "rectangle.portrait"
        case .floor: return "square"
        case .ceiling: return "square.tophalf.filled"
        case .door: return "door.left.hand.open"
        case .window: return "window.vertical.open"
        case .unknown: return "questionmark.square"
        }
    }
}

/// Datos completos de un plano detectado por ARKit.
/// Incluye transform 3D, extensión, clasificación y vértices proyectados en 2D.
struct OffsitePlaneData: Codable, Identifiable, Equatable, Hashable {
    let id: String           // ARPlaneAnchor.identifier as string
    let alignment: String    // "vertical", "horizontal"
    let classification: PlaneClassification
    /// Transform del plano en el mundo (4x4 aplanado)
    let transform: [Float]   // 16 valores
    /// Extensión del plano en metros (x = ancho, z = alto para verticales)
    let extentX: Double
    let extentZ: Double
    /// Centro del plano en 3D
    let center3D: [Float]    // 3 valores (x, y, z)
    /// Normal del plano
    let normal: [Float]      // 3 valores
    /// Vértices del contorno del plano proyectados a 2D normalizado (para dibujar en la imagen)
    var projectedVertices: [[Double]]  // Array de [x, y] normalizados 0-1
    /// Ancho real en metros (calculado con mejor precisión)
    let widthMeters: Double
    /// Alto real en metros
    let heightMeters: Double
    
    var transformMatrix: simd_float4x4 {
        OffsiteCameraData.unflatten4x4Private(transform)
    }
    
    var center3DSIMD: SIMD3<Float> {
        guard center3D.count >= 3 else { return .zero }
        return SIMD3<Float>(center3D[0], center3D[1], center3D[2])
    }
    
    var normalSIMD: SIMD3<Float> {
        guard normal.count >= 3 else { return SIMD3<Float>(0, 0, 1) }
        return SIMD3<Float>(normal[0], normal[1], normal[2])
    }
    
    var isVertical: Bool { alignment == "vertical" }
    var isHorizontal: Bool { alignment == "horizontal" }
    
    /// Dimensiones formateadas
    var dimensionsText: String {
        String(format: "%.2f × %.2f m", widthMeters, heightMeters)
    }
}

// Helper extension for unflatten used in OffsitePlaneData
private extension OffsiteCameraData {
    static func unflatten4x4Private(_ a: [Float]) -> simd_float4x4 {
        guard a.count == 16 else { return matrix_identity_float4x4 }
        return simd_float4x4(
            SIMD4<Float>(a[0], a[1], a[2], a[3]),
            SIMD4<Float>(a[4], a[5], a[6], a[7]),
            SIMD4<Float>(a[8], a[9], a[10], a[11]),
            SIMD4<Float>(a[12], a[13], a[14], a[15])
        )
    }
}

// MARK: - Corner Data

/// Esquina detectada entre dos planos (intersección de paredes).
struct OffsiteCornerData: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    /// Posición 3D de la esquina
    let position3D: [Float]   // 3 valores
    /// Posición 2D normalizada en la imagen
    let position2D: NormalizedPoint
    /// Ángulo entre los dos planos en grados
    let angleDegrees: Double
    /// IDs de los dos planos que forman la esquina
    let planeIdA: String
    let planeIdB: String
    
    init(id: UUID = UUID(), position3D: SIMD3<Float>, position2D: NormalizedPoint, angleDegrees: Double, planeIdA: String, planeIdB: String) {
        self.id = id
        self.position3D = [position3D.x, position3D.y, position3D.z]
        self.position2D = position2D
        self.angleDegrees = angleDegrees
        self.planeIdA = planeIdA
        self.planeIdB = planeIdB
    }
    
    var position3DSIMD: SIMD3<Float> {
        guard position3D.count >= 3 else { return .zero }
        return SIMD3<Float>(position3D[0], position3D[1], position3D[2])
    }
}

// MARK: - Wall Dimension

/// Dimensiones completas de una pared con referencia de suelo y techo.
struct OffsiteWallDimension: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let planeId: String
    let widthMeters: Double
    let heightMeters: Double
    let areaSquareMeters: Double
    /// Vértices 2D del contorno de la pared (para dibujar overlay)
    let vertices2D: [[Double]]  // Array de [x, y] normalizados
    
    init(id: UUID = UUID(), planeId: String, widthMeters: Double, heightMeters: Double, vertices2D: [[Double]]) {
        self.id = id
        self.planeId = planeId
        self.widthMeters = widthMeters
        self.heightMeters = heightMeters
        self.areaSquareMeters = widthMeters * heightMeters
        self.vertices2D = vertices2D
    }
}

// MARK: - Offsite Frame (Enhanced)

/// Cuadro colocado con datos de perspectiva del plano.
struct OffsiteFramePerspective: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    /// ID del plano donde está colocado
    var planeId: String?
    /// Posición 2D normalizada del centro en la imagen
    var center2D: NormalizedPoint
    /// Esquinas del cuadro en 2D (4 puntos con perspectiva del plano)
    var corners2D: [[Double]]  // 4 puntos [x, y] normalizados
    /// Dimensiones reales en metros
    var widthMeters: Double
    var heightMeters: Double
    /// Imagen en base64 (legacy)
    var imageBase64: String?
    /// Nombre del archivo de imagen separado
    var imageFilename: String?
    /// Label del cuadro
    var label: String?
    /// Color del borde
    var color: String

    init(id: UUID = UUID(), planeId: String? = nil, center2D: NormalizedPoint, corners2D: [[Double]], widthMeters: Double, heightMeters: Double, imageBase64: String? = nil, imageFilename: String? = nil, label: String? = nil, color: String = "#3B82F6") {
        self.id = id
        self.planeId = planeId
        self.center2D = center2D
        self.corners2D = corners2D
        self.widthMeters = widthMeters
        self.heightMeters = heightMeters
        self.imageBase64 = imageBase64
        self.imageFilename = imageFilename
        self.label = label
        self.color = color
    }
}

// MARK: - Scene Snapshot

/// Snapshot completo de la escena 3D para uso offsite.
/// Contiene TODA la información necesaria para reconstruir y editar la escena sin AR.
struct OffsiteSceneSnapshot: Codable, Equatable {
    let capturedAt: Date
    /// Datos de la cámara
    let camera: OffsiteCameraData?
    /// Todos los planos detectados con sus datos completos
    var planes: [OffsitePlaneData]
    /// Todas las esquinas detectadas
    var corners: [OffsiteCornerData]
    /// Dimensiones de paredes
    var wallDimensions: [OffsiteWallDimension]
    /// Mediciones (incluye AR y offsite)
    var measurements: [OffsiteMeasurement]
    /// Cuadros con perspectiva
    var perspectiveFrames: [OffsiteFramePerspective]
    /// Cuadros simples (compatibilidad)
    var frames: [OffsiteFrame]
    /// Anotaciones de texto
    var textAnnotations: [OffsiteTextAnnotation]
    /// Metadata del LiDAR
    let lidarMetadata: OffsiteLiDARMetadata?
    /// Escala de la imagen capturada
    let imageScale: Double
    /// Última modificación
    var lastModified: Date?
    /// Nombre del archivo del depth map (opcional, para escala local por profundidad)
    var depthMapFilename: String?
    /// Ancho del depth map en pixeles
    var depthMapWidth: Int?
    /// Alto del depth map en pixeles
    var depthMapHeight: Int?
    
    /// Escala metros/pixel calculada promediando TODAS las mediciones AR.
    /// Convierte coordenadas normalizadas a pixeles reales (usando camera.imageWidth/Height)
    /// para respetar el aspect ratio antes de calcular.
    var metersPerPixelScale: Double? {
        let arMeasurements = measurements.filter { $0.isFromAR }
        guard !arMeasurements.isEmpty else { return nil }
        let imgW = Double(camera?.imageWidth ?? 0)
        let imgH = Double(camera?.imageHeight ?? 0)
        guard imgW > 0, imgH > 0 else { return nil }

        var totalScale = 0.0
        var validCount = 0
        for m in arMeasurements {
            let pixelDx = (m.pointB.x - m.pointA.x) * imgW
            let pixelDy = (m.pointB.y - m.pointA.y) * imgH
            let pixelDist = sqrt(pixelDx * pixelDx + pixelDy * pixelDy)
            guard pixelDist > 1.0 else { continue }
            totalScale += m.distanceMeters / pixelDist
            validCount += 1
        }
        guard validCount > 0 else { return nil }
        return totalScale / Double(validCount)
    }
    
    /// Planos verticales (paredes)
    var walls: [OffsitePlaneData] {
        planes.filter { $0.isVertical }
    }
    
    /// Planos horizontales (suelo/techo)
    var floors: [OffsitePlaneData] {
        planes.filter { $0.isHorizontal && $0.classification == .floor }
    }
    
    /// Total de planos detectados
    var totalPlanes: Int { planes.count }
    
    /// Total de paredes
    var totalWalls: Int { walls.count }
    
    init(capturedAt: Date = Date(), camera: OffsiteCameraData? = nil, planes: [OffsitePlaneData] = [], corners: [OffsiteCornerData] = [], wallDimensions: [OffsiteWallDimension] = [], measurements: [OffsiteMeasurement] = [], perspectiveFrames: [OffsiteFramePerspective] = [], frames: [OffsiteFrame] = [], textAnnotations: [OffsiteTextAnnotation] = [], lidarMetadata: OffsiteLiDARMetadata? = nil, imageScale: Double = 1.0) {
        self.capturedAt = capturedAt
        self.camera = camera
        self.planes = planes
        self.corners = corners
        self.wallDimensions = wallDimensions
        self.measurements = measurements
        self.perspectiveFrames = perspectiveFrames
        self.frames = frames
        self.textAnnotations = textAnnotations
        self.lidarMetadata = lidarMetadata
        self.imageScale = imageScale
    }
}
