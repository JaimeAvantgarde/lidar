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

    // MARK: - Planos, esquinas y snap
    /// Si true, se muestran overlays visuales sobre los planos detectados.
    var showPlaneOverlays: Bool = false
    /// Si true, se muestran marcadores en las esquinas detectadas.
    var showCornerMarkers: Bool = false
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
    
    /// Iniciar sesión AR: planos horizontales y verticales, opcional mesh LiDAR
    func startSession() {
        guard let sceneView = sceneView else { return }
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        if isLiDARAvailable {
            configuration.sceneReconstruction = .mesh
        }
        configuration.frameSemantics.insert(.sceneDepth)
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        errorMessage = nil
    }
    
    func pauseSession() {
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
            let frameNode = createFrameNode(size: size, image: image)
            frameNode.simdPosition = position
            if let anchor = planeAnchor {
                // Alinear el cuadro con la perspectiva real del plano
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
    
    /// Mover un cuadro a una nueva posición (y opcionalmente reorientar al plano; esquina solo mueve posición).
    func moveFrame(id: UUID, to position: SIMD3<Float>, planeAnchor: ARPlaneAnchor? = nil) {
        guard let index = placedFrames.firstIndex(where: { $0.id == id }) else { return }
        let placed = placedFrames[index]
        let node = placed.node
        node.simdPosition = position
        if !placed.isCornerFrame, let anchor = planeAnchor {
            node.simdOrientation = orientationForPlane(anchor: anchor)
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
            newNode = createFrameNode(size: newSize, image: image)
            newNode.simdPosition = old.node.simdPosition
            newNode.simdOrientation = old.node.simdOrientation
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
    }

    /// Desactiva el modo medición.
    func cancelMeasurement() {
        isMeasurementMode = false
        measurementFirstPoint = nil
        removeFirstPointMarker()
    }

    /// Registra un punto en la escena AR. Aplica snap a bordes/esquinas si está habilitado.
    /// Si es el primero, lo guarda y muestra marcador; si es el segundo, crea la medición.
    func addMeasurementPoint(_ position: SIMD3<Float>) {
        guard isMeasurementMode else { return }
        let snappedPosition = snapToEdgesEnabled ? snapToNearestEdgeOrCorner(position) : position
        
        if let first = measurementFirstPoint {
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

    /// Añade a la escena la línea, etiqueta justo encima de la línea y esferas en los extremos.
    private func addMeasurementDisplay(measurement: ARMeasurement) {
        guard let sceneView = sceneView else { return }
        let pointA = measurement.pointA
        let pointB = measurement.pointB
        let distance = measurement.distance
        let parent = SCNNode()
        parent.name = "measurement_\(measurement.id.uuidString)"
        let mid = (pointA + pointB) * 0.5
        parent.position = SCNVector3(mid.x, mid.y, mid.z)
        let length = distance
        let dir = simd_normalize(pointB - pointA)
        let worldUp = SIMD3<Float>(0, 1, 0)
        var axis = simd_cross(worldUp, dir)
        if simd_length(axis) < AppConstants.AR.minNormalLength { axis = SIMD3<Float>(1, 0, 0) }
        axis = simd_normalize(axis)
        let angle = acos(simd_dot(worldUp, dir))

        let cylinder = SCNCylinder(radius: AppConstants.AR.measurementLineRadius, height: CGFloat(length))
        cylinder.radialSegmentCount = AppConstants.AR.lineRadialSegments
        cylinder.firstMaterial?.diffuse.contents = UIColor.systemGreen
        cylinder.firstMaterial?.emission.contents = UIColor.green.withAlphaComponent(0.2)
        let lineNode = SCNNode(geometry: cylinder)
        lineNode.position = SCNVector3(0, 0, 0)
        lineNode.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
        parent.addChildNode(lineNode)

        let labelString = measurementUnit.format(distanceMeters: distance)
        let text = SCNText(string: labelString, extrusionDepth: AppConstants.AR.measurementTextExtrusion)
        text.font = .systemFont(ofSize: AppConstants.AR.measurementTextFontSize, weight: .semibold)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.firstMaterial?.emission.contents = UIColor.darkGray
        text.firstMaterial?.isDoubleSided = true
        let textNode = SCNNode(geometry: text)
        let s = AppConstants.AR.measurementTextScale
        textNode.scale = SCNVector3(s, s, s)
        let aboveLine = simd_cross(dir, worldUp)
        let aboveNorm = simd_length(aboveLine) > AppConstants.AR.minNormalLength ? simd_normalize(aboveLine) : SIMD3<Float>(1, 0, 0)
        let offset = AppConstants.AR.measurementTextOffset
        textNode.position = SCNVector3(aboveNorm.x * offset, aboveNorm.y * offset, aboveNorm.z * offset)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        textNode.constraints = [billboard]
        parent.addChildNode(textNode)

        let sphereGeo = SCNSphere(radius: AppConstants.AR.measurementEndpointRadius)
        sphereGeo.firstMaterial?.diffuse.contents = UIColor.systemGreen
        sphereGeo.firstMaterial?.emission.contents = UIColor.green.withAlphaComponent(0.2)
        let sphereA = SCNNode(geometry: sphereGeo)
        sphereA.position = SCNVector3((pointA.x - mid.x), (pointA.y - mid.y), (pointA.z - mid.z))
        parent.addChildNode(sphereA)
        let sphereGeoB = SCNSphere(radius: AppConstants.AR.measurementEndpointRadius)
        sphereGeoB.firstMaterial?.diffuse.contents = UIColor.systemGreen
        sphereGeoB.firstMaterial?.emission.contents = UIColor.green.withAlphaComponent(0.2)
        let sphereB = SCNNode(geometry: sphereGeoB)
        sphereB.position = SCNVector3((pointB.x - mid.x), (pointB.y - mid.y), (pointB.z - mid.z))
        parent.addChildNode(sphereB)

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

    // MARK: - Captura offsite

    enum CaptureError: Error, LocalizedError {
        case noSceneView
        case invalidBounds
        case imageEncodingFailed
        case saveFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .noSceneView: return "Vista AR no disponible"
            case .invalidBounds: return "Tamaño de vista inválido"
            case .imageEncodingFailed: return "No se pudo codificar la imagen"
            case .saveFailed(let error): return "Error al guardar: \(error.localizedDescription)"
            }
        }
    }

    /// Captura la vista AR actual con TODOS los datos 3D de la escena.
    /// Incluye: planos con vértices proyectados, esquinas, mediciones, cuadros con perspectiva,
    /// datos de cámara, metadata del LiDAR, y dimensiones de todas las paredes.
    /// - Returns: (URL de la imagen, URL del JSON) o lanza error si falla.
    func captureForOffsite() throws -> (imageURL: URL, jsonURL: URL) {
        guard let sceneView = sceneView else { throw CaptureError.noSceneView }
        
        // Actualizar detección de esquinas antes de capturar
        detectAllCorners()
        
        // Capturar con alta resolución (escala 2x en dispositivos retina)
        let scale = UIScreen.main.scale
        UIGraphicsBeginImageContextWithOptions(sceneView.bounds.size, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        sceneView.drawHierarchy(in: sceneView.bounds, afterScreenUpdates: true)
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            throw CaptureError.imageEncodingFailed
        }
        
        let w = sceneView.bounds.width
        let h = sceneView.bounds.height
        guard w > 0, h > 0 else { throw CaptureError.invalidBounds }

        // === 1. Proyectar mediciones 3D a coordenadas 2D normalizadas ===
        let offsiteMeasurements: [OffsiteMeasurement] = measurements.map { m in
            let pa = sceneView.projectPoint(SCNVector3(m.pointA.x, m.pointA.y, m.pointA.z))
            let pb = sceneView.projectPoint(SCNVector3(m.pointB.x, m.pointB.y, m.pointB.z))
            let pointA = NormalizedPoint(x: Double(pa.x) / Double(w), y: Double(pa.y) / Double(h))
            let pointB = NormalizedPoint(x: Double(pb.x) / Double(w), y: Double(pb.y) / Double(h))
            return OffsiteMeasurement(id: m.id, distanceMeters: Double(m.distance), pointA: pointA, pointB: pointB, isFromAR: true)
        }
        
        // === 2. Proyectar cuadros con perspectiva REAL ===
        let offsiteFrames: [OffsiteFrame] = placedFrames.compactMap { frame in
            let frameNode = frame.node
            let framePosition = frameNode.simdWorldPosition
            let frameWidthMeters = Double(frame.size.width)
            let frameHeightMeters = Double(frame.size.height)
            
            // Calcular las 4 esquinas del cuadro en 3D usando su orientación real
            let halfW = Float(frame.size.width) / 2.0
            let halfH = Float(frame.size.height) / 2.0
            
            // Usar la orientación real del nodo para las esquinas
            let right = frameNode.simdWorldRight
            let up = frameNode.simdWorldUp
            
            let tl3D = framePosition - right * halfW + up * halfH
            let tr3D = framePosition + right * halfW + up * halfH
            let br3D = framePosition + right * halfW - up * halfH
            let bl3D = framePosition - right * halfW - up * halfH
            
            let projTL = sceneView.projectPoint(SCNVector3(tl3D))
            let projTR = sceneView.projectPoint(SCNVector3(tr3D))
            let projBR = sceneView.projectPoint(SCNVector3(br3D))
            let projBL = sceneView.projectPoint(SCNVector3(bl3D))
            
            let topLeftNorm = NormalizedPoint(x: Double(projTL.x) / Double(w), y: Double(projTL.y) / Double(h))
            let widthNorm = Double(abs(projTR.x - projTL.x)) / Double(w)
            let heightNorm = Double(abs(projBL.y - projTL.y)) / Double(h)
            
            guard topLeftNorm.x >= -0.2 && topLeftNorm.x <= 1.2 && topLeftNorm.y >= -0.2 && topLeftNorm.y <= 1.2 else {
                return nil
            }
            
            var imageBase64: String?
            if let frameImage = frame.image,
               let jpegData = frameImage.jpegData(compressionQuality: 0.8) {
                imageBase64 = jpegData.base64EncodedString()
            }
            
            return OffsiteFrame(
                id: frame.id,
                topLeft: topLeftNorm,
                width: widthNorm,
                height: heightNorm,
                label: nil,
                color: "#3B82F6",
                widthMeters: frameWidthMeters,
                heightMeters: frameHeightMeters,
                imageBase64: imageBase64,
                isCornerFrame: frame.isCornerFrame
            )
        }
        
        // === 3. Cuadros con perspectiva real (4 esquinas proyectadas) ===
        let perspFrames: [OffsiteFramePerspective] = placedFrames.compactMap { frame in
            let frameNode = frame.node
            let pos: SIMD3<Float> = frameNode.simdWorldPosition
            let halfW: Float = Float(frame.size.width) / 2.0
            let halfH: Float = Float(frame.size.height) / 2.0
            let right: SIMD3<Float> = frameNode.simdWorldRight
            let up: SIMD3<Float> = frameNode.simdWorldUp
            
            let rW: SIMD3<Float> = right * halfW
            let uH: SIMD3<Float> = up * halfH
            let tl: SIMD3<Float> = pos - rW + uH
            let tr: SIMD3<Float> = pos + rW + uH
            let br: SIMD3<Float> = pos + rW - uH
            let bl: SIMD3<Float> = pos - rW - uH
            let corners3D: [SIMD3<Float>] = [tl, tr, br, bl]
            
            let corners2D = corners3D.map { pt -> [Double] in
                let p = sceneView.projectPoint(SCNVector3(pt))
                return [Double(p.x) / Double(w), Double(p.y) / Double(h)]
            }
            
            let center = sceneView.projectPoint(SCNVector3(pos))
            let center2D = NormalizedPoint(x: Double(center.x) / Double(w), y: Double(center.y) / Double(h))
            
            var imageBase64: String?
            if let img = frame.image, let data = img.jpegData(compressionQuality: 0.8) {
                imageBase64 = data.base64EncodedString()
            }
            
            return OffsiteFramePerspective(
                id: frame.id,
                planeId: frame.planeAnchor?.identifier.uuidString,
                center2D: center2D,
                corners2D: corners2D,
                widthMeters: Double(frame.size.width),
                heightMeters: Double(frame.size.height),
                imageBase64: imageBase64,
                label: nil,
                color: "#3B82F6"
            )
        }
        
        // === 4. Exportar TODOS los planos con vértices 2D proyectados ===
        let offsitePlanes: [OffsitePlaneData] = detectedPlanes.map { plane in
            let t = plane.transform
            let center = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            let normal = planeNormal(plane)
            let classification = classifyPlane(plane)
            
            // Obtener vértices 3D del plano (4 esquinas)
            let edges = getPlaneEdgePoints(plane)
            
            // Proyectar vértices a 2D
            let projected = edges.map { pt -> [Double] in
                let p = sceneView.projectPoint(SCNVector3(pt))
                return [Double(p.x) / Double(w), Double(p.y) / Double(h)]
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
        
        // === 5. Exportar esquinas ===
        let offsiteCorners: [OffsiteCornerData] = detectedCorners.map { corner in
            let p = sceneView.projectPoint(SCNVector3(corner.position))
            let pos2D = NormalizedPoint(x: Double(p.x) / Double(w), y: Double(p.y) / Double(h))
            return OffsiteCornerData(
                position3D: corner.position,
                position2D: pos2D,
                angleDegrees: Double(corner.angle),
                planeIdA: corner.planeA.identifier.uuidString,
                planeIdB: corner.planeB.identifier.uuidString
            )
        }
        
        // === 6. Dimensiones de paredes ===
        let wallDims: [OffsiteWallDimension] = detectedPlanes.filter { $0.alignment == .vertical }.map { plane in
            let edges = getPlaneEdgePoints(plane)
            let verts = edges.map { pt -> [Double] in
                let p = sceneView.projectPoint(SCNVector3(pt))
                return [Double(p.x) / Double(w), Double(p.y) / Double(h)]
            }
            return OffsiteWallDimension(
                planeId: plane.identifier.uuidString,
                widthMeters: Double(plane.extent.x),
                heightMeters: Double(plane.extent.z),
                vertices2D: verts
            )
        }
        
        // === 7. Datos de cámara ===
        var cameraData: OffsiteCameraData?
        if let frame = sceneView.session.currentFrame {
            cameraData = OffsiteCameraData(
                intrinsics: frame.camera.intrinsics,
                transform: frame.camera.transform,
                imageWidth: Int(w * scale),
                imageHeight: Int(h * scale)
            )
        }
        
        // === 8. Metadata del LiDAR ===
        let planeDims = detectedPlanes.map { plane in
            PlaneDimension(width: Double(plane.extent.x), height: Double(plane.extent.z))
        }
        let lidarMetadata = OffsiteLiDARMetadata(
            isLiDARAvailable: isLiDARAvailable,
            planeCount: detectedPlanes.count,
            planeDimensions: planeDims
        )
        
        // === 9. Crear snapshot completo ===
        let snapshot = OffsiteSceneSnapshot(
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
            imageScale: Double(scale)
        )
        
        let captureData = OffsiteCaptureData(
            capturedAt: Date(),
            measurements: offsiteMeasurements,
            frames: offsiteFrames,
            textAnnotations: [],
            lidarMetadata: lidarMetadata,
            imageScale: Double(scale),
            sceneSnapshot: snapshot
        )

        // Delegar persistencia al StorageService
        do {
            let files = try storageService.createCaptureFiles(image: image)
            try storageService.saveCaptureData(captureData, to: files.jsonURL)
            logger.info("Captura offsite guardada: \(files.baseName) con \(offsitePlanes.count) planos, \(offsiteCorners.count) esquinas")
            return (files.imageURL, files.jsonURL)
        } catch {
            logger.error("Error en captura offsite: \(error.localizedDescription)")
            throw CaptureError.saveFailed(error)
        }
    }
    
    /// Aplana un simd_float4x4 a array de 16 Float.
    private func flattenTransform(_ t: simd_float4x4) -> [Float] {
        [t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
         t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
         t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
         t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w]
    }

    // MARK: - Helpers

    /// Normal del plano (apunta hacia fuera de la pared). Para plano vertical suele ser column.2.
    private func planeNormal(_ anchor: ARPlaneAnchor) -> SIMD3<Float> {
        let t = anchor.transform
        return SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
    }

    /// Orientación según el plano: en pared (vertical) = cuadro vertical; en techo/suelo (horizontal) = cuadro horizontal (tumbado).
    private func orientationForPlane(anchor: ARPlaneAnchor) -> simd_quatf {
        if anchor.alignment == .vertical {
            return orientationForVerticalPlane(anchor: anchor)
        } else {
            return orientationForHorizontalPlane(anchor: anchor)
        }
    }

    /// Pared: cuadro vertical (alto, "de pie"), arriba del marco = hacia el techo.
    private func orientationForVerticalPlane(anchor: ARPlaneAnchor) -> simd_quatf {
        let t = anchor.transform
        let N = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        let worldUp = SIMD3<Float>(0, 1, 0)
        var U = worldUp - simd_dot(worldUp, N) * N
        let len = simd_length(U)
        if len < AppConstants.AR.minNormalLength {
            U = SIMD3<Float>(0, 1, 0)
        } else {
            U = U / len
        }
        U = -U
        let R = simd_cross(N, U)
        let Rnorm = simd_normalize(R)
        let rot3 = simd_float3x3(U, Rnorm, -N)
        return simd_quatf(rot3)
    }

    /// Techo/suelo: cuadro horizontal (tumbado en el plano), no "de pie".
    private func orientationForHorizontalPlane(anchor: ARPlaneAnchor) -> simd_quatf {
        let t = anchor.transform
        let N = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        let worldForward = SIMD3<Float>(0, 0, -1)
        var U = worldForward - simd_dot(worldForward, N) * N
        let len = simd_length(U)
        if len < 0.001 {
            U = SIMD3<Float>(1, 0, 0)
        } else {
            U = U / len
        }
        let R = simd_cross(N, U)
        let Rnorm = simd_normalize(R)
        let rot3 = simd_float3x3(Rnorm, U, -N)
        return simd_quatf(rot3)
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

    /// Cuadro plano con foto. Si useFramePerspective=true, se alinea al plano (pared);
    /// si false, usa billboard constraint clásico.
    private func createFrameNode(size: CGSize, image: UIImage? = nil) -> SCNNode {
        let plane = SCNPlane(width: size.width, height: size.height)
        plane.firstMaterial?.diffuse.contents = image ?? UIColor.systemGray5
        plane.firstMaterial?.isDoubleSided = true
        plane.firstMaterial?.specular.contents = UIColor.white
        plane.firstMaterial?.lightingModel = .physicallyBased
        let node = SCNNode(geometry: plane)
        node.name = "frame"
        
        // Solo usar billboard si la perspectiva no está habilitada
        if !useFramePerspective {
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .Y
            node.constraints = [billboard]
        }
        
        // Añadir borde visual al cuadro
        let border = SCNPlane(width: size.width + 0.02, height: size.height + 0.02)
        border.firstMaterial?.diffuse.contents = UIColor.white
        border.firstMaterial?.isDoubleSided = true
        let borderNode = SCNNode(geometry: border)
        borderNode.position = SCNVector3(0, 0, -0.001) // Ligeramente detrás
        borderNode.name = "frame_border"
        node.addChildNode(borderNode)
        
        return node
    }

    /// Cuadro en esquina (dos caras en L); el conjunto siempre se ve de frente (billboard).
    private func createCornerFrameNode(size: CGSize, image: UIImage? = nil, planeA: ARPlaneAnchor, planeB: ARPlaneAnchor) -> (SCNNode, [SCNNode]) {
        let parent = SCNNode()
        parent.name = "frame_corner"
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        parent.constraints = [billboard]
        let contents = image ?? UIColor.systemGray5
        let plane1 = SCNPlane(width: size.width, height: size.height)
        plane1.firstMaterial?.diffuse.contents = contents
        plane1.firstMaterial?.isDoubleSided = true
        plane1.firstMaterial?.specular.contents = UIColor.white
        let node1 = SCNNode(geometry: plane1)
        node1.simdOrientation = orientationForPlane(anchor: planeA)
        let plane2 = SCNPlane(width: size.width, height: size.height)
        plane2.firstMaterial?.diffuse.contents = contents
        plane2.firstMaterial?.isDoubleSided = true
        plane2.firstMaterial?.specular.contents = UIColor.white
        let node2 = SCNNode(geometry: plane2)
        node2.simdOrientation = orientationForPlane(anchor: planeB)
        parent.addChildNode(node1)
        parent.addChildNode(node2)
        return (parent, [node1, node2])
    }

    /// Aplica imagen al nodo (una geometría o dos hijos en esquina).
    private func applyImage(to node: SCNNode, image: UIImage?, size: CGSize, isCorner: Bool) {
        let contents = image ?? UIColor.systemGray5
        if isCorner {
            for child in node.childNodes {
                if let plane = child.geometry as? SCNPlane {
                    plane.firstMaterial?.diffuse.contents = contents
                    plane.width = size.width
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
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
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
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        Task { @MainActor in
            if let idx = detectedPlanes.firstIndex(where: { $0.identifier == planeAnchor.identifier }) {
                detectedPlanes[idx] = planeAnchor
            }
            let extent = planeAnchor.extent
            lastPlaneDimensions = PlaneDimensions(width: extent.x, height: extent.z, extent: extent)
            
            // Actualizar visualizaciones en cada actualización de plano
            updatePlaneOverlays()
            // Detectar esquinas periódicamente (cada 5 actualizaciones para performance)
            if detectedPlanes.count > 1 {
                detectAllCorners()
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        Task { @MainActor in
            detectedPlanes.removeAll { $0.identifier == planeAnchor.identifier }
            updatePlaneOverlays()
            detectAllCorners()
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
        // Opcional: avisar a la UI si tracking es limitado
    }
}

