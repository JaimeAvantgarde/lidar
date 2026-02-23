//
//  OffsiteCapturesViewModel.swift
//  lidar
//
//  ViewModels para la funcionalidad de capturas offsite.
//  Separa la lógica de negocio de las vistas siguiendo el patrón MVVM.
//

import SwiftUI
import Observation
import os.log
import simd

// MARK: - List ViewModel

/// Resumen ligero de una captura para mostrar en la lista sin decodificar todo el JSON.
struct CapturePreview {
    let measurementCount: Int
    let frameCount: Int
}

/// ViewModel para la lista de capturas offsite.
@MainActor
@Observable
final class OffsiteCapturesListViewModel {
    var entries: [OffsiteCaptureEntry] = []

    private let storageService: StorageServiceProtocol
    private let hapticService: HapticServiceProtocol
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lidar", category: "OffsiteListVM")
    private var previewCache: [String: CapturePreview] = [:]

    init(
        storageService: StorageServiceProtocol = StorageService.shared,
        hapticService: HapticServiceProtocol = HapticService.shared
    ) {
        self.storageService = storageService
        self.hapticService = hapticService
    }

    func loadEntries() {
        entries = storageService.loadOffsiteCaptures()
        previewCache.removeAll()
        logger.info("Cargadas \(self.entries.count) capturas")
    }

    func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            let entry = entries[index]
            previewCache.removeValue(forKey: entry.id)
            storageService.deleteCapture(entry)
        }
        entries.remove(atOffsets: offsets)
        hapticService.notification(type: .success)
    }

    func thumbnailURL(for entry: OffsiteCaptureEntry) -> URL {
        entry.imageURL.deletingLastPathComponent()
            .appendingPathComponent(entry.imageURL.deletingPathExtension().lastPathComponent + "_thumb.jpg")
    }

    /// Devuelve un preview cacheado de los conteos de la captura.
    func preview(for entry: OffsiteCaptureEntry) -> CapturePreview? {
        if let cached = previewCache[entry.id] {
            return cached
        }
        guard let captureData = storageService.loadCaptureData(from: entry.jsonURL) else { return nil }
        let preview = CapturePreview(
            measurementCount: captureData.measurements.count,
            frameCount: captureData.frames.count
        )
        previewCache[entry.id] = preview
        return preview
    }
}

// MARK: - Detail ViewModel

/// ViewModel para la vista de detalle y edición de una captura offsite.
@MainActor
@Observable
final class OffsiteCaptureDetailViewModel {
    // MARK: - Published State
    var image: UIImage?
    var data: OffsiteCaptureData?
    var unit: MeasurementUnit = .meters
    var isEditMode: Bool = false
    var editTool: EditTool = .none
    var pendingMeasurementNormalizedPoint: NormalizedPoint?
    var showTextInput: Bool = false
    var pendingTextNormalizedPoint: NormalizedPoint?
    var newTextContent: String = ""

    // MARK: - Selection & Drag State
    var selectedItem: SelectableItemType?
    var isDragging: Bool = false
    var dragStartNormalized: NormalizedPoint?
    var originalDataSnapshot: OffsiteCaptureData?

    // MARK: - Undo/Redo
    private(set) var undoStack: [OffsiteCaptureData] = []
    private(set) var redoStack: [OffsiteCaptureData] = []
    private let maxUndoLevels = 20

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    let entry: OffsiteCaptureEntry

    // MARK: - Dependencies
    private let storageService: StorageServiceProtocol
    private let hapticService: HapticServiceProtocol
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lidar", category: "OffsiteDetailVM")

    // MARK: - Depth Map Cache
    private var cachedDepthMapData: Data?
    private var isDepthMapLoaded = false

    enum EditTool: Equatable {
        case none, select, measure, frame, text, placeFrame
    }

    init(
        entry: OffsiteCaptureEntry,
        storageService: StorageServiceProtocol = StorageService.shared,
        hapticService: HapticServiceProtocol = HapticService.shared
    ) {
        self.entry = entry
        self.storageService = storageService
        self.hapticService = hapticService
    }

    // MARK: - Load

    func loadContent() {
        image = UIImage(contentsOfFile: entry.imageURL.path)
        data = storageService.loadCaptureData(from: entry.jsonURL)

        // Sync: si top-level vacío pero snapshot tiene datos, copiar del snapshot
        if var d = data, let snapshot = d.sceneSnapshot {
            var changed = false
            if d.measurements.isEmpty && !snapshot.measurements.isEmpty {
                d.measurements = snapshot.measurements
                changed = true
            }
            if d.frames.isEmpty && !snapshot.frames.isEmpty {
                d.frames = snapshot.frames
                changed = true
            }
            if d.textAnnotations.isEmpty && !snapshot.textAnnotations.isEmpty {
                d.textAnnotations = snapshot.textAnnotations
                changed = true
            }
            if changed { data = d }
        }

        logger.info("Contenido cargado para: \(self.entry.id)")
    }

    // MARK: - Edit Actions

    func handleEditTap(at location: CGPoint, viewSize: CGSize, imageSize: CGSize) {
        guard data != nil else { return }

        let scale = scaleToFit(imageSize: imageSize, in: viewSize)
        let offset = offsetToCenter(imageSize: imageSize, in: viewSize, scale: scale)

        let normalizedX = (location.x - offset.x) / (imageSize.width * scale)
        let normalizedY = (location.y - offset.y) / (imageSize.height * scale)

        guard (0...1).contains(normalizedX), (0...1).contains(normalizedY) else { return }

        let normalizedPoint = NormalizedPoint(x: normalizedX, y: normalizedY)

        switch editTool {
        case .select:
            let hit = hitTest(at: location, viewSize: viewSize, imageSize: imageSize)
            if selectedItem == hit {
                selectedItem = nil
            } else {
                selectedItem = hit
            }
            if hit != nil {
                hapticService.impact(style: .medium)
            }
        case .measure:
            handleMeasureTap(point: normalizedPoint, imageSize: imageSize, viewSize: viewSize)
        case .frame:
            handleFrameTap(point: normalizedPoint)
        case .text:
            pendingTextNormalizedPoint = normalizedPoint
            showTextInput = true
        case .placeFrame:
            handlePlaceFrameOnWall(point: normalizedPoint)
        case .none:
            break
        }
    }

    func addTextAnnotation() {
        guard let point = pendingTextNormalizedPoint,
              !newTextContent.isEmpty,
              var currentData = data else { return }

        pushUndoState()
        let annotation = OffsiteTextAnnotation(position: point, text: newTextContent)
        currentData.textAnnotations.append(annotation)
        data = currentData
        resetTextInput()
        hapticService.notification(type: .success)
    }

    func deleteMeasurement(id: UUID) {
        pushUndoState()
        data?.measurements.removeAll { $0.id == id }
        hapticService.impact(style: .light)
    }

    func deleteFrame(id: UUID) {
        pushUndoState()
        data?.frames.removeAll { $0.id == id }
        hapticService.impact(style: .light)
    }

    func deleteTextAnnotation(id: UUID) {
        pushUndoState()
        data?.textAnnotations.removeAll { $0.id == id }
        hapticService.impact(style: .light)
    }

    func toggleEditTool(_ tool: EditTool) {
        editTool = editTool == tool ? .none : tool
        selectedItem = nil
        resetPendingState()
        hapticService.impact(style: .medium)
    }

    // MARK: - Edit Mode Lifecycle

    func enterEditMode() {
        originalDataSnapshot = data
        isEditMode = true
        editTool = .select
        selectedItem = nil
        isDragging = false
        undoStack.removeAll()
        redoStack.removeAll()
    }

    // MARK: - Undo/Redo

    /// Guarda el estado actual en el stack de undo antes de una mutacion.
    func pushUndoState() {
        guard let currentData = data else { return }
        undoStack.append(currentData)
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        if let current = data {
            redoStack.append(current)
        }
        data = previous
        selectedItem = nil
        hapticService.impact(style: .light)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        if let current = data {
            undoStack.append(current)
        }
        data = next
        selectedItem = nil
        hapticService.impact(style: .light)
    }

    // MARK: - Hit Testing

    /// Hit test en coordenadas de pantalla para encontrar el elemento más cercano al toque.
    func hitTest(at location: CGPoint, viewSize: CGSize, imageSize: CGSize) -> SelectableItemType? {
        guard let currentData = data else { return nil }

        let scale = scaleToFit(imageSize: imageSize, in: viewSize)
        let offset = offsetToCenter(imageSize: imageSize, in: viewSize, scale: scale)
        let endpointRadius = AppConstants.OffsiteEditor.endpointHitTestRadius
        let hitRadius = AppConstants.OffsiteEditor.hitTestRadius

        // Prioridad 1: Endpoints de medición + handle de rotación
        for m in currentData.measurements {
            let pA = CGPoint(
                x: m.pointA.x * imageSize.width * scale + offset.x,
                y: m.pointA.y * imageSize.height * scale + offset.y
            )
            if distance(location, pA) <= endpointRadius {
                return .measurementEndpointA(m.id)
            }
            let pB = CGPoint(
                x: m.pointB.x * imageSize.width * scale + offset.x,
                y: m.pointB.y * imageSize.height * scale + offset.y
            )
            if distance(location, pB) <= endpointRadius {
                return .measurementEndpointB(m.id)
            }
            // Handle de rotación: perpendicular al midpoint (solo si seleccionada)
            if let sel = selectedItem, sel.itemId == m.id {
                let mid = CGPoint(x: (pA.x + pB.x) / 2, y: (pA.y + pB.y) / 2)
                let dx = pB.x - pA.x
                let dy = pB.y - pA.y
                let len = hypot(dx, dy)
                guard len > 1 else { continue }
                let perpX = -dy / len * 30  // 30pt perpendicular
                let perpY = dx / len * 30
                let rotateHandle = CGPoint(x: mid.x + perpX, y: mid.y + perpY)
                if distance(location, rotateHandle) <= endpointRadius {
                    return .measurementRotate(m.id)
                }
            }
        }

        // Prioridad 2: Anotaciones de texto
        for ann in currentData.textAnnotations {
            let pos = CGPoint(
                x: ann.position.x * imageSize.width * scale + offset.x,
                y: ann.position.y * imageSize.height * scale + offset.y
            )
            if distance(location, pos) <= hitRadius {
                return .textAnnotation(ann.id)
            }
        }

        // Prioridad 3: Resize handles de cuadros (esquina inferior derecha)
        for frame in currentData.frames {
            let brx = (frame.topLeft.x + frame.width) * imageSize.width * scale + offset.x
            let bry = (frame.topLeft.y + frame.height) * imageSize.height * scale + offset.y
            if distance(location, CGPoint(x: brx, y: bry)) <= endpointRadius {
                return .frameResizeBottomRight(frame.id)
            }
        }

        // Prioridad 4: Cuadros standard (test de area)
        for frame in currentData.frames {
            let x = frame.topLeft.x * imageSize.width * scale + offset.x
            let y = frame.topLeft.y * imageSize.height * scale + offset.y
            let w = frame.width * imageSize.width * scale
            let h = frame.height * imageSize.height * scale
            let rect = CGRect(x: x, y: y, width: w, height: h)
            if rect.contains(location) {
                return .frame(frame.id)
            }
        }

        // Prioridad 4: Cuadros perspectiva
        if let snapshot = currentData.sceneSnapshot {
            for pf in snapshot.perspectiveFrames {
                let corners = pf.corners2D.compactMap { pt -> CGPoint? in
                    guard pt.count >= 2 else { return nil }
                    return CGPoint(
                        x: pt[0] * imageSize.width * scale + offset.x,
                        y: pt[1] * imageSize.height * scale + offset.y
                    )
                }
                if pointInPolygon(location, vertices: corners) {
                    return .perspectiveFrame(pf.id)
                }
            }
        }

        // Prioridad 5: Líneas de medición (distancia al segmento)
        for m in currentData.measurements {
            let pA = CGPoint(
                x: m.pointA.x * imageSize.width * scale + offset.x,
                y: m.pointA.y * imageSize.height * scale + offset.y
            )
            let pB = CGPoint(
                x: m.pointB.x * imageSize.width * scale + offset.x,
                y: m.pointB.y * imageSize.height * scale + offset.y
            )
            if distanceToSegment(point: location, segA: pA, segB: pB) <= hitRadius {
                return .measurement(m.id)
            }
        }

        return nil
    }

    // MARK: - Drag Handling

    func handleDragStart(at location: CGPoint, viewSize: CGSize, imageSize: CGSize) {
        guard let item = selectedItem else { return }
        let scale = scaleToFit(imageSize: imageSize, in: viewSize)
        let offset = offsetToCenter(imageSize: imageSize, in: viewSize, scale: scale)
        let normalizedX = (location.x - offset.x) / (imageSize.width * scale)
        let normalizedY = (location.y - offset.y) / (imageSize.height * scale)
        dragStartNormalized = NormalizedPoint(x: normalizedX, y: normalizedY)
        isDragging = true
        pushUndoState()

        // Verificar proximidad al item seleccionado (relajado para mejor UX)
        let hitItem = hitTest(at: location, viewSize: viewSize, imageSize: imageSize)
        if hitItem?.itemId != item.itemId {
            // Si no coincide con hit test estricto, verificar distancia razonable al item
            let itemCenter = centerOfItem(item, imageSize: imageSize, scale: scale, offset: offset)
            if let center = itemCenter, distance(location, center) < AppConstants.OffsiteEditor.relaxedDragRadius {
                // Permitir drag - el item ya estaba seleccionado y estamos cerca
            } else {
                isDragging = false
                dragStartNormalized = nil
            }
        }
    }

    func handleDragChanged(to location: CGPoint, viewSize: CGSize, imageSize: CGSize) {
        guard isDragging, let startNorm = dragStartNormalized, var currentData = data else { return }

        let scale = scaleToFit(imageSize: imageSize, in: viewSize)
        let offset = offsetToCenter(imageSize: imageSize, in: viewSize, scale: scale)
        let currentNormX = (location.x - offset.x) / (imageSize.width * scale)
        let currentNormY = (location.y - offset.y) / (imageSize.height * scale)

        let dx = currentNormX - startNorm.x
        let dy = currentNormY - startNorm.y

        guard let item = selectedItem else { return }

        switch item {
        case .measurementEndpointA(let id):
            guard let idx = currentData.measurements.firstIndex(where: { $0.id == id }) else { return }
            var m = currentData.measurements[idx]
            let newX = clamp(m.pointA.x + dx, 0, 1)
            let newY = clamp(m.pointA.y + dy, 0, 1)
            m.pointA = NormalizedPoint(x: newX, y: newY)
            m.distanceMeters = recalculateDistance(pointA: m.pointA, pointB: m.pointB, data: currentData, imageSize: imageSize, viewSize: viewSize)
            currentData.measurements[idx] = m

        case .measurementEndpointB(let id):
            guard let idx = currentData.measurements.firstIndex(where: { $0.id == id }) else { return }
            var m = currentData.measurements[idx]
            let newX = clamp(m.pointB.x + dx, 0, 1)
            let newY = clamp(m.pointB.y + dy, 0, 1)
            m.pointB = NormalizedPoint(x: newX, y: newY)
            m.distanceMeters = recalculateDistance(pointA: m.pointA, pointB: m.pointB, data: currentData, imageSize: imageSize, viewSize: viewSize)
            currentData.measurements[idx] = m

        case .measurement(let id):
            guard let idx = currentData.measurements.firstIndex(where: { $0.id == id }) else { return }
            var m = currentData.measurements[idx]
            let newAx = clamp(m.pointA.x + dx, 0, 1)
            let newAy = clamp(m.pointA.y + dy, 0, 1)
            let newBx = clamp(m.pointB.x + dx, 0, 1)
            let newBy = clamp(m.pointB.y + dy, 0, 1)
            m.pointA = NormalizedPoint(x: newAx, y: newAy)
            m.pointB = NormalizedPoint(x: newBx, y: newBy)
            // No recalcular: mover la medición entera preserva la distancia original
            currentData.measurements[idx] = m

        case .measurementRotate(let id):
            guard let idx = currentData.measurements.firstIndex(where: { $0.id == id }) else { return }
            var m = currentData.measurements[idx]
            // Rotar endpoints alrededor del midpoint
            let midX = (m.pointA.x + m.pointB.x) / 2
            let midY = (m.pointA.y + m.pointB.y) / 2
            let halfDx = m.pointB.x - midX
            let halfDy = m.pointB.y - midY
            // Calcular ángulo de rotación desde el desplazamiento del drag
            let angle = Double(dx) * .pi  // Sensibilidad: mover toda la imagen = 180°
            let cosA = cos(angle)
            let sinA = sin(angle)
            let newHalfDx = halfDx * cosA - halfDy * sinA
            let newHalfDy = halfDx * sinA + halfDy * cosA
            m.pointA = NormalizedPoint(x: clamp(midX - newHalfDx, 0, 1), y: clamp(midY - newHalfDy, 0, 1))
            m.pointB = NormalizedPoint(x: clamp(midX + newHalfDx, 0, 1), y: clamp(midY + newHalfDy, 0, 1))
            // No recalcular: rotar preserva la longitud de la medición
            currentData.measurements[idx] = m

        case .frame(let id):
            guard let idx = currentData.frames.firstIndex(where: { $0.id == id }) else { return }
            var f = currentData.frames[idx]
            let newX = clamp(f.topLeft.x + dx, 0, 1 - f.width)
            let newY = clamp(f.topLeft.y + dy, 0, 1 - f.height)
            f.topLeft = NormalizedPoint(x: newX, y: newY)
            currentData.frames[idx] = f

        case .frameResizeBottomRight(let id):
            guard let idx = currentData.frames.firstIndex(where: { $0.id == id }) else { return }
            var f = currentData.frames[idx]
            let newW = clamp(f.width + dx, AppConstants.OffsiteEditor.minFrameSize, AppConstants.OffsiteEditor.maxFrameSize)
            let newH = clamp(f.height + dy, AppConstants.OffsiteEditor.minFrameSize, AppConstants.OffsiteEditor.maxFrameSize)
            f.width = newW
            f.height = newH
            currentData.frames[idx] = f

        case .perspectiveFrame(let id):
            guard var snapshot = currentData.sceneSnapshot,
                  let idx = snapshot.perspectiveFrames.firstIndex(where: { $0.id == id }) else { return }
            var pf = snapshot.perspectiveFrames[idx]
            // Calcular offset ajustado: si algún corner se sale de [0,1], reducir el offset
            var adjDx = dx
            var adjDy = dy
            for corner in pf.corners2D {
                guard corner.count >= 2 else { continue }
                let newX = corner[0] + adjDx
                let newY = corner[1] + adjDy
                if newX < 0 { adjDx -= newX }
                if newX > 1 { adjDx -= (newX - 1) }
                if newY < 0 { adjDy -= newY }
                if newY > 1 { adjDy -= (newY - 1) }
            }
            pf.center2D = NormalizedPoint(x: pf.center2D.x + adjDx, y: pf.center2D.y + adjDy)
            pf.corners2D = pf.corners2D.map { corner in
                guard corner.count >= 2 else { return corner }
                return [corner[0] + adjDx, corner[1] + adjDy]
            }
            snapshot.perspectiveFrames[idx] = pf
            currentData.sceneSnapshot = snapshot

        case .textAnnotation(let id):
            guard let idx = currentData.textAnnotations.firstIndex(where: { $0.id == id }) else { return }
            var ann = currentData.textAnnotations[idx]
            let newX = clamp(ann.position.x + dx, 0, 1)
            let newY = clamp(ann.position.y + dy, 0, 1)
            ann.position = NormalizedPoint(x: newX, y: newY)
            currentData.textAnnotations[idx] = ann
        }

        data = currentData
        dragStartNormalized = NormalizedPoint(x: currentNormX, y: currentNormY)
    }

    func handleDragEnded() {
        isDragging = false
        dragStartNormalized = nil
        hapticService.impact(style: .light)
    }

    // MARK: - Delete Selected

    func deleteSelectedItem() {
        guard let item = selectedItem else { return }

        switch item {
        case .measurement(let id), .measurementEndpointA(let id), .measurementEndpointB(let id), .measurementRotate(let id):
            deleteMeasurement(id: id)
        case .frame(let id), .frameResizeBottomRight(let id):
            deleteFrame(id: id)
        case .perspectiveFrame(let id):
            deletePerspectiveFrame(id: id)
        case .textAnnotation(let id):
            deleteTextAnnotation(id: id)
        }

        selectedItem = nil
    }

    /// Duplica la medición seleccionada con un pequeño offset.
    func duplicateSelectedMeasurement() {
        guard let item = selectedItem, var currentData = data else { return }
        let id: UUID
        switch item {
        case .measurement(let i), .measurementEndpointA(let i), .measurementEndpointB(let i), .measurementRotate(let i):
            id = i
        default: return
        }
        guard let m = currentData.measurements.first(where: { $0.id == id }) else { return }
        pushUndoState()
        let offset = 0.03  // Pequeño desplazamiento visual
        let copy = OffsiteMeasurement(
            distanceMeters: m.distanceMeters,
            pointA: NormalizedPoint(x: clamp(m.pointA.x + offset, 0, 1), y: clamp(m.pointA.y + offset, 0, 1)),
            pointB: NormalizedPoint(x: clamp(m.pointB.x + offset, 0, 1), y: clamp(m.pointB.y + offset, 0, 1)),
            isFromAR: false  // La copia es offsite, ya no es AR
        )
        currentData.measurements.append(copy)
        data = currentData
        selectedItem = .measurement(copy.id)
        hapticService.impact(style: .medium)
    }

    func deletePerspectiveFrame(id: UUID) {
        pushUndoState()
        guard var currentData = data, var snapshot = currentData.sceneSnapshot else { return }
        snapshot.perspectiveFrames.removeAll { $0.id == id }
        currentData.sceneSnapshot = snapshot
        data = currentData
        hapticService.impact(style: .light)
    }

    // MARK: - Frame Image

    func updateFrameImage(id: UUID, image: UIImage) {
        pushUndoState()
        let downsized = downscaleImage(image, maxDimension: AppConstants.OffsiteEditor.framePhotoMaxDimension)

        // Intentar guardar como archivo separado
        let filename: String? = {
            do {
                return try storageService.saveFrameImage(downsized, captureId: entry.id, frameId: id)
            } catch {
                logger.warning("No se pudo guardar imagen como archivo, usando base64: \(error.localizedDescription)")
                return nil
            }
        }()

        // Intentar en cuadros standard
        if var currentData = data, let idx = currentData.frames.firstIndex(where: { $0.id == id }) {
            if let filename {
                currentData.frames[idx].imageFilename = filename
                currentData.frames[idx].imageBase64 = nil
            } else {
                guard let jpegData = downsized.jpegData(compressionQuality: AppConstants.OffsiteEditor.framePhotoJPEGQuality) else { return }
                currentData.frames[idx].imageBase64 = jpegData.base64EncodedString()
            }
            data = currentData
            hapticService.notification(type: .success)
            return
        }

        // Intentar en cuadros perspectiva
        if var currentData = data, var snapshot = currentData.sceneSnapshot,
           let idx = snapshot.perspectiveFrames.firstIndex(where: { $0.id == id }) {
            if let filename {
                snapshot.perspectiveFrames[idx].imageFilename = filename
                snapshot.perspectiveFrames[idx].imageBase64 = nil
            } else {
                guard let jpegData = downsized.jpegData(compressionQuality: AppConstants.OffsiteEditor.framePhotoJPEGQuality) else { return }
                snapshot.perspectiveFrames[idx].imageBase64 = jpegData.base64EncodedString()
            }
            currentData.sceneSnapshot = snapshot
            data = currentData
            hapticService.notification(type: .success)
        }
    }

    // MARK: - Color Update

    func updateItemColor(_ hexColor: String) {
        guard let item = selectedItem, var currentData = data else { return }
        pushUndoState()

        switch item {
        case .frame(let id), .frameResizeBottomRight(let id):
            if let idx = currentData.frames.firstIndex(where: { $0.id == id }) {
                currentData.frames[idx].color = hexColor
            }
        case .perspectiveFrame(let id):
            if var snapshot = currentData.sceneSnapshot,
               let idx = snapshot.perspectiveFrames.firstIndex(where: { $0.id == id }) {
                snapshot.perspectiveFrames[idx].color = hexColor
                currentData.sceneSnapshot = snapshot
            }
        case .textAnnotation(let id):
            if let idx = currentData.textAnnotations.firstIndex(where: { $0.id == id }) {
                currentData.textAnnotations[idx].color = hexColor
            }
        default:
            return
        }

        data = currentData
        hapticService.impact(style: .light)
    }

    /// Si el item seleccionado soporta cambio de color.
    var selectedItemSupportsColor: Bool {
        guard let item = selectedItem else { return false }
        switch item {
        case .frame, .frameResizeBottomRight, .perspectiveFrame, .textAnnotation: return true
        default: return false
        }
    }

    /// Color actual del item seleccionado (hex string).
    var selectedItemColor: String? {
        guard let item = selectedItem, let currentData = data else { return nil }
        switch item {
        case .frame(let id), .frameResizeBottomRight(let id):
            return currentData.frames.first(where: { $0.id == id })?.color
        case .perspectiveFrame(let id):
            return currentData.sceneSnapshot?.perspectiveFrames.first(where: { $0.id == id })?.color
        case .textAnnotation(let id):
            return currentData.textAnnotations.first(where: { $0.id == id })?.color
        default:
            return nil
        }
    }

    // MARK: - Image Rendering

    /// Renderiza la imagen original con todos los overlays (mediciones, cuadros, texto) usando Core Graphics.
    func renderImageWithOverlays() -> UIImage? {
        guard let baseImage = image, let currentData = data else { return nil }
        let imgSize = baseImage.size

        let renderer = UIGraphicsImageRenderer(size: imgSize)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // 1. Dibujar imagen base
            baseImage.draw(at: .zero)

            // 2. Dibujar mediciones
            for m in currentData.measurements {
                let pA = CGPoint(x: m.pointA.x * imgSize.width, y: m.pointA.y * imgSize.height)
                let pB = CGPoint(x: m.pointB.x * imgSize.width, y: m.pointB.y * imgSize.height)
                let color = m.isFromAR ? UIColor.cyan : UIColor.orange

                // Línea
                cgCtx.setStrokeColor(color.cgColor)
                cgCtx.setLineWidth(3.0)
                cgCtx.move(to: pA)
                cgCtx.addLine(to: pB)
                cgCtx.strokePath()

                // Endpoints
                let endpointRadius: CGFloat = 8
                for p in [pA, pB] {
                    cgCtx.setFillColor(color.cgColor)
                    cgCtx.fillEllipse(in: CGRect(x: p.x - endpointRadius, y: p.y - endpointRadius, width: endpointRadius * 2, height: endpointRadius * 2))
                    cgCtx.setStrokeColor(UIColor.white.cgColor)
                    cgCtx.setLineWidth(1.5)
                    cgCtx.strokeEllipse(in: CGRect(x: p.x - endpointRadius, y: p.y - endpointRadius, width: endpointRadius * 2, height: endpointRadius * 2))
                }

                // Etiqueta de distancia
                let midPoint = CGPoint(x: (pA.x + pB.x) / 2, y: (pA.y + pB.y) / 2)
                let label = String(format: "%.2f m", m.distanceMeters)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: UIColor.white
                ]
                let labelSize = (label as NSString).size(withAttributes: attrs)
                let labelRect = CGRect(
                    x: midPoint.x - labelSize.width / 2 - 4,
                    y: midPoint.y - labelSize.height / 2 - 2,
                    width: labelSize.width + 8,
                    height: labelSize.height + 4
                )
                cgCtx.setFillColor(color.withAlphaComponent(0.85).cgColor)
                let labelPath = UIBezierPath(roundedRect: labelRect, cornerRadius: 4)
                cgCtx.addPath(labelPath.cgPath)
                cgCtx.fillPath()
                (label as NSString).draw(
                    at: CGPoint(x: labelRect.origin.x + 4, y: labelRect.origin.y + 2),
                    withAttributes: attrs
                )
            }

            // 3. Dibujar cuadros standard
            for frame in currentData.frames {
                let x = frame.topLeft.x * imgSize.width
                let y = frame.topLeft.y * imgSize.height
                let w = frame.width * imgSize.width
                let h = frame.height * imgSize.height
                let frameRect = CGRect(x: x, y: y, width: w, height: h)
                let frameColor = Self.uiColor(fromHex: frame.color)

                // Imagen del cuadro si tiene
                if let frameImg = self.loadFrameImage(filename: frame.imageFilename, base64: frame.imageBase64) {
                    frameImg.draw(in: frameRect)
                }

                // Borde
                cgCtx.setStrokeColor(frameColor.cgColor)
                cgCtx.setLineWidth(3.0)
                cgCtx.stroke(frameRect)

                // Label
                if let label = frame.label {
                    let labelText: String
                    if let wm = frame.widthMeters, let hm = frame.heightMeters {
                        labelText = "\(label) (\(String(format: "%.2f×%.2f m", wm, hm)))"
                    } else {
                        labelText = label
                    }
                    self.drawLabel(labelText, at: CGPoint(x: x + w / 2, y: y - 6), color: frameColor, in: cgCtx)
                }
            }

            // 4. Dibujar cuadros perspectiva
            if let perspectiveFrames = currentData.sceneSnapshot?.perspectiveFrames {
                for pf in perspectiveFrames {
                    let corners = pf.corners2D.compactMap { pt -> CGPoint? in
                        guard pt.count >= 2 else { return nil }
                        return CGPoint(x: pt[0] * imgSize.width, y: pt[1] * imgSize.height)
                    }
                    guard corners.count >= 3 else { continue }
                    let pfColor = Self.uiColor(fromHex: pf.color)

                    // Imagen del cuadro si tiene
                    if let pfImg = self.loadFrameImage(filename: pf.imageFilename, base64: pf.imageBase64) {
                        cgCtx.saveGState()
                        let path = UIBezierPath()
                        path.move(to: corners[0])
                        for i in 1..<corners.count { path.addLine(to: corners[i]) }
                        path.close()
                        path.addClip()
                        let boundingBox = path.bounds
                        pfImg.draw(in: boundingBox)
                        cgCtx.restoreGState()
                    }

                    // Polígono borde
                    cgCtx.setStrokeColor(pfColor.cgColor)
                    cgCtx.setLineWidth(3.0)
                    cgCtx.move(to: corners[0])
                    for i in 1..<corners.count { cgCtx.addLine(to: corners[i]) }
                    cgCtx.closePath()
                    cgCtx.strokePath()

                    // Label
                    if let label = pf.label {
                        let center = CGPoint(x: pf.center2D.x * imgSize.width, y: pf.center2D.y * imgSize.height)
                        self.drawLabel(label, at: CGPoint(x: center.x, y: corners.map(\.y).min()! - 6), color: pfColor, in: cgCtx)
                    }
                }
            }

            // 5. Dibujar texto annotations
            for ann in currentData.textAnnotations {
                let pos = CGPoint(x: ann.position.x * imgSize.width, y: ann.position.y * imgSize.height)
                let annColor = Self.uiColor(fromHex: ann.color)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                    .foregroundColor: annColor
                ]
                let textSize = (ann.text as NSString).size(withAttributes: attrs)
                let bgRect = CGRect(
                    x: pos.x - textSize.width / 2 - 6,
                    y: pos.y - textSize.height / 2 - 3,
                    width: textSize.width + 12,
                    height: textSize.height + 6
                )
                cgCtx.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)
                let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: 6)
                cgCtx.addPath(bgPath.cgPath)
                cgCtx.fillPath()
                (ann.text as NSString).draw(
                    at: CGPoint(x: bgRect.origin.x + 6, y: bgRect.origin.y + 3),
                    withAttributes: attrs
                )
            }
        }
    }

    /// Dibuja un label centrado horizontalmente sobre un punto.
    private func drawLabel(_ text: String, at point: CGPoint, color: UIColor, in cgCtx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = CGRect(
            x: point.x - size.width / 2 - 4,
            y: point.y - size.height - 2,
            width: size.width + 8,
            height: size.height + 4
        )
        cgCtx.setFillColor(color.withAlphaComponent(0.9).cgColor)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
        cgCtx.addPath(path.cgPath)
        cgCtx.fillPath()
        (text as NSString).draw(at: CGPoint(x: rect.origin.x + 4, y: rect.origin.y + 2), withAttributes: attrs)
    }

    /// Convierte un string hex a UIColor para renderizado Core Graphics.
    private static func uiColor(fromHex hex: String) -> UIColor {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: CGFloat
        if hex.count == 6 {
            r = CGFloat((int >> 16) & 0xFF) / 255
            g = CGFloat((int >> 8) & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
        } else {
            r = 0; g = 0; b = 0
        }
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    // MARK: - Sharing

    /// Renderiza la imagen con overlays a un archivo temporal para compartir.
    func renderedImageForSharing() -> URL? {
        guard let rendered = renderImageWithOverlays(),
              let jpegData = rendered.jpegData(compressionQuality: AppConstants.Capture.jpegQuality) else {
            return nil
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share_\(entry.id).jpg")
        do {
            try jpegData.write(to: tempURL)
            return tempURL
        } catch {
            logger.error("Error creando imagen temporal para compartir: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Improved Save & Cancel

    func saveChanges() {
        guard var currentData = data else { return }
        currentData.lastModified = Date()

        // Sincronizar snapshot con datos top-level
        if var snapshot = currentData.sceneSnapshot {
            snapshot.measurements = currentData.measurements
            snapshot.frames = currentData.frames
            snapshot.textAnnotations = currentData.textAnnotations
            snapshot.lastModified = Date()
            currentData.sceneSnapshot = snapshot
        }

        do {
            try storageService.saveCaptureData(currentData, to: entry.jsonURL)
        } catch {
            logger.error("Error guardando JSON: \(error.localizedDescription)")
            hapticService.notification(type: .error)
            return
        }

        // Actualizar thumbnail (no crítico — si falla, el JSON ya está guardado)
        if let rendered = renderImageWithOverlays() {
            try? storageService.updateCaptureThumbnail(rendered, for: entry)
        }

        data = currentData
        originalDataSnapshot = currentData
        undoStack.removeAll()
        redoStack.removeAll()
        hapticService.notification(type: .success)
        exitEditMode()
        logger.info("Cambios guardados")
    }

    func cancelEdit() {
        if let snapshot = originalDataSnapshot {
            data = snapshot
        } else {
            data = storageService.loadCaptureData(from: entry.jsonURL)
        }
        exitEditMode()
    }

    /// Nombre descriptivo del item seleccionado para la barra de acciones.
    var selectedItemName: String? {
        guard let item = selectedItem, let currentData = data else { return nil }
        switch item {
        case .measurement(let id), .measurementEndpointA(let id), .measurementEndpointB(let id), .measurementRotate(let id):
            return currentData.measurements.first(where: { $0.id == id }).map { m in
                "Medición (\(String(format: "%.2f m", m.distanceMeters)))"
            }
        case .frame(let id), .frameResizeBottomRight(let id):
            return currentData.frames.first(where: { $0.id == id })?.label ?? "Cuadro"
        case .perspectiveFrame(let id):
            return currentData.sceneSnapshot?.perspectiveFrames.first(where: { $0.id == id })?.label ?? "Cuadro 3D"
        case .textAnnotation(let id):
            return currentData.textAnnotations.first(where: { $0.id == id })?.text ?? "Texto"
        }
    }

    /// Icono del item seleccionado.
    var selectedItemIcon: String {
        guard let item = selectedItem else { return "" }
        switch item {
        case .measurement, .measurementEndpointA, .measurementEndpointB, .measurementRotate: return "ruler"
        case .frame, .frameResizeBottomRight: return "rectangle.dashed"
        case .perspectiveFrame: return "cube"
        case .textAnnotation: return "text.bubble"
        }
    }

    /// Si el item seleccionado es un cuadro (standard o perspectiva).
    var selectedItemIsFrame: Bool {
        guard let item = selectedItem else { return false }
        switch item {
        case .frame, .frameResizeBottomRight, .perspectiveFrame: return true
        default: return false
        }
    }

    var selectedItemIsMeasurement: Bool {
        guard let item = selectedItem else { return false }
        switch item {
        case .measurement, .measurementEndpointA, .measurementEndpointB, .measurementRotate: return true
        default: return false
        }
    }

    /// ID del cuadro seleccionado (standard o perspectiva).
    var selectedFrameId: UUID? {
        guard let item = selectedItem else { return nil }
        switch item {
        case .frame(let id), .frameResizeBottomRight(let id), .perspectiveFrame(let id): return id
        default: return nil
        }
    }

    // MARK: - Geometry Helpers

    /// Devuelve el centro en coordenadas de pantalla del item seleccionado.
    private func centerOfItem(_ item: SelectableItemType, imageSize: CGSize, scale: CGFloat, offset: CGPoint) -> CGPoint? {
        guard let currentData = data else { return nil }
        switch item {
        case .measurement(let id), .measurementEndpointA(let id), .measurementEndpointB(let id), .measurementRotate(let id):
            guard let m = currentData.measurements.first(where: { $0.id == id }) else { return nil }
            let cx = ((m.pointA.x + m.pointB.x) / 2) * imageSize.width * scale + offset.x
            let cy = ((m.pointA.y + m.pointB.y) / 2) * imageSize.height * scale + offset.y
            return CGPoint(x: cx, y: cy)
        case .frame(let id), .frameResizeBottomRight(let id):
            guard let f = currentData.frames.first(where: { $0.id == id }) else { return nil }
            let cx = (f.topLeft.x + f.width / 2) * imageSize.width * scale + offset.x
            let cy = (f.topLeft.y + f.height / 2) * imageSize.height * scale + offset.y
            return CGPoint(x: cx, y: cy)
        case .perspectiveFrame(let id):
            guard let pf = currentData.sceneSnapshot?.perspectiveFrames.first(where: { $0.id == id }) else { return nil }
            let cx = pf.center2D.x * imageSize.width * scale + offset.x
            let cy = pf.center2D.y * imageSize.height * scale + offset.y
            return CGPoint(x: cx, y: cy)
        case .textAnnotation(let id):
            guard let ann = currentData.textAnnotations.first(where: { $0.id == id }) else { return nil }
            let cx = ann.position.x * imageSize.width * scale + offset.x
            let cy = ann.position.y * imageSize.height * scale + offset.y
            return CGPoint(x: cx, y: cy)
        }
    }

    func scaleToFit(imageSize: CGSize, in viewSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
    }

    func offsetToCenter(imageSize: CGSize, in viewSize: CGSize, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: (viewSize.width - imageSize.width * scale) / 2,
            y: (viewSize.height - imageSize.height * scale) / 2
        )
    }

    // MARK: - Private

    private func handleMeasureTap(point: NormalizedPoint, imageSize: CGSize, viewSize: CGSize) {
        guard var currentData = data else { return }

        if let firstNorm = pendingMeasurementNormalizedPoint {
            pushUndoState()
            let distance = recalculateDistance(pointA: firstNorm, pointB: point, data: currentData, imageSize: imageSize, viewSize: viewSize)
            let newMeasurement = OffsiteMeasurement(distanceMeters: distance, pointA: firstNorm, pointB: point, isFromAR: false)
            currentData.measurements.append(newMeasurement)
            data = currentData
            pendingMeasurementNormalizedPoint = nil
            hapticService.notification(type: .success)
        } else {
            pendingMeasurementNormalizedPoint = point
            hapticService.impact(style: .medium)
        }
    }

    private func handleFrameTap(point: NormalizedPoint) {
        guard var currentData = data else { return }
        pushUndoState()

        let newFrame = OffsiteFrame(
            topLeft: point,
            width: AppConstants.OffsiteEditor.defaultFrameSize,
            height: AppConstants.OffsiteEditor.defaultFrameSize,
            label: "Cuadro \(currentData.frames.count + 1)",
            color: AppConstants.OffsiteEditor.availableColors.randomElement() ?? "#3B82F6"
        )
        currentData.frames.append(newFrame)
        data = currentData
        hapticService.notification(type: .success)
    }

    private func handlePlaceFrameOnWall(point: NormalizedPoint) {
        guard var currentData = data,
              let snapshot = currentData.sceneSnapshot else {
            handleFrameTap(point: point)
            return
        }

        guard let plane = snapshot.planes.first(where: { planeContains(point: point, plane: $0) }) else {
            handleFrameTap(point: point)
            return
        }

        // Calcular vectores del plano en espacio 2D normalizado usando sus vertices proyectados
        let verts = plane.projectedVertices.compactMap { pt -> (Double, Double)? in
            guard pt.count >= 2 else { return nil }
            return (pt[0], pt[1])
        }

        let corners: [[Double]]
        let frameSize = Double(AppConstants.OffsiteEditor.defaultFrameSize)

        if verts.count >= 4 {
            // Usar los vertices del plano para calcular vectores H y V con perspectiva real
            // verts: TL(0), TR(1), BR(2), BL(3) - orden del plano proyectado
            let hx = verts[1].0 - verts[0].0
            let hy = verts[1].1 - verts[0].1
            let vx = verts[3].0 - verts[0].0
            let vy = verts[3].1 - verts[0].1

            let hLen = sqrt(hx * hx + hy * hy)
            let vLen = sqrt(vx * vx + vy * vy)
            guard hLen > 0.001, vLen > 0.001 else {
                handleFrameTap(point: point)
                return
            }

            // Vectores unitarios del plano en 2D normalizado
            let uhx = hx / hLen
            let uhy = hy / hLen
            let uvx = vx / vLen
            let uvy = vy / vLen

            // Escala: frameSize relativo al plano (fraccion del tamano del plano)
            let halfH = frameSize / 2 * hLen
            let halfV = frameSize / 2 * vLen

            corners = [
                [clamp(point.x - uhx * halfH + uvx * halfV, 0, 1),
                 clamp(point.y - uhy * halfH + uvy * halfV, 0, 1)],
                [clamp(point.x + uhx * halfH + uvx * halfV, 0, 1),
                 clamp(point.y + uhy * halfH + uvy * halfV, 0, 1)],
                [clamp(point.x + uhx * halfH - uvx * halfV, 0, 1),
                 clamp(point.y + uhy * halfH - uvy * halfV, 0, 1)],
                [clamp(point.x - uhx * halfH - uvx * halfV, 0, 1),
                 clamp(point.y - uhy * halfH - uvy * halfV, 0, 1)]
            ]
        } else {
            // Fallback: rectangulo axis-aligned
            let half = frameSize / 2
            corners = [
                [clamp(point.x - half, 0, 1), clamp(point.y - half, 0, 1)],
                [clamp(point.x + half, 0, 1), clamp(point.y - half, 0, 1)],
                [clamp(point.x + half, 0, 1), clamp(point.y + half, 0, 1)],
                [clamp(point.x - half, 0, 1), clamp(point.y + half, 0, 1)]
            ]
        }

        pushUndoState()
        let perspectiveFrame = OffsiteFramePerspective(
            planeId: plane.id,
            center2D: point,
            corners2D: corners,
            widthMeters: plane.widthMeters * frameSize,
            heightMeters: plane.heightMeters * frameSize,
            label: "Cuadro \((snapshot.perspectiveFrames.count) + 1)",
            color: AppConstants.OffsiteEditor.availableColors.randomElement() ?? "#3B82F6"
        )

        var updatedSnapshot = snapshot
        updatedSnapshot.perspectiveFrames.append(perspectiveFrame)
        currentData.sceneSnapshot = updatedSnapshot
        data = currentData
        hapticService.notification(type: .success)
        logger.info("Frame colocado en plano con perspectiva: \(plane.id)")
    }

    private func planeContains(point: NormalizedPoint, plane: OffsitePlaneData) -> Bool {
        let vertices = plane.projectedVertices
        guard vertices.count >= 3 else { return false }

        // Point-in-polygon (ray casting)
        var inside = false
        var j = vertices.count - 1
        for i in 0..<vertices.count {
            guard vertices[i].count >= 2, vertices[j].count >= 2 else { j = i; continue }
            let xi = vertices[i][0], yi = vertices[i][1]
            let xj = vertices[j][0], yj = vertices[j][1]
            if ((yi > point.y) != (yj > point.y)) &&
               (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private func exitEditMode() {
        isEditMode = false
        editTool = .none
        selectedItem = nil
        isDragging = false
        dragStartNormalized = nil
        resetPendingState()
    }

    private func resetPendingState() {
        pendingMeasurementNormalizedPoint = nil
        pendingTextNormalizedPoint = nil
    }

    private func resetTextInput() {
        newTextContent = ""
        pendingTextNormalizedPoint = nil
    }

    // MARK: - Geometry Utilities

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func distanceToSegment(point: CGPoint, segA: CGPoint, segB: CGPoint) -> CGFloat {
        let dx = segB.x - segA.x
        let dy = segB.y - segA.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else { return distance(point, segA) }

        var t = ((point.x - segA.x) * dx + (point.y - segA.y) * dy) / lengthSq
        t = max(0, min(1, t))
        let proj = CGPoint(x: segA.x + t * dx, y: segA.y + t * dy)
        return distance(point, proj)
    }

    private func pointInPolygon(_ point: CGPoint, vertices: [CGPoint]) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        var j = vertices.count - 1
        for i in 0..<vertices.count {
            let xi = vertices[i].x, yi = vertices[i].y
            let xj = vertices[j].x, yj = vertices[j].y
            if ((yi > point.y) != (yj > point.y)) &&
               (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        max(lo, min(hi, value))
    }

    // MARK: - Depth Map

    /// Carga el depth map desde disco si existe y no ha sido cargado aún.
    private func loadDepthMapIfNeeded() -> Data? {
        if isDepthMapLoaded { return cachedDepthMapData }
        isDepthMapLoaded = true
        guard let snapshot = data?.sceneSnapshot,
              let filename = snapshot.depthMapFilename,
              !filename.isEmpty else { return nil }
        cachedDepthMapData = storageService.loadDepthMap(captureId: entry.id, filename: filename)
        return cachedDepthMapData
    }

    /// Muestrea la profundidad en un punto normalizado (0-1) con interpolación bilineal.
    private func sampleDepth(at point: NormalizedPoint, depthData: Data, width: Int, height: Int) -> Float? {
        let expectedSize = width * height * MemoryLayout<Float>.size
        guard depthData.count >= expectedSize, width > 0, height > 0 else { return nil }

        // El depth map de ARKit está en landscape-left nativo.
        // Las coordenadas normalizadas están en portrait (orientación de la app).
        // Transformar: portrait (x,y) → landscape-left (lx, ly)
        // En landscape-left: lx = y_portrait, ly = 1 - x_portrait
        let lx = point.y
        let ly = 1.0 - point.x

        let fx = lx * Double(width - 1)
        let fy = ly * Double(height - 1)
        let x0 = Int(fx)
        let y0 = Int(fy)
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let dx = Float(fx - Double(x0))
        let dy = Float(fy - Double(y0))

        func valueAt(_ x: Int, _ y: Int) -> Float? {
            let offset = (y * width + x) * MemoryLayout<Float>.size
            guard offset + MemoryLayout<Float>.size <= depthData.count else { return nil }
            let value = depthData.withUnsafeBytes { ptr -> Float in
                ptr.load(fromByteOffset: offset, as: Float.self)
            }
            guard value.isFinite, value > 0 else { return nil }
            return value
        }

        guard let v00 = valueAt(x0, y0),
              let v10 = valueAt(x1, y0),
              let v01 = valueAt(x0, y1),
              let v11 = valueAt(x1, y1) else {
            // Fallback: sin interpolación, usar el más cercano válido
            return valueAt(x0, y0) ?? valueAt(x1, y0) ?? valueAt(x0, y1) ?? valueAt(x1, y1)
        }

        let top = v00 * (1 - dx) + v10 * dx
        let bottom = v01 * (1 - dx) + v11 * dx
        return top * (1 - dy) + bottom * dy
    }

    /// Calcula distancia 3D usando depth map y camera intrinsics (unproyección).
    /// Los intrínsecos de ARKit son para la resolución nativa de la cámara, pero las coordenadas
    /// normalizadas corresponden a la resolución de la vista capturada (imageWidth x imageHeight).
    /// Se escalan los intrínsecos proporcionalmente.
    private func calculateDepthAwareDistance(pointA: NormalizedPoint, pointB: NormalizedPoint, snapshot: OffsiteSceneSnapshot) -> Double? {
        guard let depthData = loadDepthMapIfNeeded(),
              let dmW = snapshot.depthMapWidth, dmW > 0,
              let dmH = snapshot.depthMapHeight, dmH > 0,
              let cam = snapshot.camera else { return nil }

        guard let depthA = sampleDepth(at: pointA, depthData: depthData, width: dmW, height: dmH),
              let depthB = sampleDepth(at: pointB, depthData: depthData, width: dmW, height: dmH) else { return nil }

        // Intrínsecos nativos de la cámara ARKit (orientación landscape-left)
        let intrinsics = cam.intrinsicsMatrix
        let nativeFx = intrinsics.columns.0.x  // focal x en landscape
        let nativeFy = intrinsics.columns.1.y  // focal y en landscape
        let nativeCx = intrinsics.columns.2.x  // centro óptico x en landscape
        let nativeCy = intrinsics.columns.2.y  // centro óptico y en landscape

        // imageWidth/Height está en portrait (imagen rotada .right desde landscape-left).
        // Rotación .right (90° CW): portrait_x = landscape_y, portrait_y = landscape_width - landscape_x
        // Intrínsecos en portrait: fx_p = fy_native, fy_p = fx_native, cx_p = cy_native, cy_p = cx_native
        let imgW = Float(cam.imageWidth)   // portrait width
        let imgH = Float(cam.imageHeight)  // portrait height

        // Resolución nativa landscape estimada desde centro óptico
        let estimatedNativeLandscapeW = 2 * nativeCx  // ancho landscape
        let estimatedNativeLandscapeH = 2 * nativeCy  // alto landscape
        guard estimatedNativeLandscapeW > 0, estimatedNativeLandscapeH > 0 else { return nil }

        // Portrait: width corresponde a landscape height, height a landscape width
        let scaleX = imgW / estimatedNativeLandscapeH   // portrait width / landscape height
        let scaleY = imgH / estimatedNativeLandscapeW   // portrait height / landscape width

        let fx = nativeFy * scaleX   // portrait fx = landscape fy, escalado a portrait width
        let fy = nativeFx * scaleY   // portrait fy = landscape fx, escalado a portrait height
        let cx = nativeCy * scaleX   // portrait cx = landscape cy, escalado
        let cy = nativeCx * scaleY   // portrait cy = landscape cx, escalado

        // Convertir coordenadas normalizadas a pixeles de la imagen portrait
        let pixA = SIMD2<Float>(Float(pointA.x) * imgW, Float(pointA.y) * imgH)
        let pixB = SIMD2<Float>(Float(pointB.x) * imgW, Float(pointB.y) * imgH)

        // Unproyectar: x3D = (pixelX - cx) * depth / fx
        let ptA = SIMD3<Float>(
            (pixA.x - cx) * depthA / fx,
            (pixA.y - cy) * depthA / fy,
            depthA
        )
        let ptB = SIMD3<Float>(
            (pixB.x - cx) * depthB / fx,
            (pixB.y - cy) * depthB / fy,
            depthB
        )

        let diff = ptB - ptA
        let distance = Double(sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z))
        guard distance.isFinite, distance > 0 else { return nil }
        return distance
    }

    /// Estima la distancia entre dos puntos (wrapper público para preview en tiempo real).
    func estimateDistance(pointA: NormalizedPoint, pointB: NormalizedPoint, imageSize: CGSize, viewSize: CGSize) -> Double? {
        guard let currentData = data else { return nil }
        return recalculateDistance(pointA: pointA, pointB: pointB, data: currentData, imageSize: imageSize, viewSize: viewSize)
    }

    /// Calcula distancia en metros entre dos puntos normalizados.
    /// Usa las dimensiones reales de la imagen capturada (camera.imageWidth/Height)
    /// para respetar el aspect ratio. Fallback a UIImage.size si no hay datos de cámara.
    private func recalculateDistance(pointA: NormalizedPoint, pointB: NormalizedPoint, data: OffsiteCaptureData, imageSize: CGSize, viewSize: CGSize) -> Double {
        // Prioridad 1: Depth-aware 3D distance (más precisa, usa profundidad real)
        if let snapshot = data.sceneSnapshot,
           let depthDist = calculateDepthAwareDistance(pointA: pointA, pointB: pointB, snapshot: snapshot) {
            return depthDist
        }

        // Obtener dimensiones consistentes con metersPerPixelScale
        let imgW: Double
        let imgH: Double
        if let cam = data.sceneSnapshot?.camera {
            imgW = Double(cam.imageWidth)
            imgH = Double(cam.imageHeight)
        } else {
            // Fallback: UIImage.size (en puntos, no pixeles)
            imgW = Double(imageSize.width)
            imgH = Double(imageSize.height)
        }

        // Convertir coordenadas normalizadas a pixeles reales (respeta aspect ratio)
        let pixelDx = (pointB.x - pointA.x) * imgW
        let pixelDy = (pointB.y - pointA.y) * imgH
        let pixelDistance = sqrt(pixelDx * pixelDx + pixelDy * pixelDy)

        // Prioridad 2: metersPerPixelScale del snapshot (metros/pixel)
        if let snapshot = data.sceneSnapshot, let mpp = snapshot.metersPerPixelScale, mpp > 0 {
            return pixelDistance * mpp
        }

        // Prioridad 3: Calcular escala desde medición AR
        if let arM = data.measurements.first(where: { $0.isFromAR }) {
            let arPixelDx = (arM.pointB.x - arM.pointA.x) * imgW
            let arPixelDy = (arM.pointB.y - arM.pointA.y) * imgH
            let arPixelDist = sqrt(arPixelDx * arPixelDx + arPixelDy * arPixelDy)
            guard arPixelDist > 1.0 else {
                return pixelDistance * AppConstants.OffsiteEditor.estimatedMetersPerPixel
            }
            return pixelDistance * (arM.distanceMeters / arPixelDist)
        }

        // Sin referencia AR: estimación muy aproximada
        return pixelDistance * AppConstants.OffsiteEditor.estimatedMetersPerPixel
    }

    /// Carga la imagen de un cuadro: primero intenta archivo, fallback a base64.
    func loadFrameImage(filename: String?, base64: String?) -> UIImage? {
        if let filename, let img = storageService.loadFrameImage(captureId: entry.id, filename: filename) {
            return img
        }
        if let base64, let data = Data(base64Encoded: base64) {
            return UIImage(data: data)
        }
        return nil
    }

    private func downscaleImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }
        let scaleFactor = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
