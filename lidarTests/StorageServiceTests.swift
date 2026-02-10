//
//  StorageServiceTests.swift
//  lidarTests
//
//  Tests para el servicio de persistencia.
//

import Testing
@testable import lidar
import Foundation
import UIKit

@Suite("StorageService Tests")
struct StorageServiceTests {

    @Test("MockStorageService load captures")
    func mockLoadCaptures() {
        let mock = MockStorageService()
        let entry1 = OffsiteCaptureEntry(
            id: "test1",
            imageURL: URL(fileURLWithPath: "/test1.jpg"),
            jsonURL: URL(fileURLWithPath: "/test1.json"),
            capturedAt: Date()
        )
        mock.mockEntries = [entry1]

        let loaded = mock.loadOffsiteCaptures()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == "test1")
    }

    @Test("MockStorageService delete capture")
    func mockDeleteCapture() {
        let mock = MockStorageService()
        let entry1 = OffsiteCaptureEntry(
            id: "test1",
            imageURL: URL(fileURLWithPath: "/test1.jpg"),
            jsonURL: URL(fileURLWithPath: "/test1.json"),
            capturedAt: Date()
        )
        let entry2 = OffsiteCaptureEntry(
            id: "test2",
            imageURL: URL(fileURLWithPath: "/test2.jpg"),
            jsonURL: URL(fileURLWithPath: "/test2.json"),
            capturedAt: Date()
        )
        mock.mockEntries = [entry1, entry2]

        mock.deleteCapture(entry1)
        #expect(mock.deletedEntries.count == 1)
        #expect(mock.deletedEntries.first?.id == "test1")
        #expect(mock.mockEntries.count == 1)
        #expect(mock.mockEntries.first?.id == "test2")
    }

    @Test("MockStorageService save capture data")
    func mockSaveCaptureData() throws {
        let mock = MockStorageService()
        let data = OffsiteCaptureData(
            capturedAt: Date(),
            measurements: [],
            frames: [],
            textAnnotations: []
        )

        try mock.saveCaptureData(data, to: URL(fileURLWithPath: "/test.json"))
        #expect(mock.savedData != nil)
        #expect(mock.savedData?.measurements.isEmpty == true)
    }

    @Test("MockStorageService save throws when configured")
    func mockSaveThrows() {
        let mock = MockStorageService()
        mock.shouldThrowOnSave = true
        let data = OffsiteCaptureData(capturedAt: Date(), measurements: [], frames: [], textAnnotations: [])

        #expect(throws: StorageError.self) {
            try mock.saveCaptureData(data, to: URL(fileURLWithPath: "/test.json"))
        }
    }

    @Test("MockStorageService load capture data")
    func mockLoadCaptureData() {
        let mock = MockStorageService()
        let data = OffsiteCaptureData(capturedAt: Date(), measurements: [], frames: [], textAnnotations: [])
        mock.savedData = data

        let loaded = mock.loadCaptureData(from: URL(fileURLWithPath: "/test.json"))
        #expect(loaded != nil)
        #expect(loaded?.measurements.isEmpty == true)
    }

    @Test("MockStorageService create capture files")
    func mockCreateCaptureFiles() throws {
        let mock = MockStorageService()
        let image = UIImage()

        let files = try mock.createCaptureFiles(image: image)
        #expect(files.baseName == "test_capture")
        #expect(files.imageURL.lastPathComponent == "test_capture.jpg")
        #expect(files.jsonURL.lastPathComponent == "test_capture.json")
        #expect(files.thumbnailURL.lastPathComponent == "test_capture_thumb.jpg")
    }

    @Test("MockStorageService reset")
    func mockReset() {
        let mock = MockStorageService()
        let entry = OffsiteCaptureEntry(
            id: "test",
            imageURL: URL(fileURLWithPath: "/test.jpg"),
            jsonURL: URL(fileURLWithPath: "/test.json"),
            capturedAt: Date()
        )
        mock.mockEntries = [entry]
        mock.deletedEntries = [entry]
        mock.savedData = OffsiteCaptureData(capturedAt: Date(), measurements: [], frames: [], textAnnotations: [])
        mock.shouldThrowOnSave = true

        mock.reset()
        #expect(mock.mockEntries.isEmpty)
        #expect(mock.deletedEntries.isEmpty)
        #expect(mock.savedData == nil)
        #expect(mock.shouldThrowOnSave == false)
    }
}
