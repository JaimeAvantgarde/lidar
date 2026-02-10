//
//  FlutterBridge.swift
//  lidar
//
//  Puente para conectar esta app nativa iOS (ARKit) con Flutter más adelante.
//  Flutter podrá invocar métodos aquí vía Method Channel / Platform Channel.
//

import Foundation

/// Protocolo del puente: define la API que Flutter podrá llamar cuando se integre.
enum FlutterBridge {
    
    /// Acciones que Flutter puede enviar a AR
    enum Action: String {
        case placeFrame = "place_frame"
        case moveFrame = "move_frame"
        case resizeFrame = "resize_frame"
        case deleteFrame = "delete_frame"
        case replaceFrame = "replace_frame"
        case startMeasurement = "start_measurement"
        case getPlaneDimensions = "get_plane_dimensions"
        case saveScene = "save_scene"
        case loadScene = "load_scene"
    }
    
    /// Eventos que la app nativa puede enviar a Flutter
    enum Event: String {
        case planeDetected = "plane_detected"
        case framePlaced = "frame_placed"
        case measurementResult = "measurement_result"
        case error = "error"
    }
    
    /// Singleton del bridge (se conectará al Method Channel de Flutter)
    static var isFlutterConnected: Bool = false
    
    /// Cuando Flutter esté conectado, llamar a este método con el handler del channel
    static func connect(handler: ((String, [String: Any]?) -> Void)?) {
        // TODO: asignar handler cuando Flutter registre el Method Channel
        isFlutterConnected = handler != nil
    }
    
    /// Enviar evento a Flutter (cuando esté conectado)
    static func sendToFlutter(event: Event, data: [String: Any]? = nil) {
        guard isFlutterConnected else { return }
        // TODO: invocar MethodChannel.invokeMethod desde el lado Flutter
        // Aquí se podría usar NotificationCenter o un callback registrado
    }
}
