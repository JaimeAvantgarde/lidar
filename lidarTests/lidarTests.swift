//
//  lidarTests.swift
//  lidarTests
//
//  Tests unitarios para la app lidar.
//  Tests específicos por módulo están en archivos separados.
//

import Testing

// Los tests se han organizado en:
// - MeasurementModelsTests.swift: Modelos de medición
// - HapticServiceTests.swift: Servicio háptico
// - StorageServiceTests.swift: Servicio de persistencia
// - OffsiteCaptureTests.swift: Modelos de captura offsite
// - AppConstantsTests.swift: Validación de constantes

@Suite("lidar Core Tests")
struct lidarCoreTests {

    @Test("Placeholder test")
    func placeholderTest() async throws {
        // Test de integración básica
        #expect(true)
    }
}

