import Foundation

struct TrafficDelta: Equatable, Sendable {
    let uploaded: UInt64
    let downloaded: UInt64

    static let zero = TrafficDelta(uploaded: 0, downloaded: 0)
}

struct TrafficTotals: Equatable, Sendable {
    let uploaded: UInt64
    let downloaded: UInt64

    static let zero = TrafficTotals(uploaded: 0, downloaded: 0)

    var total: UInt64 { uploaded + downloaded }
    var formattedUpload: String { ByteCountFormatter.trafficString(uploaded) }
    var formattedDownload: String { ByteCountFormatter.trafficString(downloaded) }
    var formattedTotal: String { ByteCountFormatter.trafficString(total) }
}

struct DailyTrafficUsage: Identifiable, Equatable, Sendable {
    let date: Date
    let networkID: String
    let networkName: String
    let networkKind: NetworkKind
    let uploaded: UInt64
    let downloaded: UInt64

    var id: String { "\(date.timeIntervalSince1970)-\(networkID)" }
    var totals: TrafficTotals { TrafficTotals(uploaded: uploaded, downloaded: downloaded) }
}

struct TrafficNetwork: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: NetworkKind
}

extension ByteCountFormatter {
    static func trafficString(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .decimal
        formatter.includesUnit = true
        formatter.isAdaptive = true
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }
}
