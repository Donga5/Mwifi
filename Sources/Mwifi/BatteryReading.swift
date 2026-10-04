import Foundation

struct BatteryReading: Equatable, Sendable {
    let percentage: Int
    let isCharging: Bool
}

struct TransferRates: Equatable, Sendable {
    let uploadBytesPerSecond: Double
    let downloadBytesPerSecond: Double

    static let zero = TransferRates(uploadBytesPerSecond: 0, downloadBytesPerSecond: 0)

    var formattedUpload: String { Self.format(uploadBytesPerSecond) }
    var formattedDownload: String { Self.format(downloadBytesPerSecond) }

    private static func format(_ bytesPerSecond: Double) -> String {
        let megabytesPerSecond = max(0, bytesPerSecond) / 1_000_000
        if megabytesPerSecond > 0, megabytesPerSecond < 0.01 {
            return "<0.01 MB/s"
        }
        return String(format: "%.2f MB/s", megabytesPerSecond)
    }
}

struct RouterSnapshot: Equatable, Sendable {
    let battery: BatteryReading
    let transferRates: TransferRates
    let carrierName: String?
}

enum RouterResponseParser {
    enum ParseError: LocalizedError, Equatable {
        case invalidJSON
        case missingPercentage
        case invalidPercentage

        var errorDescription: String? {
            switch self {
            case .invalidJSON: "设备返回了无法识别的数据"
            case .missingPercentage: "设备没有返回电量"
            case .invalidPercentage: "设备返回的电量无效"
            }
        }
    }

    static func parse(_ data: Data) throws -> RouterSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            throw ParseError.invalidJSON
        }

        let rawPercentage = firstValue(in: json, keys: [
            "battery_vol_percent", "battery_pers", "battery_percent", "battery_value"
        ])
        guard let rawPercentage else {
            throw ParseError.missingPercentage
        }
        guard let percentage = integer(from: rawPercentage), (0...100).contains(percentage) else {
            throw ParseError.invalidPercentage
        }

        let chargingValue = firstValue(in: json, keys: [
            "battery_charging", "external_charging_flag", "battery_charg_type"
        ])
        let battery = BatteryReading(
            percentage: percentage,
            isCharging: chargingValue.map(isTruthy) ?? false
        )
        let transferRates = TransferRates(
            uploadBytesPerSecond: number(from: firstValue(
                in: json,
                keys: ["flux_realtime_tx_thrpt", "realtime_tx_thrpt"]
            )) ?? 0,
            downloadBytesPerSecond: number(from: firstValue(
                in: json,
                keys: ["flux_realtime_rx_thrpt", "realtime_rx_thrpt"]
            )) ?? 0
        )
        return RouterSnapshot(
            battery: battery,
            transferRates: transferRates,
            carrierName: firstNonEmptyString(in: json, keys: [
                "network_provider_fullname",
                "network_provider",
                "sim_spn_name_data",
                "spn_name_data"
            ])
        )
    }

    private static func firstValue(in json: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = json[key], !(value is NSNull) {
                return value
            }
        }
        return nil
    }

    private static func integer(from value: Any) -> Int? {
        if let integer = value as? Int { return integer }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String {
            let digits = string.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix { $0.isNumber }
            return Int(digits)
        }
        return nil
    }

    private static func number(from value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let string = value as? String else { return nil }
        return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func firstNonEmptyString(in json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let string = json[key] as? String else { continue }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func isTruthy(_ value: Any) -> Bool {
        if let boolean = value as? Bool { return boolean }
        if let number = value as? NSNumber { return number.intValue > 0 }
        guard let string = value as? String else { return false }
        return ["1", "true", "yes", "charging", "charge", "usb"].contains(string.lowercased())
    }
}
