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

        // Prioridad 1: Endpoints de medición
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

        // Verificar que el drag es sobre el item seleccionado (mismo UUID)
        let hitItem = hitTest(at: location, viewSize: viewSize, imageSize: imageSize)
        if hitItem?.itemId != item.itemId {
            isDragging = false
            dragStartNormalized = nil
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
            if !m.isFromAR {
                m.distanceMeters = recalculateDistance(pointA: m.pointA, pointB: m.pointB, data: currentData, imageSize: imageSize, viewSize: viewSize)
            }
            currentData.measurements[idx] = m

        case .measurementEndpointB(let id):
            guard let idx = currentData.measurements.firstIndex(where: { $0.id == id }) else { return }
            var m = currentData.measurements[idx]
            let newX = clamp(m.pointB.x + dx, 0, 1)
            let newY = clamp(m.pointB.y + dy, 0, 1)
            m.pointB = NormalizedPoint(x: newX, y: newY)
            if !m.isFromAR {
                m.distanceMeters = recalculateDistance(pointA: m.pointA, pointB: m.pointB, data: currentData, imageSize: imageSize, viewSize: viewSize)
            }
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
            let newCx = clamp(pf.center2D.x + dx, 0, 1)
            let newCy = clamp(pf.center2D.y + dy, 0, 1)
            pf.center2D = NormalizedPoint(x: newCx, y: newCy)
            pf.corners2D = pf.corners2D.map { corner in
                guard corner.count >= 2 else { return corner }
                return [clamp(corner[0] + dx, 0, 1), clamp(corner[1] + dy, 0, 1)]
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
        case .measurement(let id), .measurementEndpointA(let id), .measurementEndpointB(let id):
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
            data = currentData
            originalDataSnapshot = currentData
            hapticService.notification(type: .success)
            exitEditMode()
            logger.info("Cambios guardados")
        } catch {
            logger.error("Error guardando: \(error.localizedDescription)")
        }
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
        case .measurement(let id), .measurementEndpointA(let id), .measurementEndpointB(let id):
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
        case .measurement, .measurementEndpointA, .measurementEndpointB: return "ruler"
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

    /// ID del cuadro seleccionado (standard o perspectiva).
    var selectedFrameId: UUID? {
        guard let item = selectedItem else { return nil }
        switch item {
        case .frame(let id), .frameResizeBottomRight(let id), .perspectiveFrame(let id): return id
        default: return nil
        }
    }

    // MARK: - Geometry Helpers

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

    /// Calcula distancia en metros entre dos puntos normalizados.
    /// Usa las dimensiones reales de la imagen capturada (camera.imageWidth/Height)
    /// para respetar el aspect ratio. Fallback a UIImage.size si no hay datos de cámara.
    private func recalculateDistance(pointA: NormalizedPoint, pointB: NormalizedPoint, data: OffsiteCaptureData, imageSize: CGSize, viewSize: CGSize) -> Double {
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

        // Prioridad 1: metersPerPixelScale del snapshot (metros/pixel)
        if let snapshot = data.sceneSnapshot, let mpp = snapshot.metersPerPixelScale, mpp > 0 {
            return pixelDistance * mpp
        }

        // Prioridad 2: Calcular escala desde medición AR
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
