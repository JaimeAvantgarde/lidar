//
//  FlutterBridge.swift
//  lidar
//
//  Puente completo para conectar esta app nativa iOS (ARKit) con Flutter.
//  Flutter podrá invocar métodos aquí vía Method Channel / Platform Channel.
//  Soporta: mediciones, planos, esquinas, cuadros, capturas offsite, y escena completa.
//

import Foundation

/// Protocolo del puente: define la API que Flutter podrá llamar cuando se integre.
enum FlutterBridge {
    
    // MARK: - Actions (Flutter → Native)
    
    /// Acciones que Flutter puede enviar a AR
    enum Action: String, CaseIterable {
        // Cuadros
        case placeFrame = "place_frame"
        case moveFrame = "move_frame"
        case resizeFrame = "resize_frame"
        case deleteFrame = "delete_frame"
        case replaceFrame = "replace_frame"
        case setFrameImage = "set_frame_image"
        
        // Mediciones
        case startMeasurement = "start_measurement"
        case cancelMeasurement = "cancel_measurement"
        case deleteMeasurement = "delete_measurement"
        case deleteAllMeasurements = "delete_all_measurements"
        case setMeasurementUnit = "set_measurement_unit"
        
        // Planos
        case getPlaneDimensions = "get_plane_dimensions"
        case getAllPlanes = "get_all_planes"
        case selectPlane = "select_plane"
        case getDetectedCorners = "get_detected_corners"
        
        // Visualización
        case togglePlaneOverlays = "toggle_plane_overlays"
        case toggleCornerMarkers = "toggle_corner_markers"
        case toggleSnapToEdges = "toggle_snap_to_edges"
        case toggleFramePerspective = "toggle_frame_perspective"
        
        // Captura offsite
        case captureForOffsite = "capture_for_offsite"
        case loadOffsiteCaptures = "load_offsite_captures"
        case deleteOffsiteCapture = "delete_offsite_capture"
        case getOffsiteCaptureData = "get_offsite_capture_data"
        
        // Escena
        case getSceneSnapshot = "get_scene_snapshot"
        case saveScene = "save_scene"
        case loadScene = "load_scene"
        case resetSession = "reset_session"
        
        // Offsite editing
        case addOffsiteMeasurement = "add_offsite_measurement"
        case addOffsiteFrame = "add_offsite_frame"
        case addOffsiteTextAnnotation = "add_offsite_text_annotation"
        case deleteOffsiteElement = "delete_offsite_element"
        case saveOffsiteChanges = "save_offsite_changes"
    }
    
    // MARK: - Events (Native → Flutter)
    
    /// Eventos que la app nativa puede enviar a Flutter
    enum Event: String, CaseIterable {
        // Planos
        case planeDetected = "plane_detected"
        case planeUpdated = "plane_updated"
        case planeRemoved = "plane_removed"
        
        // Esquinas
        case cornerDetected = "corner_detected"
        case cornersUpdated = "corners_updated"
        
        // Cuadros
        case framePlaced = "frame_placed"
        case frameMoved = "frame_moved"
        case frameResized = "frame_resized"
        case frameDeleted = "frame_deleted"
        
        // Mediciones
        case measurementStarted = "measurement_started"
        case measurementPointAdded = "measurement_point_added"
        case measurementCompleted = "measurement_result"
        case measurementCancelled = "measurement_cancelled"
        
        // Snap
        case snapToEdge = "snap_to_edge"
        case snapToCorner = "snap_to_corner"
        
        // Captura
        case offsiteCaptured = "offsite_captured"
        case offsiteSaved = "offsite_saved"
        
        // Estado
        case sessionStarted = "session_started"
        case sessionPaused = "session_paused"
        case trackingChanged = "tracking_changed"
        case error = "error"
    }
    
    // MARK: - Data Types for Flutter
    
    /// Estructura de datos de un plano para Flutter (JSON-serializable)
    struct PlaneData: Codable {
        let id: String
        let alignment: String  // "vertical" or "horizontal"
        let classification: String
        let widthMeters: Double
        let heightMeters: Double
        let centerX: Double
        let centerY: Double
        let centerZ: Double
        let normalX: Double
        let normalY: Double
        let normalZ: Double
    }
    
    /// Estructura de datos de una esquina para Flutter
    struct CornerData: Codable {
        let positionX: Double
        let positionY: Double
        let positionZ: Double
        let angleDegrees: Double
        let planeIdA: String
        let planeIdB: String
    }
    
    /// Estructura de datos de una medición para Flutter
    struct MeasurementData: Codable {
        let id: String
        let distanceMeters: Double
        let pointAX: Double
        let pointAY: Double
        let pointAZ: Double
        let pointBX: Double
        let pointBY: Double
        let pointBZ: Double
    }
    
    /// Estructura de datos de un cuadro para Flutter
    struct FrameData: Codable {
        let id: String
        let positionX: Double
        let positionY: Double
        let positionZ: Double
        let widthMeters: Double
        let heightMeters: Double
        let isCornerFrame: Bool
        let planeId: String?
        let hasImage: Bool
    }
    
    /// Estructura de la escena completa para Flutter
    struct SceneData: Codable {
        let planes: [PlaneData]
        let corners: [CornerData]
        let measurements: [MeasurementData]
        let frames: [FrameData]
        let isLiDARAvailable: Bool
        let totalPlanes: Int
        let totalWalls: Int
        let totalCorners: Int
    }
    
    // MARK: - Connection
    
    /// Singleton del bridge (se conectará al Method Channel de Flutter)
    static var isFlutterConnected: Bool = false
    
    /// Handler para enviar datos a Flutter
    private static var flutterHandler: ((String, [String: Any]?) -> Void)?
    
    /// Handler para recibir acciones de Flutter
    private static var actionHandler: ((Action, [String: Any]?) -> [String: Any]?)?
    
    /// Cuando Flutter esté conectado, llamar a este método con los handlers
    static func connect(
        sendHandler: ((String, [String: Any]?) -> Void)?,
        receiveHandler: ((Action, [String: Any]?) -> [String: Any]?)? = nil
    ) {
        flutterHandler = sendHandler
        actionHandler = receiveHandler
        isFlutterConnected = sendHandler != nil
    }
    
    /// Desconectar Flutter
    static func disconnect() {
        flutterHandler = nil
        actionHandler = nil
        isFlutterConnected = false
    }
    
    /// Enviar evento a Flutter (cuando esté conectado)
    static func sendToFlutter(event: Event, data: [String: Any]? = nil) {
        guard isFlutterConnected else { return }
        flutterHandler?(event.rawValue, data)
    }
    
    /// Recibir acción de Flutter y devolver resultado
    static func handleAction(_ action: Action, params: [String: Any]? = nil) -> [String: Any]? {
        return actionHandler?(action, params)
    }
    
    // MARK: - Convenience methods for common events
    
    /// Notifica a Flutter que se detectó un nuevo plano
    static func notifyPlaneDetected(planeData: PlaneData) {
        guard let jsonData = try? JSONEncoder().encode(planeData),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return }
        sendToFlutter(event: .planeDetected, data: dict)
    }
    
    /// Notifica a Flutter que se completó una medición
    static func notifyMeasurementCompleted(measurement: MeasurementData) {
        guard let jsonData = try? JSONEncoder().encode(measurement),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return }
        sendToFlutter(event: .measurementCompleted, data: dict)
    }
    
    /// Notifica a Flutter que se detectaron esquinas
    static func notifyCornersUpdated(corners: [CornerData]) {
        guard let jsonData = try? JSONEncoder().encode(["corners": corners]),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return }
        sendToFlutter(event: .cornersUpdated, data: dict)
    }
    
    /// Envía la escena completa a Flutter
    static func sendSceneData(_ sceneData: SceneData) {
        guard let jsonData = try? JSONEncoder().encode(sceneData),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return }
        sendToFlutter(event: .sessionStarted, data: dict)
    }
    
    /// Notifica a Flutter que se capturó para offsite
    static func notifyOffsiteCaptured(imageURL: String, jsonURL: String, planeCount: Int, cornerCount: Int, measurementCount: Int) {
        sendToFlutter(event: .offsiteCaptured, data: [
            "imageURL": imageURL,
            "jsonURL": jsonURL,
            "planeCount": planeCount,
            "cornerCount": cornerCount,
            "measurementCount": measurementCount
        ])
    }
}
