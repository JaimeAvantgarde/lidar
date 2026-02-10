//
//  HapticService.swift
//  lidar
//
//  Servicio centralizado de feedback háptico. Encapsula UIFeedbackGenerator
//  detrás de un protocolo para facilitar testing y eliminar duplicación.
//

import UIKit

// MARK: - Protocol

/// Protocolo para el servicio de feedback háptico.
/// Permite inyección de dependencias y mocking en tests.
protocol HapticServiceProtocol: Sendable {
    @MainActor func impact(style: UIImpactFeedbackGenerator.FeedbackStyle)
    @MainActor func notification(type: UINotificationFeedbackGenerator.FeedbackType)
}

// MARK: - Implementation

/// Implementación real del servicio háptico usando UIFeedbackGenerator.
final class HapticService: HapticServiceProtocol, @unchecked Sendable {
    static let shared = HapticService()

    private init() {}

    @MainActor
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    @MainActor
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Mock for Testing

#if DEBUG
/// Mock del servicio háptico para tests unitarios.
final class MockHapticService: HapticServiceProtocol, @unchecked Sendable {
    var impactCallCount = 0
    var notificationCallCount = 0
    var lastImpactStyle: UIImpactFeedbackGenerator.FeedbackStyle?
    var lastNotificationType: UINotificationFeedbackGenerator.FeedbackType?

    @MainActor
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        impactCallCount += 1
        lastImpactStyle = style
    }

    @MainActor
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationCallCount += 1
        lastNotificationType = type
    }

    func reset() {
        impactCallCount = 0
        notificationCallCount = 0
        lastImpactStyle = nil
        lastNotificationType = nil
    }
}
#endif
