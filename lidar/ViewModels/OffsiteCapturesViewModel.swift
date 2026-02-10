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

/// ViewModel para la lista de capturas offsite.
@MainActor
@Observable
final class OffsiteCapturesListViewModel {
    var entries: [OffsiteCaptureEntry] = []

    private let storageService: StorageServiceProtocol
    private let hapticService: HapticServiceProtocol
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lidar", category: "OffsiteListVM")

    init(
        storageService: StorageServiceProtocol = StorageService.shared,
        hapticService: HapticServiceProtocol = HapticService.shared
    ) {
        self.storageService = storageService
        self.hapticService = hapticService
    }

    func loadEntries() {
        entries = storageService.loadOffsiteCaptures()
        logger.info("Cargadas \(self.entries.count) capturas")
    }

    func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            storageService.deleteCapture(entries[index])
        }
        entries.remove(atOffsets: offsets)
        hapticService.notification(type: .success)
    }

    func thumbnailURL(for entry: OffsiteCaptureEntry) -> URL {
        entry.imageURL.deletingLastPathComponent()
            .appendingPathComponent(entry.imageURL.deletingPathExtension().lastPathComponent + "_thumb.jpg")
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
    var pendingMeasurementPoint: CGPoint?
    var pendingMeasurementNormalizedPoint: NormalizedPoint?
    var pendingFrameStart: CGPoint?
    var showTextInput: Bool = false
    var newTextPosition: CGPoint?
    var pendingTextNormalizedPoint: NormalizedPoint?
    var newTextContent: String = ""

    let entry: OffsiteCaptureEntry

    // MARK: - Dependencies
    private let storageService: StorageServiceProtocol
    private let hapticService: HapticServiceProtocol
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lidar", category: "OffsiteDetailVM")

    enum EditTool: Equatable {
        case none, measure, frame, text
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
        case .measure:
            handleMeasureTap(point: normalizedPoint, screenPoint: location, viewSize: viewSize, imageSize: imageSize)
        case .frame:
            handleFrameTap(point: normalizedPoint)
        case .text:
            pendingTextNormalizedPoint = normalizedPoint
            newTextPosition = location
            showTextInput = true
        case .none:
            break
        }
    }

    func addTextAnnotation() {
        guard let point = pendingTextNormalizedPoint,
              !newTextContent.isEmpty,
              var currentData = data else { return }

        let annotation = OffsiteTextAnnotation(position: point, text: newTextContent)
        currentData.textAnnotations.append(annotation)
        data = currentData
        resetTextInput()
        hapticService.notification(type: .success)
    }

    func deleteMeasurement(id: UUID) {
        data?.measurements.removeAll { $0.id == id }
        hapticService.impact(style: .light)
    }

    func deleteFrame(id: UUID) {
        data?.frames.removeAll { $0.id == id }
        hapticService.impact(style: .light)
    }

    func deleteTextAnnotation(id: UUID) {
        data?.textAnnotations.removeAll { $0.id == id }
        hapticService.impact(style: .light)
    }

    func saveChanges() {
        guard var currentData = data else { return }
        currentData.lastModified = Date()

        do {
            try storageService.saveCaptureData(currentData, to: entry.jsonURL)
            data = currentData
            hapticService.notification(type: .success)
            exitEditMode()
            logger.info("Cambios guardados")
        } catch {
            logger.error("Error guardando: \(error.localizedDescription)")
        }
    }

    func cancelEdit() {
        data = storageService.loadCaptureData(from: entry.jsonURL)
        exitEditMode()
    }

    func toggleEditTool(_ tool: EditTool) {
        editTool = editTool == tool ? .none : tool
        resetPendingState()
        hapticService.impact(style: .medium)
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

    private func handleMeasureTap(point: NormalizedPoint, screenPoint: CGPoint, viewSize: CGSize, imageSize: CGSize) {
        guard var currentData = data else { return }

        if let firstPoint = pendingMeasurementPoint, let firstNorm = pendingMeasurementNormalizedPoint {
            let distance = calculateDistance(from: firstPoint, to: screenPoint, viewSize: viewSize, imageSize: imageSize)
            let newMeasurement = OffsiteMeasurement(distanceMeters: distance, pointA: firstNorm, pointB: point, isFromAR: false)
            currentData.measurements.append(newMeasurement)
            data = currentData
            pendingMeasurementPoint = nil
            pendingMeasurementNormalizedPoint = nil
            hapticService.notification(type: .success)
        } else {
            pendingMeasurementPoint = screenPoint
            pendingMeasurementNormalizedPoint = point
            hapticService.impact(style: .medium)
        }
    }

    private func handleFrameTap(point: NormalizedPoint) {
        guard var currentData = data else { return }

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

    private func calculateDistance(from pointA: CGPoint, to pointB: CGPoint, viewSize: CGSize, imageSize: CGSize) -> Double {
        let dx = pointB.x - pointA.x
        let dy = pointB.y - pointA.y
        let pixelDistance = sqrt(dx * dx + dy * dy)

        // Usar mediciones AR como referencia de escala si están disponibles
        if let currentData = data,
           let arMeasurement = currentData.measurements.first(where: { $0.isFromAR }) {
            let scale = scaleToFit(imageSize: imageSize, in: viewSize)
            let offset = offsetToCenter(imageSize: imageSize, in: viewSize, scale: scale)

            let refA = CGPoint(
                x: arMeasurement.pointA.x * imageSize.width * scale + offset.x,
                y: arMeasurement.pointA.y * imageSize.height * scale + offset.y
            )
            let refB = CGPoint(
                x: arMeasurement.pointB.x * imageSize.width * scale + offset.x,
                y: arMeasurement.pointB.y * imageSize.height * scale + offset.y
            )
            let refDx = refB.x - refA.x
            let refDy = refB.y - refA.y
            let refPixelDistance = sqrt(refDx * refDx + refDy * refDy)

            guard refPixelDistance > 0 else {
                return pixelDistance * AppConstants.OffsiteEditor.estimatedMetersPerPixel
            }

            let metersPerPixel = arMeasurement.distanceMeters / refPixelDistance
            return pixelDistance * metersPerPixel
        }

        // Sin referencia AR: estimación aproximada
        return pixelDistance * AppConstants.OffsiteEditor.estimatedMetersPerPixel
    }

    private func exitEditMode() {
        isEditMode = false
        editTool = .none
        resetPendingState()
    }

    private func resetPendingState() {
        pendingMeasurementPoint = nil
        pendingMeasurementNormalizedPoint = nil
        pendingFrameStart = nil
        pendingTextNormalizedPoint = nil
    }

    private func resetTextInput() {
        newTextContent = ""
        newTextPosition = nil
        pendingTextNormalizedPoint = nil
    }
}
