//
//  MeasurementModelsTests.swift
//  lidarTests
//
//  Tests para las estructuras de medición.
//

import Testing
@testable import lidar

@Suite("MeasurementModels Tests")
struct MeasurementModelsTests {

    // MARK: - MeasurementUnit Tests

    @Test("MeasurementUnit format meters")
    func measurementUnitFormatMeters() {
        let unit = MeasurementUnit.meters
        let formatted = unit.format(distanceMeters: 1.5)
        #expect(formatted == "1.50 m")
    }

    @Test("MeasurementUnit format feet")
    func measurementUnitFormatFeet() {
        let unit = MeasurementUnit.feet
        let formatted = unit.format(distanceMeters: 1.0)
        #expect(formatted.hasPrefix("3.28")) // 1m ≈ 3.28ft
    }

    @Test("MeasurementUnit value conversion")
    func measurementUnitValueConversion() {
        let metersUnit = MeasurementUnit.meters
        let feetUnit = MeasurementUnit.feet

        #expect(metersUnit.value(fromMeters: 10.0) == 10.0)
        #expect(feetUnit.value(fromMeters: 1.0) > 3.0 && feetUnit.value(fromMeters: 1.0) < 4.0)
    }

    // MARK: - ARMeasurement Tests

    @Test("ARMeasurement initialization")
    func arMeasurementInit() {
        let pointA = SIMD3<Float>(0, 0, 0)
        let pointB = SIMD3<Float>(1, 0, 0)
        let measurement = ARMeasurement(pointA: pointA, pointB: pointB, distance: 1.0)

        #expect(measurement.distance == 1.0)
        #expect(measurement.pointA == pointA)
        #expect(measurement.pointB == pointB)
    }

    @Test("ARMeasurement equality")
    func arMeasurementEquality() {
        let m1 = ARMeasurement(pointA: SIMD3<Float>(0, 0, 0), pointB: SIMD3<Float>(1, 0, 0), distance: 1.0)
        let m2 = ARMeasurement(id: m1.id, pointA: SIMD3<Float>(0, 0, 0), pointB: SIMD3<Float>(1, 0, 0), distance: 1.0)
        let m3 = ARMeasurement(pointA: SIMD3<Float>(0, 0, 0), pointB: SIMD3<Float>(1, 0, 0), distance: 1.0)

        #expect(m1 == m2) // Mismo ID
        #expect(m1 != m3) // ID diferente
    }

    // MARK: - PlaneDimensions Tests

    @Test("PlaneDimensions equality")
    func planeDimensionsEquality() {
        let d1 = PlaneDimensions(width: 2.0, height: 3.0, extent: SIMD3<Float>(2, 3, 0))
        let d2 = PlaneDimensions(width: 2.0, height: 3.0, extent: SIMD3<Float>(2, 3, 0))
        let d3 = PlaneDimensions(width: 2.5, height: 3.0, extent: SIMD3<Float>(2.5, 3, 0))

        #expect(d1 == d2)
        #expect(d1 != d3)
    }
}
