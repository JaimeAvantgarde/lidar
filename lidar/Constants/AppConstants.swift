//
//  AppConstants.swift
//  lidar
//
//  Constantes centralizadas de la aplicación. Elimina "magic numbers" y facilita el mantenimiento.
//

import Foundation
import CoreGraphics

enum AppConstants {

    // MARK: - UI Layout

    enum Layout {
        /// Zona superior de exclusión para toques AR (puntos)
        static let topBarExclusionZone: CGFloat = 120
        /// Zona inferior de exclusión para toques AR (puntos)
        static let bottomPanelExclusionZone: CGFloat = 400
        /// Altura fija del panel de contenido
        static let panelContentHeight: CGFloat = 320
        /// Radio de esquinas del panel principal
        static let panelCornerRadius: CGFloat = 28
        /// Padding horizontal del panel
        static let panelHorizontalPadding: CGFloat = 16
        /// Padding inferior del panel
        static let panelBottomPadding: CGFloat = 24
        /// Padding horizontal de la barra superior
        static let topBarHorizontalPadding: CGFloat = 20
        /// Padding superior de la barra superior
        static let topBarTopPadding: CGFloat = 12
        /// Padding inferior de la barra superior
        static let topBarBottomPadding: CGFloat = 8
        /// Radio de esquinas de glass pills
        static let glassPillCornerRadius: CGFloat = 20
        /// Padding inferior del hint cuando panel está colapsado
        static let collapsedHintBottomPadding: CGFloat = 100
        /// Padding inferior del hint cuando panel está expandido
        static let expandedHintBottomPadding: CGFloat = 380
    }

    // MARK: - AR Scene

    enum AR {
        /// Tamaño por defecto de un cuadro al colocarlo
        static let defaultFrameSize = CGSize(width: 0.5, height: 0.5)
        /// Radio de la esfera del punto de medición (marcador naranja)
        static let measurementPointRadius: CGFloat = 0.02
        /// Radio del cilindro de la línea de medición
        static let measurementLineRadius: CGFloat = 0.005
        /// Radio de las esferas en los extremos de la medición
        static let measurementEndpointRadius: CGFloat = 0.015
        /// Tamaño de fuente del texto 3D de medición
        static let measurementTextFontSize: CGFloat = 0.055
        /// Escala del nodo de texto 3D
        static let measurementTextScale: Float = 0.35
        /// Offset vertical del texto respecto a la línea
        static let measurementTextOffset: Float = 0.08
        /// Profundidad de extrusión del texto 3D
        static let measurementTextExtrusion: CGFloat = 0.006
        /// Segmentos radiales del cilindro de línea
        static let lineRadialSegments: Int = 8
        /// Distancia máxima para detectar esquinas entre planos
        static let cornerMaxDistance: Float = 0.8
        /// Dot product mínimo para considerar esquina (~90°)
        static let cornerMinDot: Float = -0.3
        /// Dot product máximo para considerar esquina (~90°)
        static let cornerMaxDot: Float = 0.3
        /// Longitud mínima de un vector normal para considerarlo válido
        static let minNormalLength: Float = 0.001
    }

    // MARK: - Capture (Offsite)

    enum Capture {
        /// Calidad JPEG para la imagen de captura
        static let jpegQuality: CGFloat = 0.9
        /// Tamaño del thumbnail generado
        static let thumbnailSize = CGSize(width: 200, height: 200)
        /// Calidad JPEG del thumbnail
        static let thumbnailQuality: CGFloat = 0.7
        /// Nombre del directorio de capturas offsite
        static let directoryName = "OffsiteCaptures"
        /// Formato de fecha para nombres de archivo
        static let dateFormat = "yyyyMMdd_HHmmss"
        /// Prefijo de los archivos de captura
        static let filePrefix = "capture_"
    }

    // MARK: - Measurement

    enum Measurement {
        /// Factor de conversión de metros a pies
        static let feetConversionFactor: Float = 3.28084
        /// Rango de zoom permitido en modo medición
        static let zoomRange: ClosedRange<Double> = 1.0...2.5
        /// Incremento del slider de zoom
        static let zoomStep: Double = 0.1
        /// Escala de zoom por defecto
        static let defaultZoomScale: Float = 1.0
    }

    // MARK: - Cuadros (Frames)

    enum Cuadros {
        /// Tamaño mínimo del slider
        static let minSize: CGFloat = 0.2
        /// Tamaño máximo del slider
        static let maxSize: CGFloat = 1.5
        /// Incremento del slider
        static let sizeStep: CGFloat = 0.05
        /// Tamaño por defecto
        static let defaultSize: CGFloat = 0.5
        /// Relación de aspecto alto/ancho
        static let aspectRatio: CGFloat = 0.8
        /// Tamaño de reemplazo rápido
        static let replaceSize = CGSize(width: 0.6, height: 0.48)
    }

    // MARK: - Offsite Editor

    enum OffsiteEditor {
        /// Tamaño normalizado por defecto de un cuadro offsite
        static let defaultFrameSize: Double = 0.15
        /// Metros por pixel estimado (sin referencia AR)
        static let estimatedMetersPerPixel: Double = 0.01
        /// Colores disponibles para cuadros offsite
        static let availableColors = ["#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6"]
        /// Tamaño del marcador de punto pendiente
        static let measurementPointSize: CGFloat = 20
        /// Tamaño del anillo exterior del marcador
        static let measurementPointOuterSize: CGFloat = 32
    }

    // MARK: - Animation

    enum Animation {
        /// Respuesta del spring principal
        static let springResponse: Double = 0.35
        /// Amortiguación del spring principal
        static let springDamping: Double = 0.8
        /// Duración de la animación de zoom
        static let zoomDuration: Double = 0.2
    }
}
