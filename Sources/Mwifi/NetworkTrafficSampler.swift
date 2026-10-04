import Darwin
import Foundation

struct NetworkByteCounters: Equatable, Sendable {
    let uploaded: UInt64
    let downloaded: UInt64
}

struct NetworkTrafficSample: Equatable, Sendable {
    let rates: TransferRates
    let delta: TrafficDelta

    static let zero = NetworkTrafficSample(rates: .zero, delta: .zero)
}

final class NetworkTrafficSampler {
    private var previousCounters: [String: (counters: NetworkByteCounters, date: Date)] = [:]

    func sample(interfaceName: String, now: Date = Date()) -> TransferRates {
        sampleWithUsage(interfaceName: interfaceName, now: now).rates
    }

    func sampleWithUsage(interfaceName: String, now: Date = Date()) -> NetworkTrafficSample {
        guard let counters = Self.readCounters(interfaceName: interfaceName) else { return .zero }
        defer { previousCounters[interfaceName] = (counters, now) }

        guard let previous = previousCounters[interfaceName] else { return .zero }
        return Self.calculateSample(
            previous: previous.counters,
            current: counters,
            interval: now.timeIntervalSince(previous.date)
        )
    }

    func reset() {
        previousCounters.removeAll()
    }

    static func calculateRates(
        previous: NetworkByteCounters,
        current: NetworkByteCounters,
        interval: TimeInterval
    ) -> TransferRates {
        calculateSample(previous: previous, current: current, interval: interval).rates
    }

    static func calculateSample(
        previous: NetworkByteCounters,
        current: NetworkByteCounters,
        interval: TimeInterval
    ) -> NetworkTrafficSample {
        guard interval > 0,
              current.uploaded >= previous.uploaded,
              current.downloaded >= previous.downloaded else {
            return .zero
        }
        let delta = TrafficDelta(
            uploaded: current.uploaded - previous.uploaded,
            downloaded: current.downloaded - previous.downloaded
        )
        return NetworkTrafficSample(
            rates: TransferRates(
                uploadBytesPerSecond: Double(delta.uploaded) / interval,
                downloadBytesPerSecond: Double(delta.downloaded) / interval
            ),
            delta: delta
        )
    }

    private static func readCounters(interfaceName: String) -> NetworkByteCounters? {
        let interfaceIndex = if_nametoindex(interfaceName)
        guard interfaceIndex > 0 else { return nil }

        var managementInformationBase: [Int32] = [
            CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(interfaceIndex)
        ]
        var byteCount = 0
        guard sysctl(&managementInformationBase, UInt32(managementInformationBase.count), nil, &byteCount, nil, 0) == 0,
              byteCount >= MemoryLayout<if_msghdr2>.size else {
            return nil
        }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<if_msghdr2>.alignment
        )
        defer { buffer.deallocate() }
        guard sysctl(
            &managementInformationBase,
            UInt32(managementInformationBase.count),
            buffer,
            &byteCount,
            nil,
            0
        ) == 0 else {
            return nil
        }

        var offset = 0
        while offset + MemoryLayout<if_msghdr2>.size <= byteCount {
            let header = buffer.advanced(by: offset)
                .assumingMemoryBound(to: if_msghdr2.self)
                .pointee
            let messageLength = Int(header.ifm_msglen)
            guard messageLength > 0, offset + messageLength <= byteCount else { return nil }
            if header.ifm_type == RTM_IFINFO2,
               UInt32(header.ifm_index) == interfaceIndex {
                return NetworkByteCounters(
                    uploaded: header.ifm_data.ifi_obytes,
                    downloaded: header.ifm_data.ifi_ibytes
                )
            }
            offset += messageLength
        }
        return nil
    }
}
