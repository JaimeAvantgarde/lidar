//
//  StorageService.swift
//  lidar
//
//  Servicio de persistencia: gestiona lectura/escritura de capturas offsite.
//  Centraliza el acceso a FileManager y la codificación/decodificación JSON.
//

import Foundation
import UIKit
import os.log

// MARK: - Protocol

/// Protocolo para el servicio de almacenamiento de capturas offsite.
protocol StorageServiceProtocol: Sendable {
    /// Carga todas las capturas offsite guardadas.
    func loadOffsiteCaptures() -> [OffsiteCaptureEntry]
    /// Elimina una captura (imagen, JSON y thumbnail).
    func deleteCapture(_ entry: OffsiteCaptureEntry)
    /// Guarda datos de captura en formato JSON.
    func saveCaptureData(_ data: OffsiteCaptureData, to url: URL) throws
    /// Carga datos de captura desde un archivo JSON.
    func loadCaptureData(from url: URL) -> OffsiteCaptureData?
    /// Crea los archivos de una nueva captura (imagen + thumbnail) y devuelve las URLs.
    func createCaptureFiles(image: UIImage) throws -> CaptureFileURLs
    /// Directorio donde se almacenan las capturas.
    var capturesDirectory: URL { get }
}

// MARK: - Supporting Types

/// URLs generadas al crear una captura.
struct CaptureFileURLs {
    let imageURL: URL
    let jsonURL: URL
    let thumbnailURL: URL
    let baseName: String
}

/// Errores del servicio de almacenamiento.
enum StorageError: LocalizedError {
    case imageEncodingFailed
    case directoryCreationFailed
    case documentsUnavailable

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: return "No se pudo codificar la imagen"
        case .directoryCreationFailed: return "No se pudo crear el directorio"
        case .documentsUnavailable: return "No se pudo acceder al directorio Documents"
        }
    }
}

// MARK: - Implementation

/// Implementación del servicio de almacenamiento usando FileManager.
final class StorageService: StorageServiceProtocol, @unchecked Sendable {
    static let shared = StorageService()

    private let fileManager: FileManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lidar", category: "Storage")

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var capturesDirectory: URL {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Cannot access Documents directory")
        }
        return docs.appendingPathComponent(AppConstants.Capture.directoryName, isDirectory: true)
    }

    func loadOffsiteCaptures() -> [OffsiteCaptureEntry] {
        do {
            try fileManager.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
            let contents = try fileManager.contentsOfDirectory(
                at: capturesDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )

            let jpgURLs = contents.filter {
                $0.pathExtension.lowercased() == "jpg" && !$0.lastPathComponent.contains("_thumb")
            }

            var entries: [OffsiteCaptureEntry] = []
            for imageURL in jpgURLs {
                let base = imageURL.deletingPathExtension().lastPathComponent
                let jsonURL = capturesDirectory.appendingPathComponent("\(base).json")
                guard fileManager.fileExists(atPath: jsonURL.path) else {
                    logger.warning("JSON no encontrado para captura: \(base)")
                    continue
                }
                let date = (try? fileManager.attributesOfItem(atPath: imageURL.path)[.modificationDate] as? Date) ?? Date()
                entries.append(OffsiteCaptureEntry(id: base, imageURL: imageURL, jsonURL: jsonURL, capturedAt: date))
            }

            logger.info("Cargadas \(entries.count) capturas offsite")
            return entries.sorted { $0.capturedAt > $1.capturedAt }
        } catch {
            logger.error("Error cargando capturas: \(error.localizedDescription)")
            return []
        }
    }

    func deleteCapture(_ entry: OffsiteCaptureEntry) {
        let thumbURL = thumbnailURL(for: entry.imageURL)

        for url in [entry.imageURL, entry.jsonURL, thumbURL] {
            do {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            } catch {
                logger.warning("Error eliminando \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        logger.info("Captura eliminada: \(entry.id)")
    }

    func saveCaptureData(_ data: OffsiteCaptureData, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url)
        logger.info("Datos de captura guardados: \(url.lastPathComponent)")
    }

    func loadCaptureData(from url: URL) -> OffsiteCaptureData? {
        guard let rawData = try? Data(contentsOf: url) else {
            logger.warning("No se puede leer: \(url.lastPathComponent)")
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateString) ?? Date()
        }

        do {
            let decoded = try decoder.decode(OffsiteCaptureData.self, from: rawData)
            return decoded
        } catch {
            logger.error("Error decodificando captura: \(error.localizedDescription)")
            return nil
        }
    }

    func createCaptureFiles(image: UIImage) throws -> CaptureFileURLs {
        try fileManager.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = AppConstants.Capture.dateFormat
        let baseName = "\(AppConstants.Capture.filePrefix)\(formatter.string(from: Date()))"

        let imageURL = capturesDirectory.appendingPathComponent("\(baseName).jpg")
        let jsonURL = capturesDirectory.appendingPathComponent("\(baseName).json")
        let thumbURL = capturesDirectory.appendingPathComponent("\(baseName)_thumb.jpg")

        guard let jpeg = image.jpegData(compressionQuality: AppConstants.Capture.jpegQuality) else {
            throw StorageError.imageEncodingFailed
        }
        try jpeg.write(to: imageURL)

        // Crear thumbnail optimizado
        if let thumbnail = image.preparingThumbnail(of: AppConstants.Capture.thumbnailSize),
           let thumbData = thumbnail.jpegData(compressionQuality: AppConstants.Capture.thumbnailQuality) {
            try? thumbData.write(to: thumbURL)
        }

        logger.info("Archivos de captura creados: \(baseName)")
        return CaptureFileURLs(imageURL: imageURL, jsonURL: jsonURL, thumbnailURL: thumbURL, baseName: baseName)
    }

    // MARK: - Helpers

    private func thumbnailURL(for imageURL: URL) -> URL {
        imageURL.deletingLastPathComponent()
            .appendingPathComponent(imageURL.deletingPathExtension().lastPathComponent + "_thumb.jpg")
    }
}

// MARK: - Mock for Testing

#if DEBUG
/// Mock del servicio de almacenamiento para tests unitarios.
final class MockStorageService: StorageServiceProtocol, @unchecked Sendable {
    var mockEntries: [OffsiteCaptureEntry] = []
    var savedData: OffsiteCaptureData?
    var deletedEntries: [OffsiteCaptureEntry] = []
    var shouldThrowOnSave = false

    var capturesDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TestCaptures")
    }

    func loadOffsiteCaptures() -> [OffsiteCaptureEntry] {
        mockEntries
    }

    func deleteCapture(_ entry: OffsiteCaptureEntry) {
        deletedEntries.append(entry)
        mockEntries.removeAll { $0.id == entry.id }
    }

    func saveCaptureData(_ data: OffsiteCaptureData, to url: URL) throws {
        if shouldThrowOnSave { throw StorageError.imageEncodingFailed }
        savedData = data
    }

    func loadCaptureData(from url: URL) -> OffsiteCaptureData? {
        savedData
    }

    func createCaptureFiles(image: UIImage) throws -> CaptureFileURLs {
        let dir = capturesDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let baseName = "test_capture"
        return CaptureFileURLs(
            imageURL: dir.appendingPathComponent("\(baseName).jpg"),
            jsonURL: dir.appendingPathComponent("\(baseName).json"),
            thumbnailURL: dir.appendingPathComponent("\(baseName)_thumb.jpg"),
            baseName: baseName
        )
    }

    func reset() {
        mockEntries = []
        savedData = nil
        deletedEntries = []
        shouldThrowOnSave = false
    }
}
#endif
