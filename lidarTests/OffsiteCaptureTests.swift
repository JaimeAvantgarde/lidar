//
//  OffsiteCaptureTests.swift
//  lidarTests
//
//  Tests para modelos de captura offsite.
//

import Testing
@testable import lidar

@Suite("OffsiteCapture Tests")
struct OffsiteCaptureTests {

    // MARK: - NormalizedPoint Tests

    @Test("NormalizedPoint isValid - valid points")
    func normalizedPointValid() {
        let p1 = NormalizedPoint(x: 0.0, y: 0.0)
        let p2 = NormalizedPoint(x: 1.0, y: 1.0)
        let p3 = NormalizedPoint(x: 0.5, y: 0.5)

        #expect(p1.isValid)
        #expect(p2.isValid)
        #expect(p3.isValid)
    }

    @Test("NormalizedPoint isValid - invalid points")
    func normalizedPointInvalid() {
        let p1 = NormalizedPoint(x: -0.1, y: 0.5)
        let p2 = NormalizedPoint(x: 0.5, y: 1.1)
        let p3 = NormalizedPoint(x: 2.0, y: 2.0)

        #expect(!p1.isValid)
        #expect(!p2.isValid)
        #expect(!p3.isValid)
    }

    @Test("NormalizedPoint equality")
    func normalizedPointEquality() {
        let p1 = NormalizedPoint(x: 0.5, y: 0.5)
        let p2 = NormalizedPoint(x: 0.5, y: 0.5)
        let p3 = NormalizedPoint(x: 0.6, y: 0.5)

        #expect(p1 == p2)
        #expect(p1 != p3)
    }

    // MARK: - OffsiteMeasurement Tests

    @Test("OffsiteMeasurement initialization with defaults")
    func offsiteMeasurementDefaults() {
        let pointA = NormalizedPoint(x: 0.1, y: 0.1)
        let pointB = NormalizedPoint(x: 0.9, y: 0.9)
        let measurement = OffsiteMeasurement(distanceMeters: 2.5, pointA: pointA, pointB: pointB)

        #expect(measurement.distanceMeters == 2.5)
        #expect(measurement.isFromAR == true) // Default
    }

    @Test("OffsiteMeasurement isFromAR flag")
    func offsiteMeasurementIsFromAR() {
        let pointA = NormalizedPoint(x: 0.1, y: 0.1)
        let pointB = NormalizedPoint(x: 0.9, y: 0.9)
        let arMeasurement = OffsiteMeasurement(distanceMeters: 2.0, pointA: pointA, pointB: pointB, isFromAR: true)
        let offsiteMeasurement = OffsiteMeasurement(distanceMeters: 2.0, pointA: pointA, pointB: pointB, isFromAR: false)

        #expect(arMeasurement.isFromAR == true)
        #expect(offsiteMeasurement.isFromAR == false)
    }

    // MARK: - OffsiteFrame Tests

    @Test("OffsiteFrame initialization")
    func offsiteFrameInit() {
        let topLeft = NormalizedPoint(x: 0.2, y: 0.2)
        let frame = OffsiteFrame(topLeft: topLeft, width: 0.3, height: 0.4, label: "Test Frame", color: "#FF0000")

        #expect(frame.topLeft == topLeft)
        #expect(frame.width == 0.3)
        #expect(frame.height == 0.4)
        #expect(frame.label == "Test Frame")
        #expect(frame.color == "#FF0000")
    }

    @Test("OffsiteFrame default values")
    func offsiteFrameDefaults() {
        let topLeft = NormalizedPoint(x: 0.0, y: 0.0)
        let frame = OffsiteFrame(topLeft: topLeft, width: 0.1, height: 0.1)

        #expect(frame.label == nil)
        #expect(frame.color == "#3B82F6") // Default blue
    }

    // MARK: - OffsiteTextAnnotation Tests

    @Test("OffsiteTextAnnotation initialization")
    func offsiteTextAnnotationInit() {
        let position = NormalizedPoint(x: 0.5, y: 0.5)
        let annotation = OffsiteTextAnnotation(position: position, text: "Hello", color: "#00FF00")

        #expect(annotation.text == "Hello")
        #expect(annotation.position == position)
        #expect(annotation.color == "#00FF00")
    }

    @Test("OffsiteTextAnnotation default color")
    func offsiteTextAnnotationDefaultColor() {
        let position = NormalizedPoint(x: 0.5, y: 0.5)
        let annotation = OffsiteTextAnnotation(position: position, text: "Test")

        #expect(annotation.color == "#FFFFFF") // Default white
    }

    // MARK: - OffsiteCaptureData Tests

    @Test("OffsiteCaptureData initialization")
    func offsiteCaptureDataInit() {
        let measurement = OffsiteMeasurement(
            distanceMeters: 1.0,
            pointA: NormalizedPoint(x: 0, y: 0),
            pointB: NormalizedPoint(x: 1, y: 1),
            isFromAR: true
        )
        let data = OffsiteCaptureData(capturedAt: Date(), measurements: [measurement])

        #expect(data.measurements.count == 1)
        #expect(data.frames.isEmpty)
        #expect(data.textAnnotations.isEmpty)
        #expect(data.lastModified == nil)
    }

    @Test("OffsiteCaptureData mutability")
    func offsiteCaptureDataMutability() {
        var data = OffsiteCaptureData(capturedAt: Date(), measurements: [])

        #expect(data.measurements.isEmpty)

        let measurement = OffsiteMeasurement(
            distanceMeters: 2.0,
            pointA: NormalizedPoint(x: 0, y: 0),
            pointB: NormalizedPoint(x: 1, y: 0),
            isFromAR: false
        )
        data.measurements.append(measurement)

        #expect(data.measurements.count == 1)
    }

    // MARK: - OffsiteCaptureEntry Tests

    @Test("OffsiteCaptureEntry equality")
    func offsiteCaptureEntryEquality() {
        let url1 = URL(fileURLWithPath: "/test.jpg")
        let url2 = URL(fileURLWithPath: "/test.json")
        let date = Date()

        let entry1 = OffsiteCaptureEntry(id: "test", imageURL: url1, jsonURL: url2, capturedAt: date)
        let entry2 = OffsiteCaptureEntry(id: "test", imageURL: url1, jsonURL: url2, capturedAt: date)
        let entry3 = OffsiteCaptureEntry(id: "other", imageURL: url1, jsonURL: url2, capturedAt: date)

        #expect(entry1 == entry2) // Mismo ID
        #expect(entry1 != entry3) // ID diferente
    }

    @Test("OffsiteCaptureEntry hashable")
    func offsiteCaptureEntryHashable() {
        let entry1 = OffsiteCaptureEntry(
            id: "test",
            imageURL: URL(fileURLWithPath: "/test.jpg"),
            jsonURL: URL(fileURLWithPath: "/test.json"),
            capturedAt: Date()
        )
        let entry2 = OffsiteCaptureEntry(
            id: "test",
            imageURL: URL(fileURLWithPath: "/test.jpg"),
            jsonURL: URL(fileURLWithPath: "/test.json"),
            capturedAt: Date()
        )

        var set = Set<OffsiteCaptureEntry>()
        set.insert(entry1)
        set.insert(entry2)

        #expect(set.count == 1) // Solo uno porque tienen el mismo ID
    }
}
