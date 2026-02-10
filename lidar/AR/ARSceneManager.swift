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
    
    /// Colocar un cuadro (foto de galería) en el punto 3D; si hay esquina de dos paredes, se adapta en L.
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
                frameNode.simdOrientation = orientationForPlane(anchor: anchor)
            }
            let placed = PlacedFrame(node: frameNode, planeAnchor: planeAnchor, size: size, image: image, isCornerFrame: false)
            sceneView?.scene.rootNode.addChildNode(frameNode)
            placedFrames.append(placed)
            selectedFrameId = placed.id
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

    /// Registra un punto en la escena AR. Si es el primero, lo guarda y muestra marcador; si es el segundo, crea la medición.
    func addMeasurementPoint(_ position: SIMD3<Float>) {
        guard isMeasurementMode else { return }
        if let first = measurementFirstPoint {
            removeFirstPointMarker()
            let distance = simd_distance(first, position)
            let measurement = ARMeasurement(pointA: first, pointB: position, distance: distance)
            measurements.append(measurement)
            addMeasurementDisplay(measurement: measurement)
            measurementFirstPoint = nil
        } else {
            measurementFirstPoint = position
            showFirstPointMarker(at: position)
        }
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

    /// Captura la vista AR actual y todas las mediciones con posiciones 2D normalizadas.
    /// Usa `StorageService` para persistir imagen + JSON en Documents/OffsiteCaptures/.
    /// - Returns: (URL de la imagen, URL del JSON) o lanza error si falla.
    func captureForOffsite() throws -> (imageURL: URL, jsonURL: URL) {
        guard let sceneView = sceneView else { throw CaptureError.noSceneView }
        let image = sceneView.snapshot()
        let w = sceneView.bounds.width
        let h = sceneView.bounds.height
        guard w > 0, h > 0 else { throw CaptureError.invalidBounds }

        // Proyectar mediciones 3D a coordenadas 2D normalizadas
        let offsiteMeasurements: [OffsiteMeasurement] = measurements.map { m in
            let pa = sceneView.projectPoint(SCNVector3(m.pointA.x, m.pointA.y, m.pointA.z))
            let pb = sceneView.projectPoint(SCNVector3(m.pointB.x, m.pointB.y, m.pointB.z))
            let pointA = NormalizedPoint(x: Double(pa.x) / Double(w), y: Double(pa.y) / Double(h))
            let pointB = NormalizedPoint(x: Double(pb.x) / Double(w), y: Double(pb.y) / Double(h))
            return OffsiteMeasurement(id: m.id, distanceMeters: Double(m.distance), pointA: pointA, pointB: pointB, isFromAR: true)
        }
        let captureData = OffsiteCaptureData(capturedAt: Date(), measurements: offsiteMeasurements, frames: [], textAnnotations: [])

        // Delegar persistencia al StorageService
        do {
            let files = try storageService.createCaptureFiles(image: image)
            try storageService.saveCaptureData(captureData, to: files.jsonURL)
            logger.info("Captura offsite guardada: \(files.baseName)")
            return (files.imageURL, files.jsonURL)
        } catch {
            logger.error("Error en captura offsite: \(error.localizedDescription)")
            throw CaptureError.saveFailed(error)
        }
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

    /// Cuadro plano con foto; siempre se ve de frente (billboard) en pared, techo o suelo.
    private func createFrameNode(size: CGSize, image: UIImage? = nil) -> SCNNode {
        let plane = SCNPlane(width: size.width, height: size.height)
        plane.firstMaterial?.diffuse.contents = image ?? UIColor.systemGray5
        plane.firstMaterial?.isDoubleSided = true
        plane.firstMaterial?.specular.contents = UIColor.white
        let node = SCNNode(geometry: plane)
        node.name = "frame"
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        node.constraints = [billboard]
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
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        Task { @MainActor in
            detectedPlanes.removeAll { $0.identifier == planeAnchor.identifier }
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

