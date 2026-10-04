import XCTest
@testable import Mwifi

final class NotificationPolicyTests: XCTestCase {
    func testSendsEachAlertOnlyOncePerDischargeCycle() {
        var policy = NotificationPolicy(warningSent: false, emergencySent: false, chargingTargetSent: false)

        XCTAssertEqual(policy.evaluate(percentage: 20, isCharging: false, warningThreshold: 20, emergencyThreshold: 10), .warning(20))
        policy.recordDelivery(of: .warning(20))
        XCTAssertNil(policy.evaluate(percentage: 18, isCharging: false, warningThreshold: 20, emergencyThreshold: 10))
        XCTAssertEqual(policy.evaluate(percentage: 10, isCharging: false, warningThreshold: 20, emergencyThreshold: 10), .emergency(10))
        policy.recordDelivery(of: .emergency(10))
        XCTAssertNil(policy.evaluate(percentage: 8, isCharging: false, warningThreshold: 20, emergencyThreshold: 10))

        XCTAssertNil(policy.evaluate(percentage: 30, isCharging: false, warningThreshold: 20, emergencyThreshold: 10))
        XCTAssertEqual(policy.evaluate(percentage: 19, isCharging: false, warningThreshold: 20, emergencyThreshold: 10), .warning(19))
    }

    func testJumpingDirectlyToEmergencyDoesNotAlsoSendWarning() {
        var policy = NotificationPolicy(warningSent: false, emergencySent: false, chargingTargetSent: false)
        XCTAssertEqual(policy.evaluate(percentage: 7, isCharging: false, warningThreshold: 20, emergencyThreshold: 10), .emergency(7))
        policy.recordDelivery(of: .emergency(7))
        XCTAssertNil(policy.evaluate(percentage: 7, isCharging: false, warningThreshold: 20, emergencyThreshold: 10))
    }

    func testChargingTargetSendsOncePerChargingCycle() {
        var policy = NotificationPolicy(warningSent: false, emergencySent: false, chargingTargetSent: false)

        XCTAssertNil(policy.evaluate(percentage: 59, isCharging: true, warningThreshold: 20, emergencyThreshold: 10))
        XCTAssertEqual(policy.evaluate(percentage: 60, isCharging: true, warningThreshold: 20, emergencyThreshold: 10), .chargingTargetReached(60))
        policy.recordDelivery(of: .chargingTargetReached(60))
        XCTAssertNil(policy.evaluate(percentage: 75, isCharging: true, warningThreshold: 20, emergencyThreshold: 10))
        XCTAssertNil(policy.evaluate(percentage: 75, isCharging: false, warningThreshold: 20, emergencyThreshold: 10))
        XCTAssertEqual(policy.evaluate(percentage: 62, isCharging: true, warningThreshold: 20, emergencyThreshold: 10), .chargingTargetReached(62))
    }

    func testFailedDeliveryRemainsEligibleForRetry() {
        var lowBatteryPolicy = NotificationPolicy(warningSent: false, emergencySent: false, chargingTargetSent: false)
        XCTAssertEqual(lowBatteryPolicy.evaluate(percentage: 20, isCharging: false, warningThreshold: 20, emergencyThreshold: 10), .warning(20))
        XCTAssertEqual(lowBatteryPolicy.evaluate(percentage: 20, isCharging: false, warningThreshold: 20, emergencyThreshold: 10), .warning(20))

        var chargingPolicy = NotificationPolicy(warningSent: false, emergencySent: false, chargingTargetSent: false)
        XCTAssertEqual(chargingPolicy.evaluate(percentage: 60, isCharging: true, warningThreshold: 20, emergencyThreshold: 10), .chargingTargetReached(60))
        XCTAssertEqual(chargingPolicy.evaluate(percentage: 60, isCharging: true, warningThreshold: 20, emergencyThreshold: 10), .chargingTargetReached(60))
    }
}
