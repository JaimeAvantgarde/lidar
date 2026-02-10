//
//  AppConstantsTests.swift
//  lidarTests
//
//  Tests para validar que las constantes tienen valores razonables.
//

import Testing
@testable import lidar
import CoreGraphics

@Suite("AppConstants Tests")
struct AppConstantsTests {

    // MARK: - Layout Tests

    @Test("Layout constants are positive")
    func layoutConstantsPositive() {
        #expect(AppConstants.Layout.topBarExclusionZone > 0)
        #expect(AppConstants.Layout.bottomPanelExclusionZone > 0)
        #expect(AppConstants.Layout.panelContentHeight > 0)
        #expect(AppConstants.Layout.panelCornerRadius > 0)
    }

    @Test("Layout exclusion zones are reasonable")
    func layoutExclusionZones() {
        // Zonas de exclusión deben ser menores que resoluciones típicas
        #expect(AppConstants.Layout.topBarExclusionZone < 200)
        #expect(AppConstants.Layout.bottomPanelExclusionZone < 500)
    }

    // MARK: - AR Tests

    @Test("AR sizes are positive")
    func arSizesPositive() {
        #expect(AppConstants.AR.defaultFrameSize.width > 0)
        #expect(AppConstants.AR.defaultFrameSize.height > 0)
        #expect(AppConstants.AR.measurementPointRadius > 0)
        #expect(AppConstants.AR.measurementLineRadius > 0)
    }

    @Test("AR corner detection thresholds are valid")
    func arCornerThresholds() {
        // Dot products para 90° deben estar cerca de 0
        #expect(AppConstants.AR.cornerMinDot < 0)
        #expect(AppConstants.AR.cornerMaxDot > 0)
        #expect(AppConstants.AR.cornerMinDot < AppConstants.AR.cornerMaxDot)
    }

    @Test("AR line segments count is reasonable")
    func arLineSegments() {
        #expect(AppConstants.AR.lineRadialSegments >= 3)
        #expect(AppConstants.AR.lineRadialSegments <= 32)
    }

    // MARK: - Capture Tests

    @Test("Capture quality values are valid")
    func captureQuality() {
        #expect(AppConstants.Capture.jpegQuality >= 0.0)
        #expect(AppConstants.Capture.jpegQuality <= 1.0)
        #expect(AppConstants.Capture.thumbnailQuality >= 0.0)
        #expect(AppConstants.Capture.thumbnailQuality <= 1.0)
    }

    @Test("Capture thumbnail size is reasonable")
    func captureThumbnailSize() {
        #expect(AppConstants.Capture.thumbnailSize.width > 0)
        #expect(AppConstants.Capture.thumbnailSize.height > 0)
        #expect(AppConstants.Capture.thumbnailSize.width <= 400)
        #expect(AppConstants.Capture.thumbnailSize.height <= 400)
    }

    // MARK: - Measurement Tests

    @Test("Measurement feet conversion is correct")
    func measurementFeetConversion() {
        let factor = AppConstants.Measurement.feetConversionFactor
        #expect(factor > 3.0 && factor < 3.5) // 1m ≈ 3.28ft
    }

    @Test("Measurement zoom range is valid")
    func measurementZoomRange() {
        let range = AppConstants.Measurement.zoomRange
        #expect(range.lowerBound >= 1.0)
        #expect(range.upperBound <= 5.0)
        #expect(range.lowerBound < range.upperBound)
    }

    @Test("Measurement zoom step is reasonable")
    func measurementZoomStep() {
        #expect(AppConstants.Measurement.zoomStep > 0.0)
        #expect(AppConstants.Measurement.zoomStep < 1.0)
    }

    // MARK: - Cuadros Tests

    @Test("Cuadros size range is valid")
    func cuadrosSizeRange() {
        #expect(AppConstants.Cuadros.minSize > 0)
        #expect(AppConstants.Cuadros.maxSize > AppConstants.Cuadros.minSize)
        #expect(AppConstants.Cuadros.defaultSize >= AppConstants.Cuadros.minSize)
        #expect(AppConstants.Cuadros.defaultSize <= AppConstants.Cuadros.maxSize)
    }

    @Test("Cuadros aspect ratio is reasonable")
    func cuadrosAspectRatio() {
        #expect(AppConstants.Cuadros.aspectRatio > 0)
        #expect(AppConstants.Cuadros.aspectRatio <= 2.0)
    }

    // MARK: - Offsite Editor Tests

    @Test("Offsite editor frame size is normalized")
    func offsiteFrameSizeNormalized() {
        #expect(AppConstants.OffsiteEditor.defaultFrameSize > 0)
        #expect(AppConstants.OffsiteEditor.defaultFrameSize < 1.0)
    }

    @Test("Offsite editor has color options")
    func offsiteEditorColors() {
        #expect(!AppConstants.OffsiteEditor.availableColors.isEmpty)
        #expect(AppConstants.OffsiteEditor.availableColors.allSatisfy { $0.hasPrefix("#") })
    }

    @Test("Offsite editor meters per pixel is positive")
    func offsiteMetersPerPixel() {
        #expect(AppConstants.OffsiteEditor.estimatedMetersPerPixel > 0)
    }

    // MARK: - Animation Tests

    @Test("Animation spring values are valid")
    func animationSpringValues() {
        #expect(AppConstants.Animation.springResponse > 0)
        #expect(AppConstants.Animation.springDamping > 0)
        #expect(AppConstants.Animation.springDamping <= 1.0)
        #expect(AppConstants.Animation.zoomDuration > 0)
    }
}
