import Foundation
import UserNotifications

struct NotificationService: Sendable {
    enum ServiceError: LocalizedError {
        case authorizationDenied

        var errorDescription: String? {
            switch self {
            case .authorizationDenied:
                "通知权限未开启，请在“系统设置 → 通知 → Mwifi”中允许通知。"
            }
        }
    }

    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw ServiceError.authorizationDenied
            }
        case .denied:
            throw ServiceError.authorizationDenied
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            throw ServiceError.authorizationDenied
        }
    }

    func send(_ alert: BatteryAlert) async throws {
        try await requestAuthorization()

        let content = UNMutableNotificationContent()
        content.sound = .default

        switch alert {
        case .warning(let percentage):
            content.title = "Mwifi 电量较低"
            content.body = "移动 WiFi 剩余电量 \(percentage)%，请准备充电。"
        case .emergency(let percentage):
            content.title = "Mwifi 即将没电"
            content.body = "移动 WiFi 仅剩 \(percentage)%，请尽快连接充电器。"
        case .chargingTargetReached(let percentage):
            content.title = "Mwifi 已充至 60%"
            content.body = "移动 WiFi 当前电量为 \(percentage)%，已达到充电提醒电量。"
        }

        let request = UNNotificationRequest(
            identifier: "mwifi-battery-\(alert.identifier)",
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}

private extension BatteryAlert {
    var identifier: String {
        switch self {
        case .warning: "warning"
        case .emergency: "emergency"
        case .chargingTargetReached: "charging-target"
        }
    }
}
