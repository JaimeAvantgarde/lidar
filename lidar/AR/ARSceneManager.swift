//
//  ARSceneManager.swift
//  lidar
//
//  Gestiona la sesión ARKit: detección de planos (paredes), LiDAR si está disponible,
//  y colocación/movimiento/redimensionado/eliminación de cuadros (objetos).
//

import ARKit
import SceneKit
import Observation
import os.log

// Models (MeasurementUnit, ARMeasurement, PlaneDimensions) → Models/MeasurementModels.swift
// PlacedFrame → Models/PlacedFrame.swift

@MainActor
@Observable
final class ARSceneManager: NSObject {
    
    var detectedPlanes: [ARPlaneAnchor] = []
    var placedFrames: [PlacedFrame] = []
    var selectedFrameId: UUID?
    var lastPlaneDimensions: PlaneDimensions?
    var errorMessage: String?
    var isLiDARAvailable: Bool = false
    /// Si no es nil, el próximo tap en un plano moverá este cuadro a esa posición.
    var moveModeForFrameId: UUID?
    /// Imagen seleccionada de la galería para los nuevos cuadros (y para sustituir en uno existente).
    var selectedFrameImage: UIImage?
    /// Si true, el próximo tap en una pared coloca un vinilo que cubre toda la superficie detectada.
    var isVinylMode: Bool = false
    /// Contador para sincronizar el slider UI cuando se redimensiona/rota por gesto.
    var frameGestureUpdateCounter: Int = 0

    // MARK: - Medidas
    /// Si true, los toques en AR registran puntos para medir distancia (no colocan cuadros).
    var isMeasurementMode: Bool = false
    /// Primer punto de la medición en curso (nil = esperando primer toque).
    var measurementFirstPoint: SIMD3<Float>?
    /// Marcador visible en la escena para el primer punto (para que se vea dónde se tomará el punto).
    var measurementFirstPointMarker: SCNNode?
    /// Lista de todas las mediciones.
    var measurements: [ARMeasurement] = []
    /// Nodos en la escena por id de medición (línea + etiqueta + esferas en extremos).
    var measurementDisplayNodes: [UUID: SCNNode] = [:]
    /// Unidad para mostrar medidas: metros o pies (americanos).
    var measurementUnit: MeasurementUnit = .meters
    /// Zoom al medir: escala de la vista (1.0 = normal, 2.0 = 2x zoom). Afecta solo en modo medición.
    var measurementZoomScale: Float = 1.0

    // MARK: - Preview de medición en tiempo real
    /// Nodo temporal que muestra línea + distancia mientras el usuario apunta (antes de confirmar punto 2).
    private var measurementPreviewNode: SCNNode?
    /// Timer para actualizar el preview de medición cada frame.
    private var measurementPreviewTimer: Timer?

    // MARK: - Planos, esquinas y snap
    /// Si true, se muestran overlays visuales sobre los planos detectados.
    var showPlaneOverlays: Bool = false
    /// Si true, se muestran marcadores en las esquinas detectadas.
    var showCornerMarkers: Bool = false
    /// Si true, se muestra el wireframe del mesh LiDAR reconstruido.
    var showMeshWireframe: Bool = false
    /// Si true, se muestra el mesh LiDAR con color por profundidad (azul→verde→rojo).
    var showDepthColorMesh: Bool = false
    /// Si true, se muestran los feature points de tracking ARKit.
    var showFeaturePoints: Bool = false
    /// Si true, los puntos de medición se ajustan a bordes/esquinas cercanos.
    var snapToEdgesEnabled: Bool = true
    /// Si true, los cuadros se colocan alineados al plano (sin billboard).
    var useFramePerspective: Bool = false
    /// Plano seleccionado manualmente por el usuario.
    var selectedPlaneAnchor: ARPlaneAnchor?
    /// Esquinas detectadas entre planos.
    var detectedCorners: [(position: SIMD3<Float>, planeA: ARPlaneAnchor, planeB: ARPlaneAnchor, angle: Float)] = []
    /// Último punto de snap detectado (nil si no hay snap activo).
    var lastSnapPoint: SIMD3<Float>?
    /// Nodos de overlay para cada plano (key = anchor identifier).
    private var planeOverlayNodes: [UUID: SCNNode] = [:]
    /// Nodos de marcadores de esquinas.
    private var cornerMarkerNodes: [SCNNode] = []
    /// Nodo de marcador de snap temporal.
    private var snapMarkerNode: SCNNode?
    /// Nodos del mesh LiDAR por anchor identifier.
    private var meshNodes: [UUID: SCNNode] = [:]
    /// Nodos del mesh coloreado por profundidad por anchor identifier.
    private var depthMeshNodes: [UUID: SCNNode] = [:]

    /// Estado actual del tracking de la cámara AR.
    var currentTrackingState: ARCamera.TrackingState = .notAvailable

    /// Calidad estimada de la captura actual.
    enum CaptureQuality {
        case poor, fair, good

        var color: String {
            switch self {
            case .poor: return "red"
            case .fair: return "yellow"
            case .good: return "green"
            }
        }
    }

    /// Nivel de calidad para captura basado en tracking, planos, mediciones y LiDAR.
    var captureQualityLevel: CaptureQuality {
        var score = 0

        // Tracking (0-2 pts)
        switch currentTrackingState {
        case .normal: score += 2
        case .limited: score += 1
        case .notAvailable: score += 0
        }

        // Planos detectados (0-2 pts)
        if detectedPlanes.count >= 3 { score += 2 }
        else if detectedPlanes.count >= 1 { score += 1 }

        // Mediciones (0-2 pts)
        if measurements.count >= 2 { score += 2 }
        else if measurements.count >= 1 { score += 1 }

        // LiDAR bonus (1 pt)
        if isLiDARAvailable { score += 1 }

        if score >= 5 { return .good }
        if score >= 3 { return .fair }
        return .poor
    }

    /// Alias: misma lista que detectedPlanes, para uso más explícito.
    var detectedPlaneAnchors: [ARPlaneAnchor] { detectedPlanes }

    /// Última medición (conveniencia para UI).
    var lastMeasurementResult: (distance: Float, pointA: SIMD3<Float>, pointB: SIMD3<Float>)? {
        guard let last = measurements.last else { return nil }
        return (last.distance, last.pointA, last.pointB)
    }

    private var sceneView: ARSCNView?
    private let configuration = ARWorldTrackingConfiguration()
    private let storageService: StorageServiceProtocol
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lidar", category: "ARScene")

    init(storageService: StorageServiceProtocol = StorageService.shared) {
        self.storageService = storageService
        super.init()
        checkLiDARSupport()
    }
    
    func setSceneView(_ view: ARSCNView) {
        sceneView = view
        view.delegate = self
        view.session.delegate = self
    }
    
    private func checkLiDARSupport() {
        isLiDARAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
    
    /// Iniciar sesión AR: planos horizontales y verticales, mesh LiDAR con clasificación, scene depth suavizado.
    func startSession() {
        guard let sceneView = sceneView else { return }
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        if isLiDARAvailable {
            // Mesh con clasificación semántica (pared, suelo, techo, puerta, ventana)
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                configuration.sceneReconstruction = .meshWithClassification
            } else {
                configuration.sceneReconstruction = .mesh
            }
            // Smoothed depth para mejor calidad (temporal smoothing reduce ruido)
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                configuration.frameSemantics.insert(.smoothedSceneDepth)
            } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
        }
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        errorMessage = nil
    }
    
    func pauseSession() {
        stopMeasurementPreviewUpdates()
        sceneView?.session.pause()
    }
    
    // MARK: - Cuadros (objetos)
    
    /// Colocar un cuadro (foto de galería) en el punto 3D con la perspectiva del plano.
    /// Si hay esquina de dos paredes, se adapta en L.
    func placeFrame(at position: SIMD3<Float>, on planeAnchor: ARPlaneAnchor?, size: CGSize = CGSize(width: 0.5, height: 0.5)) {
        let image = selectedFrameImage
        if let anchor = planeAnchor, let otherAnchor = findCornerPlane(near: position, from: anchor) {
            let (cornerNode, _) = createCornerFrameNode(size: size, image: image, planeA: anchor, planeB: otherAnchor)
            cornerNode.simdPosition = position
            let placed = PlacedFrame(node: cornerNode, planeAnchor: anchor, size: size, image: image, isCornerFrame: true)
            sceneView?.scene.rootNode.addChildNode(cornerNode)
            placedFrames.append(placed)
            selectedFrameId = placed.id
        } else {
            let frameNode = createFrameNode(size: size, image: image, alignToSurface: planeAnchor != nil)
            frameNode.simdPosition = position
            if let anchor = planeAnchor {
                // Siempre alinear a la superficie — quitar billboard
                frameNode.constraints = nil
                frameNode.simdOrientation = orientationForPlane(anchor: anchor)
                
                // Offset ligeramente fuera del plano para evitar z-fighting
                let normal = planeNormal(anchor)
                frameNode.simdPosition = position + normal * 0.005
            }
            let placed = PlacedFrame(node: frameNode, planeAnchor: planeAnchor, size: size, image: image, isCornerFrame: false)
            sceneView?.scene.rootNode.addChildNode(frameNode)
            placedFrames.append(placed)
            selectedFrameId = placed.id
            selectedPlaneAnchor = planeAnchor
        }
    }
    
    /// Coloca un vinilo (imagen) que cubre toda la superficie de la pared detectada.
    func placeVinyl(on planeAnchor: ARPlaneAnchor) {
        guard planeAnchor.alignment == .vertical else { return }
        let image = selectedFrameImage

        // Usar las dimensiones completas del plano detectado
        let size = CGSize(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))

        // Centro del plano en coordenadas mundo
        let t = planeAnchor.transform
        let center = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

        let frameNode = createFrameNode(size: size, image: image, alignToSurface: true)
        frameNode.constraints = nil
        frameNode.simdOrientation = orientationForPlane(anchor: planeAnchor)

        // Offset ligeramente fuera de la pared para evitar z-fighting
        let normal = planeNormal(planeAnchor)
        frameNode.simdPosition = center + normal * 0.005

        let placed = PlacedFrame(node: frameNode, planeAnchor: planeAnchor, size: size, image: image, isCornerFrame: false)
        sceneView?.scene.rootNode.addChildNode(frameNode)
        placedFrames.append(placed)
        selectedFrameId = placed.id
        selectedPlaneAnchor = planeAnchor

        isVinylMode = false
    }

    /// Mover un cuadro a una nueva posición (y opcionalmente reorientar al plano; esquina solo mueve posición).
    func moveFrame(id: UUID, to position: SIMD3<Float>, planeAnchor: ARPlaneAnchor? = nil) {
        guard let index = placedFrames.firstIndex(where: { $0.id == id }) else { return }
        let placed = placedFrames[index]
        let node = placed.node
        node.simdPosition = position
        if !placed.isCornerFrame, let anchor = planeAnchor {
            // Quitar billboard y alinear a la superficie real
            node.constraints = nil
            node.simdOrientation = orientationForPlane(anchor: anchor)
            // Offset fuera del plano
            let normal = planeNormal(anchor)
            node.simdPosition = position + normal * 0.005
        }
        placedFrames[index].planeAnchor = planeAnchor
        moveModeForFrameId = nil
    }
    
    /// Redimensionar un cuadro
    func resizeFrame(id: UUID, newSize: CGSize) {
        guard let index = placedFrames.firstIndex(where: { $0.id == id }) else { return }
        let placed = placedFrames[index]
        placed.size = newSize
        updateFrameGeometry(node: placed.node, size: newSize)
        frameGestureUpdateCounter += 1
    }
    
    /// Rotar un cuadro alrededor de su eje normal.
    func rotateFrame(id: UUID, angle: Float) {
        guard let index = placedFrames.firstIndex(where: { $0.id == id }) else { return }
        let placed = placedFrames[index]
        guard !placed.isCornerFrame else { return }
        placed.rotationAngle = angle
        if let anchor = placed.planeAnchor {
            // Orientación base del plano + rotación del usuario alrededor de la normal
            let baseOrientation = orientationForPlane(anchor: anchor)
            let normal = planeNormal(anchor)
            let userRotation = simd_quatf(angle: angle, axis: normal)
            placed.node.simdOrientation = userRotation * baseOrientation
        } else {
            // Sin plano: quitar billboard y rotar alrededor de Z local
            placed.node.constraints = nil
            placed.node.eulerAngles.z = angle
        }
        frameGestureUpdateCounter += 1
    }

    /// Eliminar un cuadro
    func deleteFrame(id: UUID) {
        guard let index = placedFrames.firstIndex(where: { $0.id == id }) else { return }
        placedFrames[index].node.removeFromParentNode()
        placedFrames.remove(at: index)
        if selectedFrameId == id { selectedFrameId = nil }
    }
    
    /// Sustituir un cuadro por otro (misma posición y plano; conserva imagen o usa la seleccionada).
    func replaceFrame(id: UUID, withNewSize size: CGSize? = nil) {
        guard let index = placedFrames.firstIndex(where: { $0.id == id }) else { return }
        let old = placedFrames[index]
        let newSize = size ?? old.size
        let image = selectedFrameImage ?? old.image
        let newNode: SCNNode
        let stillCorner: Bool
        if old.isCornerFrame, let anchorA = old.planeAnchor, let anchorB = findCornerPlane(near: old.node.simdPosition, from: anchorA) {
            let (cornerNode, _) = createCornerFrameNode(size: newSize, image: image, planeA: anchorA, planeB: anchorB)
            cornerNode.simdPosition = old.node.simdPosition
            newNode = cornerNode
            stillCorner = true  // sigue siendo esquina
        } else {
            let hasPlane = old.planeAnchor != nil
            newNode = createFrameNode(size: newSize, image: image, alignToSurface: hasPlane)
            newNode.simdPosition = old.node.simdPosition
            newNode.simdOrientation = old.node.simdOrientation
            if hasPlane { newNode.constraints = nil }
            stillCorner = false
        }
        old.node.removeFromParentNode()
        sceneView?.scene.rootNode.addChildNode(newNode)
        placedFrames[index] = PlacedFrame(id: old.id, node: newNode, planeAnchor: old.planeAnchor, size: newSize, image: image, isCornerFrame: stillCorner)
    }

    /// Cambiar la imagen de un cuadro ya colocado.
    func setFrameImage(id: UUID, image: UIImage?) {
        guard let index = placedFrames.firstIndex(where: { $0.id == id }) else { return }
        let placed = placedFrames[index]
        placed.image = image
        applyImage(to: placed.node, image: image, size: placed.size, isCorner: placed.isCornerFrame)
    }
    
    /// Obtener dimensiones del último plano seleccionado/detectado (alto x ancho)
    func getCurrentPlaneDimensions() -> PlaneDimensions? {
        return lastPlaneDimensions
    }

    /// Devuelve el id del cuadro que contiene este nodo (o nil si no es un cuadro nuestro).
    func frameId(containing node: SCNNode) -> UUID? {
        for frame in placedFrames {
            if frame.node === node { return frame.id }
            if frame.node.childNodes.contains(where: { $0 === node }) { return frame.id }
        }
        return nil
    }

    // MARK: - Medidas precisas

    /// Activa el modo medición: los dos próximos toques en AR darán la distancia.
    func startMeasurement() {
        isMeasurementMode = true
        measurementFirstPoint = nil
        removeFirstPointMarker()
        removeMeasurementPreview()
    }

    /// Desactiva el modo medición.
    func cancelMeasurement() {
        isMeasurementMode = false
        measurementFirstPoint = nil
        removeFirstPointMarker()
        removeMeasurementPreview()
        stopMeasurementPreviewUpdates()
    }

    /// Registra un punto en la escena AR. Aplica snap a bordes/esquinas si está habilitado.
    /// Si es el primero, lo guarda y muestra marcador; si es el segundo, crea la medición.
    func addMeasurementPoint(_ position: SIMD3<Float>) {
        guard isMeasurementMode else { return }
        let snappedPosition = snapToEdgesEnabled ? snapToNearestEdgeOrCorner(position) : position
        
        if let first = measurementFirstPoint {
            // Segundo punto: crear medición definitiva
            stopMeasurementPreviewUpdates()
            removeMeasurementPreview()
            removeFirstPointMarker()
            removeSnapMarker()
            let distance = simd_distance(first, snappedPosition)
            let measurement = ARMeasurement(pointA: first, pointB: snappedPosition, distance: distance)
            measurements.append(measurement)
            addMeasurementDisplay(measurement: measurement)
            measurementFirstPoint = nil
        } else {
            measurementFirstPoint = snappedPosition
            showFirstPointMarker(at: snappedPosition)
            // Iniciar preview en tiempo real de la línea de medición
            startMeasurementPreviewUpdates()
        }
    }
    
    /// Intenta hacer snap del punto a la esquina o borde de plano más cercano.
    private func snapToNearestEdgeOrCorner(_ position: SIMD3<Float>) -> SIMD3<Float> {
        // 1. Primero intentar snap a esquina detectada
        let snapCornerDist = AppConstants.AR.snapToCornerDistance
        var bestCorner: SIMD3<Float>?
        var bestCornerDist: Float = snapCornerDist
        
        for corner in detectedCorners {
            let d = simd_distance(position, corner.position)
            if d < bestCornerDist {
                bestCornerDist = d
                bestCorner = corner.position
            }
        }
        
        if let corner = bestCorner {
            showSnapMarker(at: corner, isCorner: true)
            return corner
        }
        
        // 2. Intentar snap a borde de plano
        let snapEdgeDist = AppConstants.AR.snapToEdgeDistance
        var bestEdgePoint: SIMD3<Float>?
        var bestEdgeDist: Float = snapEdgeDist
        
        for plane in detectedPlanes where plane.alignment == .vertical {
            let edgePoints = getPlaneEdgePoints(plane)
            for edgePoint in edgePoints {
                let d = simd_distance(position, edgePoint)
                if d < bestEdgeDist {
                    bestEdgeDist = d
                    bestEdgePoint = edgePoint
                }
            }
            // Also snap to nearest point on plane edge lines
            if let nearest = nearestPointOnPlaneEdges(position, plane: plane), simd_distance(position, nearest) < snapEdgeDist {
                let d = simd_distance(position, nearest)
                if d < bestEdgeDist {
                    bestEdgeDist = d
                    bestEdgePoint = nearest
                }
            }
        }
        
        if let edgePoint = bestEdgePoint {
            showSnapMarker(at: edgePoint, isCorner: false)
            return edgePoint
        }
        
        removeSnapMarker()
        return position
    }
    
    /// Obtiene los 4 puntos de las esquinas de un plano.
    private func getPlaneEdgePoints(_ anchor: ARPlaneAnchor) -> [SIMD3<Float>] {
        let t = anchor.transform
        let center = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let halfW = anchor.extent.x / 2
        let halfH = anchor.extent.z / 2
        
        let right = simd_normalize(SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z))
        let forward = simd_normalize(SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z))
        
        return [
            center + right * halfW + forward * halfH,
            center + right * halfW - forward * halfH,
            center - right * halfW + forward * halfH,
            center - right * halfW - forward * halfH
        ]
    }
    
    /// Punto más cercano en los bordes del plano.
    private func nearestPointOnPlaneEdges(_ point: SIMD3<Float>, plane: ARPlaneAnchor) -> SIMD3<Float>? {
        let edges = getPlaneEdgePoints(plane)
        guard edges.count == 4 else { return nil }
        
        let segments = [
            (edges[0], edges[1]), (edges[1], edges[3]),
            (edges[3], edges[2]), (edges[2], edges[0])
        ]
        
        var best: SIMD3<Float>?
        var bestDist: Float = .infinity
        
        for (a, b) in segments {
            let ab = b - a
            let ap = point - a
            let t = max(0, min(1, simd_dot(ap, ab) / simd_dot(ab, ab)))
            let projected = a + t * ab
            let d = simd_distance(point, projected)
            if d < bestDist {
                bestDist = d
                best = projected
            }
        }
        return best
    }
    
    /// Muestra marcador de snap (diamante para esquina, cuadrado para borde).
    private func showSnapMarker(at position: SIMD3<Float>, isCorner: Bool) {
        removeSnapMarker()
        guard let sceneView = sceneView else { return }
        
        let geo: SCNGeometry
        if isCorner {
            geo = SCNSphere(radius: AppConstants.AR.cornerMarkerRadius)
            geo.firstMaterial?.diffuse.contents = UIColor.systemYellow
            geo.firstMaterial?.emission.contents = UIColor.yellow.withAlphaComponent(0.5)
        } else {
            geo = SCNBox(width: 0.02, height: 0.02, length: 0.02, chamferRadius: 0.005)
            geo.firstMaterial?.diffuse.contents = UIColor.systemCyan
            geo.firstMaterial?.emission.contents = UIColor.cyan.withAlphaComponent(0.5)
        }
        
        let node = SCNNode(geometry: geo)
        node.simdPosition = position
        node.name = "snap_marker"
        sceneView.scene.rootNode.addChildNode(node)
        snapMarkerNode = node
        lastSnapPoint = position
    }
    
    private func removeSnapMarker() {
        snapMarkerNode?.removeFromParentNode()
        snapMarkerNode = nil
        lastSnapPoint = nil
    }

    /// Marcador visible para el primer punto (esfera pequeña).
    private func showFirstPointMarker(at position: SIMD3<Float>) {
        removeFirstPointMarker()
        guard let sceneView = sceneView else { return }
        let sphere = SCNSphere(radius: AppConstants.AR.measurementPointRadius)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemOrange
        sphere.firstMaterial?.emission.contents = UIColor.orange.withAlphaComponent(0.3)
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(position.x, position.y, position.z)
        node.name = "measurement_point_marker"
        sceneView.scene.rootNode.addChildNode(node)
        measurementFirstPointMarker = node
    }

    private func removeFirstPointMarker() {
        measurementFirstPointMarker?.removeFromParentNode()
        measurementFirstPointMarker = nil
    }

    // MARK: - Preview de medición en tiempo real
    
    /// Inicia el timer que actualiza la línea de preview cada ~30fps mientras el usuario apunta.
    private func startMeasurementPreviewUpdates() {
        stopMeasurementPreviewUpdates()
        measurementPreviewTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMeasurementPreview()
            }
        }
    }
    
    /// Para el timer de preview.
    private func stopMeasurementPreviewUpdates() {
        measurementPreviewTimer?.invalidate()
        measurementPreviewTimer = nil
    }
    
    /// Actualiza la línea temporal que va desde el primer punto hasta donde apunta la cámara.
    private func updateMeasurementPreview() {
        guard isMeasurementMode,
              let firstPoint = measurementFirstPoint,
              let sceneView = sceneView,
              let frame = sceneView.session.currentFrame else {
            removeMeasurementPreview()
            return
        }
        
        // Raycast desde el centro de la pantalla
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        var currentTarget: SIMD3<Float>?
        
        if let query = sceneView.raycastQuery(from: center, allowing: .existingPlaneGeometry, alignment: .any),
           let result = sceneView.session.raycast(query).first {
            currentTarget = result.worldTransform.position
        } else if let query = sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any),
                  let result = sceneView.session.raycast(query).first {
            currentTarget = result.worldTransform.position
        }
        
        guard let target = currentTarget else {
            removeMeasurementPreview()
            return
        }
        
        let snappedTarget = snapToEdgesEnabled ? snapToNearestEdgeOrCorner(target) : target
        let distance = simd_distance(firstPoint, snappedTarget)
        
        // Eliminar preview anterior
        removeMeasurementPreview()
        
        // Crear nodo con línea punteada + etiqueta de distancia
        let parent = SCNNode()
        parent.name = "measurement_preview"
        
        let mid = (firstPoint + snappedTarget) * 0.5
        parent.position = SCNVector3(mid.x, mid.y, mid.z)
        
        // Línea (cilindro delgado, semitransparente)
        let dir = simd_normalize(snappedTarget - firstPoint)
        let worldUp = SIMD3<Float>(0, 1, 0)
        var axis = simd_cross(worldUp, dir)
        if simd_length(axis) < AppConstants.AR.minNormalLength { axis = SIMD3<Float>(1, 0, 0) }
        axis = simd_normalize(axis)
        let angle = acos(max(-1, min(1, simd_dot(worldUp, dir))))
        
        let cylinder = SCNCylinder(radius: 0.003, height: CGFloat(distance))
        cylinder.radialSegmentCount = 6
        cylinder.firstMaterial?.diffuse.contents = UIColor.systemOrange.withAlphaComponent(0.6)
        cylinder.firstMaterial?.emission.contents = UIColor.orange.withAlphaComponent(0.15)
        let lineNode = SCNNode(geometry: cylinder)
        lineNode.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
        parent.addChildNode(lineNode)
        
        // Etiqueta de distancia
        let labelString = measurementUnit.format(distanceMeters: distance)
        let text = SCNText(string: labelString, extrusionDepth: 0.004)
        text.font = .systemFont(ofSize: 0.05, weight: .bold)
        text.firstMaterial?.diffuse.contents = UIColor.systemOrange
        text.firstMaterial?.emission.contents = UIColor.orange.withAlphaComponent(0.3)
        text.firstMaterial?.isDoubleSided = true
        let textNode = SCNNode(geometry: text)
        let s: Float = 0.3
        textNode.scale = SCNVector3(s, s, s)
        textNode.position = SCNVector3(0, 0.06, 0)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        textNode.constraints = [billboard]
        parent.addChildNode(textNode)
        
        // Esfera en el punto objetivo (visual feedback)
        let targetSphere = SCNSphere(radius: 0.012)
        targetSphere.firstMaterial?.diffuse.contents = UIColor.systemOrange.withAlphaComponent(0.5)
        targetSphere.firstMaterial?.emission.contents = UIColor.orange.withAlphaComponent(0.2)
        let targetNode = SCNNode(geometry: targetSphere)
        targetNode.position = SCNVector3(
            snappedTarget.x - mid.x,
            snappedTarget.y - mid.y,
            snappedTarget.z - mid.z
        )
        parent.addChildNode(targetNode)
        
        sceneView.scene.rootNode.addChildNode(parent)
        measurementPreviewNode = parent
    }
    
    /// Elimina el nodo de preview temporal.
    private func removeMeasurementPreview() {
        measurementPreviewNode?.removeFromParentNode()
        measurementPreviewNode = nil
    }

    /// Añade a la escena la línea, etiqueta y esferas. Usa simdWorldPosition para estabilidad.
    private func addMeasurementDisplay(measurement: ARMeasurement) {
        guard let sceneView = sceneView else { return }
        let pointA = measurement.pointA
        let pointB = measurement.pointB
        let distance = measurement.distance
        let parent = SCNNode()
        parent.name = "measurement_\(measurement.id.uuidString)"
        let mid = (pointA + pointB) * 0.5
        parent.simdWorldPosition = mid
        
        let length = distance
        let dir = simd_normalize(pointB - pointA)
        let worldUp = SIMD3<Float>(0, 1, 0)
        var axis = simd_cross(worldUp, dir)
        if simd_length(axis) < AppConstants.AR.minNormalLength { axis = SIMD3<Float>(1, 0, 0) }
        axis = simd_normalize(axis)
        let angle = acos(max(-1, min(1, simd_dot(worldUp, dir))))

        let cylinder = SCNCylinder(radius: AppConstants.AR.measurementLineRadius, height: CGFloat(length))
        cylinder.radialSegmentCount = AppConstants.AR.lineRadialSegments
        cylinder.firstMaterial?.diffuse.contents = UIColor.systemGreen
        cylinder.firstMaterial?.emission.contents = UIColor.green.withAlphaComponent(0.3)
        cylinder.firstMaterial?.lightingModel = .constant
        let lineNode = SCNNode(geometry: cylinder)
        lineNode.position = SCNVector3(0, 0, 0)
        lineNode.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
        parent.addChildNode(lineNode)

        // Etiqueta de distancia — SIEMPRE encima del punto medio (offset en Y global)
        let labelString = measurementUnit.format(distanceMeters: distance)
        let text = SCNText(string: labelString, extrusionDepth: AppConstants.AR.measurementTextExtrusion)
        text.font = .systemFont(ofSize: AppConstants.AR.measurementTextFontSize, weight: .bold)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.firstMaterial?.emission.contents = UIColor.white.withAlphaComponent(0.8)
        text.firstMaterial?.lightingModel = .constant
        text.firstMaterial?.isDoubleSided = true
        text.flatness = 0.1
        let textNode = SCNNode(geometry: text)
        let s = AppConstants.AR.measurementTextScale
        textNode.scale = SCNVector3(s, s, s)
        // Centrar texto horizontalmente
        let (textMin, textMax) = textNode.boundingBox
        let textWidth = (textMax.x - textMin.x) * s
        let textHeight = (textMax.y - textMin.y) * s
        // Offset SIEMPRE en Y positivo (arriba), fijo e independiente de la dirección de la línea
        let yOffset = AppConstants.AR.measurementTextOffset
        textNode.position = SCNVector3(-textWidth / 2, yOffset, 0)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.X, .Y]
        textNode.constraints = [billboard]
        parent.addChildNode(textNode)
        
        // Fondo semitransparente detrás del texto para legibilidad
        let bgWidth = CGFloat(textWidth + 0.02)
        let bgHeight = CGFloat(textHeight + 0.01)
        let bgPlane = SCNPlane(width: bgWidth, height: bgHeight)
        bgPlane.firstMaterial?.diffuse.contents = UIColor.black.withAlphaComponent(0.5)
        bgPlane.firstMaterial?.lightingModel = .constant
        bgPlane.firstMaterial?.isDoubleSided = true
        let bgNode = SCNNode(geometry: bgPlane)
        bgNode.position = SCNVector3(0, yOffset + Float(bgHeight) / 2, -0.001)
        bgNode.constraints = [billboard]
        parent.addChildNode(bgNode)

        // Esferas en extremos (con emisión para que se vean siempre)
        let sphereGeo = SCNSphere(radius: AppConstants.AR.measurementEndpointRadius)
        sphereGeo.firstMaterial?.diffuse.contents = UIColor.systemGreen
        sphereGeo.firstMaterial?.emission.contents = UIColor.green.withAlphaComponent(0.5)
        sphereGeo.firstMaterial?.lightingModel = .constant
        let sphereA = SCNNode(geometry: sphereGeo)
        sphereA.simdPosition = pointA - mid
        parent.addChildNode(sphereA)
        let sphereGeoB = SCNSphere(radius: AppConstants.AR.measurementEndpointRadius)
        sphereGeoB.firstMaterial?.diffuse.contents = UIColor.systemGreen
        sphereGeoB.firstMaterial?.emission.contents = UIColor.green.withAlphaComponent(0.5)
        sphereGeoB.firstMaterial?.lightingModel = .constant
        let sphereB = SCNNode(geometry: sphereGeoB)
        sphereB.simdPosition = pointB - mid
        parent.addChildNode(sphereB)

        // Renderizar mediciones encima de otros elementos para que no se oculten
        parent.renderingOrder = 10
        sceneView.scene.rootNode.addChildNode(parent)
        measurementDisplayNodes[measurement.id] = parent
    }

    /// Elimina una medición de la lista y de la escena.
    func deleteMeasurement(id: UUID) {
        measurementDisplayNodes[id]?.removeFromParentNode()
        measurementDisplayNodes.removeValue(forKey: id)
        measurements.removeAll { $0.id == id }
    }

    /// Elimina todas las mediciones.
    func deleteAllMeasurements() {
        for node in measurementDisplayNodes.values {
            node.removeFromParentNode()
        }
        measurementDisplayNodes.removeAll()
        measurements.removeAll()
    }

    /// Vuelve a dibujar todas las líneas de medición (p. ej. al cambiar de m a ft).
    func refreshMeasurementDisplays() {
        let list = measurements
        for m in list {
            measurementDisplayNodes[m.id]?.removeFromParentNode()
            measurementDisplayNodes.removeValue(forKey: m.id)
        }
        for m in list {
            addMeasurementDisplay(measurement: m)
        }
    }

    // MARK: - Detección de esquinas y visualización de planos
    
    /// Detecta todas las esquinas entre planos verticales y actualiza la lista.
    func detectAllCorners() {
        detectedCorners.removeAll()
        let verticalPlanes = detectedPlanes.filter { $0.alignment == .vertical }
        
        for i in 0..<verticalPlanes.count {
            for j in (i+1)..<verticalPlanes.count {
                let planeA = verticalPlanes[i]
                let planeB = verticalPlanes[j]
                
                if let corner = detectCorner(between: planeA, and: planeB) {
                    detectedCorners.append(corner)
                }
            }
        }
        
        if showCornerMarkers {
            updateCornerMarkerVisuals()
        }
    }
    
    /// Detecta si dos planos forman una esquina.
    private func detectCorner(between planeA: ARPlaneAnchor, and planeB: ARPlaneAnchor) -> (position: SIMD3<Float>, planeA: ARPlaneAnchor, planeB: ARPlaneAnchor, angle: Float)? {
        let n1 = planeNormal(planeA)
        let n2 = planeNormal(planeB)
        let dot = abs(simd_dot(n1, n2))
        
        // Check angle is within corner range (60°-120°)
        let angle = acos(min(1.0, max(-1.0, simd_dot(n1, n2)))) * 180 / .pi
        guard angle >= Float(AppConstants.AR.cornerMinAngle) && angle <= Float(AppConstants.AR.cornerMaxAngle) else { return nil }
        
        // Check distance between plane centers
        let centerA = SIMD3<Float>(planeA.transform.columns.3.x, planeA.transform.columns.3.y, planeA.transform.columns.3.z)
        let centerB = SIMD3<Float>(planeB.transform.columns.3.x, planeB.transform.columns.3.y, planeB.transform.columns.3.z)
        let dist = simd_distance(centerA, centerB)
        
        guard dist < AppConstants.AR.cornerDetectionMaxDistance else { return nil }
        
        // Find intersection line of the two planes and estimate corner position
        let edgesA = getPlaneEdgePoints(planeA)
        let edgesB = getPlaneEdgePoints(planeB)
        
        // Find closest pair of edge points between the two planes
        var bestDist: Float = .infinity
        var bestMidpoint = (centerA + centerB) * 0.5
        
        for ea in edgesA {
            for eb in edgesB {
                let d = simd_distance(ea, eb)
                if d < bestDist {
                    bestDist = d
                    bestMidpoint = (ea + eb) * 0.5
                }
            }
        }
        
        return (position: bestMidpoint, planeA: planeA, planeB: planeB, angle: angle)
    }
    
    /// Actualiza los marcadores visuales de esquinas en la escena.
    private func updateCornerMarkerVisuals() {
        // Remove existing
        for node in cornerMarkerNodes {
            node.removeFromParentNode()
        }
        cornerMarkerNodes.removeAll()
        
        guard let sceneView = sceneView, showCornerMarkers else { return }
        
        for corner in detectedCorners {
            let sphere = SCNSphere(radius: AppConstants.AR.cornerMarkerRadius)
            sphere.firstMaterial?.diffuse.contents = UIColor.systemYellow
            sphere.firstMaterial?.emission.contents = UIColor.yellow.withAlphaComponent(0.4)
            sphere.firstMaterial?.transparency = 0.8
            
            let node = SCNNode(geometry: sphere)
            node.simdPosition = corner.position
            node.name = "corner_marker"
            
            // Add angle text
            let angleText = SCNText(string: String(format: "%.0f°", corner.angle), extrusionDepth: 0.003)
            angleText.font = .systemFont(ofSize: 0.04, weight: .bold)
            angleText.firstMaterial?.diffuse.contents = UIColor.systemYellow
            angleText.firstMaterial?.isDoubleSided = true
            let textNode = SCNNode(geometry: angleText)
            let s: Float = 0.25
            textNode.scale = SCNVector3(s, s, s)
            textNode.position = SCNVector3(0, 0.05, 0)
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .Y
            textNode.constraints = [billboard]
            node.addChildNode(textNode)
            
            sceneView.scene.rootNode.addChildNode(node)
            cornerMarkerNodes.append(node)
        }
    }
    
    /// Actualiza los overlays visuales de planos detectados.
    func updatePlaneOverlays() {
        guard showPlaneOverlays, let sceneView = sceneView else {
            // Remove all if disabled
            for node in planeOverlayNodes.values { node.removeFromParentNode() }
            planeOverlayNodes.removeAll()
            return
        }
        
        // Track which planes still exist
        var existingIds = Set<UUID>()
        
        for plane in detectedPlanes {
            let planeId = UUID(uuidString: plane.identifier.uuidString) ?? UUID()
            existingIds.insert(planeId)
            
            if let existingNode = planeOverlayNodes[planeId] {
                // Update existing overlay
                updatePlaneOverlayNode(existingNode, for: plane)
            } else {
                // Create new overlay
                let node = createPlaneOverlayNode(for: plane)
                sceneView.scene.rootNode.addChildNode(node)
                planeOverlayNodes[planeId] = node
            }
        }
        
        // Remove overlays for planes that no longer exist
        let toRemove = planeOverlayNodes.keys.filter { !existingIds.contains($0) }
        for id in toRemove {
            planeOverlayNodes[id]?.removeFromParentNode()
            planeOverlayNodes.removeValue(forKey: id)
        }
    }
    
    private func createPlaneOverlayNode(for anchor: ARPlaneAnchor) -> SCNNode {
        let w = CGFloat(anchor.extent.x)
        let h = CGFloat(anchor.extent.z)
        let plane = SCNPlane(width: w, height: h)
        
        let color: UIColor = anchor.alignment == .vertical ? .systemBlue : .systemGreen
        plane.firstMaterial?.diffuse.contents = color.withAlphaComponent(CGFloat(AppConstants.AR.planeOverlayOpacity))
        plane.firstMaterial?.isDoubleSided = true
        plane.firstMaterial?.transparency = 1.0
        
        let node = SCNNode(geometry: plane)
        node.name = "plane_overlay"
        
        let t = anchor.transform
        node.simdTransform = t
        
        // For vertical planes, rotate to face outward
        if anchor.alignment == .vertical {
            node.eulerAngles.x = -.pi / 2
        }
        
        // Add dimension labels
        addDimensionLabels(to: node, width: Float(w), height: Float(h), isVertical: anchor.alignment == .vertical)
        
        return node
    }
    
    private func updatePlaneOverlayNode(_ node: SCNNode, for anchor: ARPlaneAnchor) {
        let w = CGFloat(anchor.extent.x)
        let h = CGFloat(anchor.extent.z)
        
        if let plane = node.geometry as? SCNPlane {
            plane.width = w
            plane.height = h
        }
        
        node.simdTransform = anchor.transform
        
        // Update dimension labels
        node.childNodes.filter { $0.name == "dim_label" }.forEach { $0.removeFromParentNode() }
        addDimensionLabels(to: node, width: Float(w), height: Float(h), isVertical: anchor.alignment == .vertical)
    }
    
    private func addDimensionLabels(to node: SCNNode, width: Float, height: Float, isVertical: Bool) {
        let label = String(format: "%.2f × %.2f m", width, height)
        let text = SCNText(string: label, extrusionDepth: 0.002)
        text.font = .systemFont(ofSize: 0.03, weight: .semibold)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.firstMaterial?.emission.contents = UIColor.white.withAlphaComponent(0.3)
        text.firstMaterial?.isDoubleSided = true
        
        let textNode = SCNNode(geometry: text)
        let s = AppConstants.AR.dimensionTextScale
        textNode.scale = SCNVector3(s, s, s)
        textNode.name = "dim_label"
        
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        textNode.constraints = [billboard]
        
        node.addChildNode(textNode)
    }
    
    /// Clasifica un plano ARKit.
    func classifyPlane(_ anchor: ARPlaneAnchor) -> PlaneClassification {
        if #available(iOS 13.0, *) {
            switch anchor.classification {
            case .wall: return .wall
            case .floor: return .floor
            case .ceiling: return .ceiling
            case .door: return .door
            case .window: return .window
            default: break
            }
        }
        // Fallback: clasificar por alineación
        return anchor.alignment == .vertical ? .wall : .floor
    }

    // MARK: - Resumen de habitación
    
    /// Calcula dimensiones estimadas de la habitación a partir de los planos detectados.
    func estimateRoomSummary() -> RoomSummary? {
        let walls = detectedPlanes.filter { $0.alignment == .vertical }
        let floors = detectedPlanes.filter { classifyPlane($0) == .floor }
        let ceilings = detectedPlanes.filter { classifyPlane($0) == .ceiling }
        
        guard !walls.isEmpty else { return nil }
        
        // Estimar ancho y largo del room:
        // Usar los dos planos verticales más grandes perpendiculares entre sí
        var maxWidth: Float = 0
        var maxLength: Float = 0
        
        for wall in walls {
            let w = wall.extent.x
            let h = wall.extent.z
            // El extent.x de un plano vertical es su ancho horizontal
            maxWidth = max(maxWidth, w)
            
            // Buscar un plano perpendicular para el largo
            let n1 = planeNormal(wall)
            for other in walls where other.identifier != wall.identifier {
                let n2 = planeNormal(other)
                let dot = abs(simd_dot(n1, n2))
                if dot < 0.3 { // Son ~perpendiculares
                    maxLength = max(maxLength, other.extent.x)
                }
            }
        }
        
        // Si no encontró largo diferente, usar el segundo ancho más grande
        if maxLength == 0 {
            let widths = walls.map { $0.extent.x }.sorted(by: >)
            if widths.count >= 2 {
                maxLength = widths[1]
            } else {
                maxLength = maxWidth
            }
        }
        
        // Altura: usar el plano vertical más alto, o la distancia suelo-techo
        var estimatedHeight: Float = walls.map { $0.extent.z }.max() ?? 2.5
        
        if let floor = floors.first, let ceiling = ceilings.first {
            let floorY = floor.transform.columns.3.y
            let ceilingY = ceiling.transform.columns.3.y
            estimatedHeight = abs(ceilingY - floorY)
        }
        
        // Asegurar que width >= length para consistencia
        let finalWidth = max(maxWidth, maxLength)
        let finalLength = min(maxWidth, maxLength)
        
        return RoomSummary(width: finalWidth, length: finalLength, height: estimatedHeight)
    }
    
    // MARK: - Exportar PDF
    
    /// Genera un informe PDF profesional con la captura actual de la escena.
    func generatePDFReport() -> URL? {
        // Capturar imagen de la escena
        var sceneImage: UIImage?
        if let sceneView = sceneView {
            UIGraphicsBeginImageContextWithOptions(sceneView.bounds.size, false, UIScreen.main.scale)
            sceneView.drawHierarchy(in: sceneView.bounds, afterScreenUpdates: true)
            sceneImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
        }
        
        // Preparar datos de mediciones
        let measurementData = measurements.enumerated().map { (index, m) in
            (index: index + 1, distance: m.distance, unit: measurementUnit)
        }
        
        // Preparar datos de planos
        let planeData = detectedPlanes.map { plane in
            let classification = classifyPlane(plane)
            return (classification: classification.displayName, width: plane.extent.x, height: plane.extent.z)
        }
        
        return PDFReportService.generateReport(
            sceneImage: sceneImage,
            measurements: measurementData,
            planes: planeData,
            corners: detectedCorners.count,
            frames: placedFrames.count,
            isLiDAR: isLiDARAvailable,
            roomSummary: estimateRoomSummary()
        )
    }

    // MARK: - Captura offsite

    enum CaptureError: Error, LocalizedError {
        case noSceneView
        case noFrame
        case invalidBounds
        case imageEncodingFailed
        case saveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .noSceneView: return "Vista AR no disponible"
            case .noFrame: return "No se pudo obtener el frame de la cámara"
            case .invalidBounds: return "Tamaño de vista inválido"
            case .imageEncodingFailed: return "No se pudo codificar la imagen"
            case .saveFailed(let error): return "Error al guardar: \(error.localizedDescription)"
            }
        }
    }

    /// Captura la vista AR actual con TODOS los datos 3D de la escena (async).
    /// Fase 1 (main thread): screenshot + proyecciones. Fase 2 (background): codificación + IO.
    /// - Returns: (URL de la imagen, URL del JSON) o lanza error si falla.
    func captureForOffsite() async throws -> (imageURL: URL, jsonURL: URL) {
        guard let sceneView = sceneView else { throw CaptureError.noSceneView }

        // === FASE 1: Main thread — captura cámara pura + proyecciones ===
        detectAllCorners()

        // Capturar imagen directamente del feed de cámara (sin overlays de SceneKit)
        guard let currentFrame = sceneView.session.currentFrame else {
            throw CaptureError.noFrame
        }
        let pixelBuffer = currentFrame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw CaptureError.imageEncodingFailed
        }
        let image = UIImage(cgImage: cgImage)

        // Dimensiones de la imagen capturada (ya en portrait tras .oriented(.right))
        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)
        guard imageW > 0, imageH > 0 else { throw CaptureError.invalidBounds }
        let camera = currentFrame.camera
        let imageSize = CGSize(width: imageW, height: imageH)

        // Pre-codificar imagen a JPEG Data (para no pasar UIImage a background)
        guard let captureImageData = image.jpegData(compressionQuality: AppConstants.Capture.jpegQuality) else {
            throw CaptureError.imageEncodingFailed
        }
        let thumbnailData = image.preparingThumbnail(of: AppConstants.Capture.thumbnailSize)?
            .jpegData(compressionQuality: AppConstants.Capture.thumbnailQuality)

        // Helper: proyectar punto 3D a coordenada normalizada clampeada [0,1]
        // Usa ARCamera.projectPoint para que las coordenadas coincidan con capturedImage
        func projectNormalized(_ point: SCNVector3) -> NormalizedPoint {
            let p = camera.projectPoint(
                simd_float3(point.x, point.y, point.z),
                orientation: .portrait,
                viewportSize: imageSize
            )
            return NormalizedPoint(
                x: min(max(Double(p.x) / Double(imageW), 0), 1),
                y: min(max(Double(p.y) / Double(imageH), 0), 1)
            )
        }

        // 1. Proyectar mediciones (descartar si ambos puntos fuera de pantalla)
        let offsiteMeasurements: [OffsiteMeasurement] = measurements.compactMap { m in
            let pointA = projectNormalized(SCNVector3(m.pointA.x, m.pointA.y, m.pointA.z))
            let pointB = projectNormalized(SCNVector3(m.pointB.x, m.pointB.y, m.pointB.z))
            // Descartar si ambos extremos están en el mismo borde (completamente fuera)
            let aOnEdge = pointA.x <= 0 || pointA.x >= 1 || pointA.y <= 0 || pointA.y >= 1
            let bOnEdge = pointB.x <= 0 || pointB.x >= 1 || pointB.y <= 0 || pointB.y >= 1
            if aOnEdge && bOnEdge { return nil }
            return OffsiteMeasurement(id: m.id, distanceMeters: Double(m.distance), pointA: pointA, pointB: pointB, isFromAR: true)
        }

        // 2. Cuadros AR solo como perspectiva — extraer JPEG Data en main thread
        let offsiteFrames: [OffsiteFrame] = []

        struct IntermediateFrame: Sendable {
            let id: UUID
            let planeId: String?
            let center2D: NormalizedPoint
            let corners2D: [[Double]]
            let widthMeters: Double
            let heightMeters: Double
            let imageJPEGData: Data?
        }

        let intermediateFrames: [IntermediateFrame] = placedFrames.compactMap { frame in
            let frameNode = frame.node
            let pos = frameNode.simdWorldPosition
            let halfW = Float(frame.size.width) / 2.0
            let halfH = Float(frame.size.height) / 2.0
            let right = frameNode.simdWorldRight
            let up = frameNode.simdWorldUp

            let rW = right * halfW
            let uH = up * halfH
            let corners3D: [SIMD3<Float>] = [pos - rW + uH, pos + rW + uH, pos + rW - uH, pos - rW - uH]

            let corners2D = corners3D.map { pt -> [Double] in
                let np = projectNormalized(SCNVector3(pt))
                return [np.x, np.y]
            }
            let center2D = projectNormalized(SCNVector3(pos))
            let imageData = frame.image?.jpegData(compressionQuality: 0.8)

            return IntermediateFrame(
                id: frame.id,
                planeId: frame.planeAnchor?.identifier.uuidString,
                center2D: center2D,
                corners2D: corners2D,
                widthMeters: Double(frame.size.width),
                heightMeters: Double(frame.size.height),
                imageJPEGData: imageData
            )
        }

        // 3. Planos con vértices proyectados
        let offsitePlanes: [OffsitePlaneData] = detectedPlanes.map { plane in
            let t = plane.transform
            let center = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            let normal = planeNormal(plane)
            let classification = classifyPlane(plane)
            let edges = getPlaneEdgePoints(plane)
            let projected = edges.map { pt -> [Double] in
                let np = projectNormalized(SCNVector3(pt))
                return [np.x, np.y]
            }
            return OffsitePlaneData(
                id: plane.identifier.uuidString,
                alignment: plane.alignment == .vertical ? "vertical" : "horizontal",
                classification: classification,
                transform: flattenTransform(t),
                extentX: Double(plane.extent.x),
                extentZ: Double(plane.extent.z),
                center3D: [center.x, center.y, center.z],
                normal: [normal.x, normal.y, normal.z],
                projectedVertices: projected,
                widthMeters: Double(plane.extent.x),
                heightMeters: Double(plane.extent.z)
            )
        }

        // 4. Esquinas
        let offsiteCorners: [OffsiteCornerData] = detectedCorners.map { corner in
            let pos2D = projectNormalized(SCNVector3(corner.position))
            return OffsiteCornerData(
                position3D: corner.position,
                position2D: pos2D,
                angleDegrees: Double(corner.angle),
                planeIdA: corner.planeA.identifier.uuidString,
                planeIdB: corner.planeB.identifier.uuidString
            )
        }

        // 5. Dimensiones de paredes
        let wallDims: [OffsiteWallDimension] = detectedPlanes.filter { $0.alignment == .vertical }.map { plane in
            let edges = getPlaneEdgePoints(plane)
            let verts = edges.map { pt -> [Double] in
                let np = projectNormalized(SCNVector3(pt))
                return [np.x, np.y]
            }
            return OffsiteWallDimension(
                planeId: plane.identifier.uuidString,
                widthMeters: Double(plane.extent.x),
                heightMeters: Double(plane.extent.z),
                vertices2D: verts
            )
        }

        // 6. Datos de cámara (usar resolución real del capturedImage)
        let cameraData = OffsiteCameraData(
            intrinsics: camera.intrinsics,
            transform: camera.transform,
            imageWidth: Int(imageW),
            imageHeight: Int(imageH)
        )

        // 7. Depth map (CVPixelBuffer Float32 → Data)
        var depthMapData: Data?
        var depthMapWidth: Int = 0
        var depthMapHeight: Int = 0
        if let sceneDepth = currentFrame.smoothedSceneDepth ?? currentFrame.sceneDepth {
            let depthBuffer = sceneDepth.depthMap
            CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }
            depthMapWidth = CVPixelBufferGetWidth(depthBuffer)
            depthMapHeight = CVPixelBufferGetHeight(depthBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
            if let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) {
                var data = Data(capacity: depthMapWidth * depthMapHeight * MemoryLayout<Float>.size)
                for row in 0..<depthMapHeight {
                    let rowPtr = baseAddress.advanced(by: row * bytesPerRow)
                    data.append(UnsafeBufferPointer(start: rowPtr.assumingMemoryBound(to: Float.self), count: depthMapWidth))
                }
                depthMapData = data
            }
        }

        // 8. Metadata del LiDAR
        let planeDims = detectedPlanes.map { plane in
            PlaneDimension(width: Double(plane.extent.x), height: Double(plane.extent.z))
        }
        let lidarMetadata = OffsiteLiDARMetadata(
            isLiDARAvailable: isLiDARAvailable,
            planeCount: detectedPlanes.count,
            planeDimensions: planeDims
        )

        let imageScaleValue = Double(imageW / sceneView.bounds.width)
        let planeCount = offsitePlanes.count
        let cornerCount = offsiteCorners.count
        let capturesDir = storageService.capturesDirectory

        // === FASE 2: Background — base64, modelos, JSON, file IO ===
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Construir perspectiveFrames con base64 (CPU-bound, fuera de main)
                    let perspFrames: [OffsiteFramePerspective] = intermediateFrames.map { frame in
                        OffsiteFramePerspective(
                            id: frame.id,
                            planeId: frame.planeId,
                            center2D: frame.center2D,
                            corners2D: frame.corners2D,
                            widthMeters: frame.widthMeters,
                            heightMeters: frame.heightMeters,
                            imageBase64: frame.imageJPEGData?.base64EncodedString(),
                            label: nil,
                            color: "#3B82F6"
                        )
                    }

                    // Preparar baseName antes de snapshot para poder referenciar el depth filename
                    try FileManager.default.createDirectory(at: capturesDir, withIntermediateDirectories: true)
                    let formatter = DateFormatter()
                    formatter.dateFormat = AppConstants.Capture.dateFormat
                    let baseName = "\(AppConstants.Capture.filePrefix)\(formatter.string(from: Date()))"

                    var snapshot = OffsiteSceneSnapshot(
                        capturedAt: Date(),
                        camera: cameraData,
                        planes: offsitePlanes,
                        corners: offsiteCorners,
                        wallDimensions: wallDims,
                        measurements: offsiteMeasurements,
                        perspectiveFrames: perspFrames,
                        frames: offsiteFrames,
                        textAnnotations: [],
                        lidarMetadata: lidarMetadata,
                        imageScale: imageScaleValue
                    )

                    // Guardar depth map si existe y registrar en snapshot
                    if let dmData = depthMapData, depthMapWidth > 0, depthMapHeight > 0 {
                        let depthFilename = "\(baseName).depth"
                        let depthURL = capturesDir.appendingPathComponent(depthFilename)
                        try? dmData.write(to: depthURL)
                        snapshot.depthMapFilename = depthFilename
                        snapshot.depthMapWidth = depthMapWidth
                        snapshot.depthMapHeight = depthMapHeight
                    }

                    let captureData = OffsiteCaptureData(
                        capturedAt: Date(),
                        measurements: offsiteMeasurements,
                        frames: offsiteFrames,
                        textAnnotations: [],
                        lidarMetadata: lidarMetadata,
                        imageScale: imageScaleValue,
                        sceneSnapshot: snapshot
                    )

                    let imageURL = capturesDir.appendingPathComponent("\(baseName).jpg")
                    let jsonURL = capturesDir.appendingPathComponent("\(baseName).json")
                    let thumbURL = capturesDir.appendingPathComponent("\(baseName)_thumb.jpg")

                    try captureImageData.write(to: imageURL)

                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = .prettyPrinted
                    try encoder.encode(captureData).write(to: jsonURL)

                    if let td = thumbnailData {
                        try? td.write(to: thumbURL)
                    }

                    continuation.resume(returning: (imageURL, jsonURL))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Aplana un simd_float4x4 a array de 16 Float.
    private func flattenTransform(_ t: simd_float4x4) -> [Float] {
        [t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
         t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
         t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
         t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w]
    }

    // MARK: - Mesh LiDAR

    /// Actualiza la visibilidad del wireframe del mesh.
    func updateMeshVisibility() {
        for (_, node) in meshNodes {
            node.isHidden = !showMeshWireframe
        }
    }

    /// Actualiza la visibilidad del mesh coloreado por profundidad.
    func updateDepthMeshVisibility() {
        for (_, node) in depthMeshNodes {
            node.isHidden = !showDepthColorMesh
        }
    }

    /// Actualiza la visibilidad de los feature points en la escena.
    func updateFeaturePointsVisibility() {
        guard let sceneView = sceneView else { return }
        if showFeaturePoints {
            sceneView.debugOptions.insert(.showFeaturePoints)
        } else {
            sceneView.debugOptions.remove(.showFeaturePoints)
        }
    }

    /// Crea geometría SCNGeometry desde un ARMeshGeometry con color por profundidad.
    /// Cada vértice se colorea según su distancia a la cámara: azul (cerca) → verde → rojo (lejos).
    private func createDepthColoredMeshGeometry(from meshGeometry: ARMeshGeometry, cameraPosition: SIMD3<Float>, anchorTransform: simd_float4x4) -> SCNGeometry {
        let vertexCount = meshGeometry.vertices.count
        let stride = meshGeometry.vertices.stride
        let offset = meshGeometry.vertices.offset
        let buffer = meshGeometry.vertices.buffer

        // Leer vértices y calcular colores por profundidad
        var colorData = Data(count: vertexCount * 4) // RGBA UInt8
        let vertexPointer = buffer.contents().advanced(by: offset)

        for i in 0..<vertexCount {
            let vertexPtr = vertexPointer.advanced(by: i * stride)
            let localPos = vertexPtr.assumingMemoryBound(to: SIMD3<Float>.self).pointee

            // Convertir a coordenadas mundo usando el transform del anchor
            let worldPos4 = anchorTransform * SIMD4<Float>(localPos.x, localPos.y, localPos.z, 1.0)
            let worldPos = SIMD3<Float>(worldPos4.x, worldPos4.y, worldPos4.z)

            // Distancia a la cámara
            let distance = simd_distance(worldPos, cameraPosition)
            let minD = AppConstants.PointCloud.minDepth
            let maxD = AppConstants.PointCloud.maxDepth
            let t = max(0, min(1, (distance - minD) / (maxD - minD)))

            // Mapear a color: azul → verde → rojo
            let r: UInt8
            let g: UInt8
            let b: UInt8
            if t < 0.5 {
                let s = t * 2.0 // 0..1
                r = 0
                g = UInt8(s * 255)
                b = UInt8((1.0 - s) * 255)
            } else {
                let s = (t - 0.5) * 2.0 // 0..1
                r = UInt8(s * 255)
                g = UInt8((1.0 - s) * 255)
                b = 0
            }
            let alpha = UInt8(AppConstants.PointCloud.meshAlpha * 255)

            let byteOffset = i * 4
            colorData[byteOffset] = r
            colorData[byteOffset + 1] = g
            colorData[byteOffset + 2] = b
            colorData[byteOffset + 3] = alpha
        }

        // Sources
        let verticesSource = SCNGeometrySource(
            buffer: meshGeometry.vertices.buffer,
            vertexFormat: meshGeometry.vertices.format,
            semantic: .vertex,
            vertexCount: vertexCount,
            dataOffset: meshGeometry.vertices.offset,
            dataStride: meshGeometry.vertices.stride
        )

        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: vertexCount,
            usesFloatComponents: false,
            componentsPerVector: 4,
            bytesPerComponent: 1,
            dataOffset: 0,
            dataStride: 4
        )

        // Faces
        let facesData = Data(
            bytesNoCopy: meshGeometry.faces.buffer.contents(),
            count: meshGeometry.faces.buffer.length,
            deallocator: .none
        )
        let facesElement = SCNGeometryElement(
            data: facesData,
            primitiveType: .triangles,
            primitiveCount: meshGeometry.faces.count,
            bytesPerIndex: meshGeometry.faces.bytesPerIndex
        )

        let geometry = SCNGeometry(sources: [verticesSource, colorSource], elements: [facesElement])
        let material = SCNMaterial()
        material.fillMode = .fill
        material.isDoubleSided = true
        material.lightingModel = .constant
        material.blendMode = .alpha
        geometry.materials = [material]
        return geometry
    }

    /// Crea geometría SCNGeometry desde un ARMeshGeometry (wireframe del LiDAR).
    private func createMeshGeometry(from meshGeometry: ARMeshGeometry) -> SCNGeometry {
        let verticesSource = SCNGeometrySource(
            buffer: meshGeometry.vertices.buffer,
            vertexFormat: meshGeometry.vertices.format,
            semantic: .vertex,
            vertexCount: meshGeometry.vertices.count,
            dataOffset: meshGeometry.vertices.offset,
            dataStride: meshGeometry.vertices.stride
        )

        let facesData = Data(
            bytesNoCopy: meshGeometry.faces.buffer.contents(),
            count: meshGeometry.faces.buffer.length,
            deallocator: .none
        )
        let facesElement = SCNGeometryElement(
            data: facesData,
            primitiveType: .triangles,
            primitiveCount: meshGeometry.faces.count,
            bytesPerIndex: meshGeometry.faces.bytesPerIndex
        )

        let geometry = SCNGeometry(sources: [verticesSource], elements: [facesElement])
        let material = SCNMaterial()
        material.fillMode = .lines
        material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.4)
        material.isDoubleSided = true
        material.lightingModel = .constant
        geometry.materials = [material]
        return geometry
    }

    // MARK: - Helpers

    /// Normal del plano (apunta hacia fuera de la superficie).
    /// En ARKit, el eje Y del anchor (columns.1) es siempre la normal del plano.
    private func planeNormal(_ anchor: ARPlaneAnchor) -> SIMD3<Float> {
        let t = anchor.transform
        return simd_normalize(SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z))
    }

    /// Orientación según la superficie: pared = perpendicular mirando hacia fuera;
    /// suelo = mirando hacia arriba; techo = mirando hacia abajo.
    private func orientationForPlane(anchor: ARPlaneAnchor) -> simd_quatf {
        if anchor.alignment == .vertical {
            return orientationForVerticalPlane(anchor: anchor)
        } else {
            let classification = classifyPlane(anchor)
            if classification == .ceiling {
                return orientationForCeiling(anchor: anchor)
            } else {
                return orientationForFloor(anchor: anchor)
            }
        }
    }

    /// Pared: cuadro vertical mirando hacia fuera de la pared, con el "arriba" del marco hacia el techo.
    private func orientationForVerticalPlane(anchor: ARPlaneAnchor) -> simd_quatf {
        let t = anchor.transform
        // Normal del plano = eje Y del anchor (columns.1) en ARKit
        let N = simd_normalize(SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z))
        let worldUp = SIMD3<Float>(0, 1, 0)
        
        // Y del cuadro = up (world up proyectado para ser perpendicular a la normal)
        var upDir = worldUp - simd_dot(worldUp, N) * N
        let len = simd_length(upDir)
        if len < AppConstants.AR.minNormalLength {
            upDir = SIMD3<Float>(0, 1, 0)
        } else {
            upDir = upDir / len
        }
        
        // X del cuadro = right (perpendicular a up y a la dirección de la cara)
        let rightDir = simd_normalize(simd_cross(upDir, N))
        
        // Matriz: col0=X(right), col1=Y(up), col2=Z(normal=cara del cuadro hacia fuera)
        let rot = simd_float3x3(rightDir, upDir, N)
        return simd_quatf(rot)
    }

    /// Suelo: cuadro horizontal mirando hacia arriba (visible al mirar el suelo desde arriba).
    private func orientationForFloor(anchor: ARPlaneAnchor) -> simd_quatf {
        let t = anchor.transform
        // Eje X del plano (dirección horizontal a lo largo de la superficie)
        let planeRight = simd_normalize(SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z))
        // Normal del cuadro apunta ARRIBA para que se vea desde arriba
        let faceDirection = SIMD3<Float>(0, 1, 0)
        // Eje Y del cuadro (altura) = Z × X (sistema diestro)
        let frameUp = simd_normalize(simd_cross(faceDirection, planeRight))
        let rot = simd_float3x3(planeRight, frameUp, faceDirection)
        return simd_quatf(rot)
    }

    /// Techo: cuadro horizontal mirando hacia abajo (visible al mirar el techo desde abajo).
    private func orientationForCeiling(anchor: ARPlaneAnchor) -> simd_quatf {
        let t = anchor.transform
        let planeRight = simd_normalize(SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z))
        // Normal del cuadro apunta ABAJO para que se vea desde abajo
        let faceDirection = SIMD3<Float>(0, -1, 0)
        let frameUp = simd_normalize(simd_cross(faceDirection, planeRight))
        let rot = simd_float3x3(planeRight, frameUp, faceDirection)
        return simd_quatf(rot)
    }

    /// Busca otro plano vertical que forme esquina (~90°) con el dado y esté cerca del punto.
    private func findCornerPlane(near position: SIMD3<Float>, from anchor: ARPlaneAnchor) -> ARPlaneAnchor? {
        guard anchor.alignment == .vertical else { return nil }
        let n1 = planeNormal(anchor)
        let maxDistance = AppConstants.AR.cornerMaxDistance
        let minDotForCorner = AppConstants.AR.cornerMinDot
        let maxDotForCorner = AppConstants.AR.cornerMaxDot
        for other in detectedPlanes where other.identifier != anchor.identifier && other.alignment == .vertical {
            let n2 = planeNormal(other)
            let dot = simd_dot(n1, n2)
            if dot >= minDotForCorner && dot <= maxDotForCorner {
                let center = SIMD3<Float>(other.transform.columns.3.x, other.transform.columns.3.y, other.transform.columns.3.z)
                if simd_distance(position, center) < maxDistance {
                    return other
                }
            }
        }
        return nil
    }

    /// Cuadro plano con foto. Si alignToSurface=true, se orienta según la superficie (pared/suelo/techo);
    /// si false, usa billboard constraint para que siempre mire a la cámara.
    private func createFrameNode(size: CGSize, image: UIImage? = nil, alignToSurface: Bool = false) -> SCNNode {
        let plane = SCNPlane(width: size.width, height: size.height)
        plane.firstMaterial?.diffuse.contents = image ?? UIColor.systemGray5
        plane.firstMaterial?.isDoubleSided = true
        // Lambert muestra la textura/foto fielmente sin necesitar iluminación compleja
        plane.firstMaterial?.lightingModel = .lambert
        plane.firstMaterial?.emission.contents = UIColor(white: 0.15, alpha: 1) // Brillo mínimo para que se vea en sombra
        let node = SCNNode(geometry: plane)
        node.name = "frame"
        node.renderingOrder = 1 // Encima del borde
        
        // Billboard solo cuando NO se alinea a superficie y perspectiva está deshabilitada
        if !alignToSurface && !useFramePerspective {
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .Y
            node.constraints = [billboard]
        }
        
        // Añadir borde visual al cuadro (detrás de la imagen)
        let border = SCNPlane(width: size.width + 0.02, height: size.height + 0.02)
        border.firstMaterial?.diffuse.contents = UIColor.white
        border.firstMaterial?.isDoubleSided = true
        border.firstMaterial?.lightingModel = .constant
        let borderNode = SCNNode(geometry: border)
        borderNode.position = SCNVector3(0, 0, -0.002) // Detrás de la imagen
        borderNode.name = "frame_border"
        borderNode.renderingOrder = 0 // Detrás de la foto
        node.addChildNode(borderNode)
        
        return node
    }

    /// Cuadro en esquina (dos mitades en L), cada una pegada a su pared real.
    /// NO usa billboard: cada mitad se orienta según la normal de su pared.
    private func createCornerFrameNode(size: CGSize, image: UIImage? = nil, planeA: ARPlaneAnchor, planeB: ARPlaneAnchor) -> (SCNNode, [SCNNode]) {
        let parent = SCNNode()
        parent.name = "frame_corner"
        // SIN billboard — cada mitad se alinea a su pared

        let halfWidth = CGFloat(size.width) / 2.0
        let contents: Any = image ?? UIColor.systemGray5

        // Calcular tangentes de cada pared (dirección horizontal a lo largo de la pared)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let normalA = planeNormal(planeA)
        let normalB = planeNormal(planeB)

        var tangentA = simd_normalize(simd_cross(worldUp, normalA))
        if simd_length(tangentA) < AppConstants.AR.minNormalLength {
            tangentA = SIMD3<Float>(1, 0, 0)
        }
        // tangentA debe apuntar alejándose de la pared B (hacia el interior de pared A)
        if simd_dot(tangentA, normalB) > 0 {
            tangentA = -tangentA
        }

        var tangentB = simd_normalize(simd_cross(worldUp, normalB))
        if simd_length(tangentB) < AppConstants.AR.minNormalLength {
            tangentB = SIMD3<Float>(0, 0, 1)
        }
        // tangentB debe apuntar alejándose de la pared A
        if simd_dot(tangentB, normalA) > 0 {
            tangentB = -tangentB
        }

        // === Dividir imagen en dos mitades si existe ===
        var contentsA: Any = contents
        var contentsB: Any = contents
        if let img = image, let cgImg = img.cgImage {
            let pixelW = cgImg.width
            let pixelH = cgImg.height
            let leftRect = CGRect(x: 0, y: 0, width: pixelW / 2, height: pixelH)
            let rightRect = CGRect(x: pixelW / 2, y: 0, width: pixelW - pixelW / 2, height: pixelH)
            if let cgLeft = cgImg.cropping(to: leftRect) {
                contentsA = UIImage(cgImage: cgLeft)
            }
            if let cgRight = cgImg.cropping(to: rightRect) {
                contentsB = UIImage(cgImage: cgRight)
            }
        }

        // --- Mitad A (pared A) ---
        let plane1 = SCNPlane(width: halfWidth, height: size.height)
        plane1.firstMaterial?.diffuse.contents = contentsA
        plane1.firstMaterial?.isDoubleSided = true
        plane1.firstMaterial?.lightingModel = .lambert
        plane1.firstMaterial?.emission.contents = UIColor(white: 0.15, alpha: 1)
        let node1 = SCNNode(geometry: plane1)
        node1.simdOrientation = orientationForVerticalPlane(anchor: planeA)
        // Centrar la mitad a lo largo de su pared, ligeramente fuera de la superficie
        node1.simdPosition = tangentA * Float(halfWidth) / 2.0 + normalA * 0.005
        node1.name = "frame_half_A"
        node1.renderingOrder = 1

        let border1 = SCNPlane(width: halfWidth + 0.015, height: size.height + 0.015)
        border1.firstMaterial?.diffuse.contents = UIColor.white
        border1.firstMaterial?.isDoubleSided = true
        border1.firstMaterial?.lightingModel = .constant
        let borderNode1 = SCNNode(geometry: border1)
        borderNode1.position = SCNVector3(0, 0, -0.002)
        borderNode1.name = "frame_border"
        borderNode1.renderingOrder = 0
        node1.addChildNode(borderNode1)

        // --- Mitad B (pared B) ---
        let plane2 = SCNPlane(width: halfWidth, height: size.height)
        plane2.firstMaterial?.diffuse.contents = contentsB
        plane2.firstMaterial?.isDoubleSided = true
        plane2.firstMaterial?.lightingModel = .lambert
        plane2.firstMaterial?.emission.contents = UIColor(white: 0.15, alpha: 1)
        let node2 = SCNNode(geometry: plane2)
        node2.simdOrientation = orientationForVerticalPlane(anchor: planeB)
        node2.simdPosition = tangentB * Float(halfWidth) / 2.0 + normalB * 0.005
        node2.name = "frame_half_B"
        node2.renderingOrder = 1

        let border2 = SCNPlane(width: halfWidth + 0.015, height: size.height + 0.015)
        border2.firstMaterial?.diffuse.contents = UIColor.white
        border2.firstMaterial?.isDoubleSided = true
        border2.firstMaterial?.lightingModel = .constant
        let borderNode2 = SCNNode(geometry: border2)
        borderNode2.position = SCNVector3(0, 0, -0.002)
        borderNode2.name = "frame_border"
        borderNode2.renderingOrder = 0
        node2.addChildNode(borderNode2)

        parent.addChildNode(node1)
        parent.addChildNode(node2)
        return (parent, [node1, node2])
    }

    /// Aplica imagen al nodo (una geometría o dos hijos en esquina).
    private func applyImage(to node: SCNNode, image: UIImage?, size: CGSize, isCorner: Bool) {
        let contents: Any = image ?? UIColor.systemGray5
        if isCorner {
            // Dividir imagen en mitades para esquina
            var contentsA: Any = contents
            var contentsB: Any = contents
            if let img = image, let cgImg = img.cgImage {
                let pixelW = cgImg.width
                let pixelH = cgImg.height
                let leftRect = CGRect(x: 0, y: 0, width: pixelW / 2, height: pixelH)
                let rightRect = CGRect(x: pixelW / 2, y: 0, width: pixelW - pixelW / 2, height: pixelH)
                if let cgLeft = cgImg.cropping(to: leftRect) { contentsA = UIImage(cgImage: cgLeft) }
                if let cgRight = cgImg.cropping(to: rightRect) { contentsB = UIImage(cgImage: cgRight) }
            }
            let halfWidth = CGFloat(size.width) / 2.0
            // Solo aplicar a nodos frame_half, no a bordes
            for child in node.childNodes {
                guard child.name == "frame_half_A" || child.name == "frame_half_B" else { continue }
                if let plane = child.geometry as? SCNPlane {
                    plane.firstMaterial?.diffuse.contents = (child.name == "frame_half_A") ? contentsA : contentsB
                    plane.width = halfWidth
                    plane.height = size.height
                }
            }
        } else if let plane = node.geometry as? SCNPlane {
            plane.firstMaterial?.diffuse.contents = contents
            plane.width = size.width
            plane.height = size.height
        }
    }

    private func updateFrameGeometry(node: SCNNode, size: CGSize) {
        if let plane = node.geometry as? SCNPlane {
            plane.width = size.width
            plane.height = size.height
        }
        for child in node.childNodes {
            if let plane = child.geometry as? SCNPlane {
                plane.width = size.width
                plane.height = size.height
            }
        }
    }
}

// MARK: - ARSCNViewDelegate

extension ARSceneManager: ARSCNViewDelegate {
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            Task { @MainActor in
                if !detectedPlanes.contains(where: { $0.identifier == planeAnchor.identifier }) {
                    detectedPlanes.append(planeAnchor)
                }
                let extent = planeAnchor.extent
                lastPlaneDimensions = PlaneDimensions(width: extent.x, height: extent.z, extent: extent)

                // Actualizar visualizaciones
                updatePlaneOverlays()
                detectAllCorners()
            }
        } else if let meshAnchor = anchor as? ARMeshAnchor {
            Task { @MainActor in
                let meshNode = SCNNode(geometry: createMeshGeometry(from: meshAnchor.geometry))
                meshNode.isHidden = !showMeshWireframe
                node.addChildNode(meshNode)
                meshNodes[meshAnchor.identifier] = meshNode

                // Nodo de mesh coloreado por profundidad
                let cameraPos = sceneView?.session.currentFrame?.camera.transform.columns.3 ?? SIMD4<Float>(0, 0, 0, 1)
                let camPosition = SIMD3<Float>(cameraPos.x, cameraPos.y, cameraPos.z)
                let depthNode = SCNNode(geometry: createDepthColoredMeshGeometry(from: meshAnchor.geometry, cameraPosition: camPosition, anchorTransform: meshAnchor.transform))
                depthNode.isHidden = !showDepthColorMesh
                depthNode.renderingOrder = AppConstants.PointCloud.renderingOrder
                node.addChildNode(depthNode)
                depthMeshNodes[meshAnchor.identifier] = depthNode
            }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            Task { @MainActor in
                if let idx = detectedPlanes.firstIndex(where: { $0.identifier == planeAnchor.identifier }) {
                    detectedPlanes[idx] = planeAnchor
                }
                let extent = planeAnchor.extent
                lastPlaneDimensions = PlaneDimensions(width: extent.x, height: extent.z, extent: extent)

                // Actualizar visualizaciones en cada actualización de plano
                updatePlaneOverlays()
                // Detectar esquinas periódicamente
                if detectedPlanes.count > 1 {
                    detectAllCorners()
                }
            }
        } else if let meshAnchor = anchor as? ARMeshAnchor {
            Task { @MainActor in
                guard let meshNode = meshNodes[meshAnchor.identifier] else { return }
                meshNode.geometry = createMeshGeometry(from: meshAnchor.geometry)
                meshNode.isHidden = !showMeshWireframe

                // Actualizar depth mesh
                if let depthNode = depthMeshNodes[meshAnchor.identifier] {
                    let cameraPos = sceneView?.session.currentFrame?.camera.transform.columns.3 ?? SIMD4<Float>(0, 0, 0, 1)
                    let camPosition = SIMD3<Float>(cameraPos.x, cameraPos.y, cameraPos.z)
                    depthNode.geometry = createDepthColoredMeshGeometry(from: meshAnchor.geometry, cameraPosition: camPosition, anchorTransform: meshAnchor.transform)
                    depthNode.isHidden = !showDepthColorMesh
                }
            }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            Task { @MainActor in
                detectedPlanes.removeAll { $0.identifier == planeAnchor.identifier }
                updatePlaneOverlays()
                detectAllCorners()
            }
        } else if let meshAnchor = anchor as? ARMeshAnchor {
            Task { @MainActor in
                meshNodes[meshAnchor.identifier]?.removeFromParentNode()
                meshNodes.removeValue(forKey: meshAnchor.identifier)
                depthMeshNodes[meshAnchor.identifier]?.removeFromParentNode()
                depthMeshNodes.removeValue(forKey: meshAnchor.identifier)
            }
        }
    }

}

// MARK: - ARSessionDelegate

extension ARSceneManager: ARSessionDelegate {
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            logger.error("Sesión AR falló: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        Task { @MainActor in
            currentTrackingState = camera.trackingState
        }
    }
}

