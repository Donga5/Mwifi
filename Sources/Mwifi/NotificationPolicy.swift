import Foundation

enum BatteryAlert: Equatable, Sendable {
    case warning(Int)
    case emergency(Int)
    case chargingTargetReached(Int)
}

struct NotificationPolicy: Sendable {
    var warningSent: Bool
    var emergencySent: Bool
    var chargingTargetSent: Bool

    mutating func evaluate(
        percentage: Int,
        isCharging: Bool,
        warningThreshold: Int,
        emergencyThreshold: Int,
        chargingTarget: Int = 60
    ) -> BatteryAlert? {
        if !isCharging {
            chargingTargetSent = false
        } else if percentage >= chargingTarget, !chargingTargetSent {
            return .chargingTargetReached(percentage)
        }

        if percentage > warningThreshold { warningSent = false }
        if percentage > emergencyThreshold { emergencySent = false }

        if percentage <= emergencyThreshold, !emergencySent {
            return .emergency(percentage)
        }
        if percentage <= warningThreshold, !warningSent {
            return .warning(percentage)
        }
        return nil
    }

    mutating func recordDelivery(of alert: BatteryAlert) {
        switch alert {
        case .warning:
            warningSent = true
        case .emergency:
            emergencySent = true
            warningSent = true
        case .chargingTargetReached:
            chargingTargetSent = true
        }
    }
}
