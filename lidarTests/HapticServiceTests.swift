//
//  HapticServiceTests.swift
//  lidarTests
//
//  Tests para el servicio de feedback háptico.
//

import Testing
@testable import lidar

@MainActor
@Suite("HapticService Tests")
struct HapticServiceTests {

    @Test("MockHapticService impact tracking")
    func mockImpactTracking() async {
        let mock = MockHapticService()
        #expect(mock.impactCallCount == 0)

        await mock.impact(style: .light)
        #expect(mock.impactCallCount == 1)
        #expect(mock.lastImpactStyle == .light)

        await mock.impact(style: .heavy)
        #expect(mock.impactCallCount == 2)
        #expect(mock.lastImpactStyle == .heavy)
    }

    @Test("MockHapticService notification tracking")
    func mockNotificationTracking() async {
        let mock = MockHapticService()
        #expect(mock.notificationCallCount == 0)

        await mock.notification(type: .success)
        #expect(mock.notificationCallCount == 1)
        #expect(mock.lastNotificationType == .success)

        await mock.notification(type: .error)
        #expect(mock.notificationCallCount == 2)
        #expect(mock.lastNotificationType == .error)
    }

    @Test("MockHapticService reset")
    func mockReset() async {
        let mock = MockHapticService()
        await mock.impact(style: .medium)
        await mock.notification(type: .warning)

        #expect(mock.impactCallCount == 1)
        #expect(mock.notificationCallCount == 1)

        mock.reset()
        #expect(mock.impactCallCount == 0)
        #expect(mock.notificationCallCount == 0)
        #expect(mock.lastImpactStyle == nil)
        #expect(mock.lastNotificationType == nil)
    }
}
