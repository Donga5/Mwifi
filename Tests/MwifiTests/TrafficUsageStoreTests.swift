import XCTest
@testable import Mwifi

@MainActor
final class TrafficUsageStoreTests: XCTestCase {
    func testAggregatesAllNetworksAndFiltersOneNetwork() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = try TrafficUsageStore(path: ":memory:", calendar: calendar)
        let date = Date(timeIntervalSince1970: 1_751_328_000)

        store.record(
            delta: TrafficDelta(uploaded: 200, downloaded: 1_000),
            networkID: "Home", networkName: "Home", networkKind: .regularWiFi, at: date
        )
        store.record(
            delta: TrafficDelta(uploaded: 300, downloaded: 2_000),
            networkID: "iPhone", networkName: "iPhone", networkKind: .mobileHotspot, at: date
        )

        XCTAssertEqual(store.totals(for: date), TrafficTotals(uploaded: 500, downloaded: 3_000))
        XCTAssertEqual(
            store.totals(for: date, networkID: "Home"),
            TrafficTotals(uploaded: 200, downloaded: 1_000)
        )
        store.flush()
        XCTAssertEqual(store.dailyUsage(in: date).first?.totals, TrafficTotals(uploaded: 500, downloaded: 3_000))
        XCTAssertEqual(store.networks().count, 2)
    }

    func testLatestNetworkMetadataWins() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = try TrafficUsageStore(path: ":memory:", calendar: calendar)
        let firstDay = Date(timeIntervalSince1970: 1_751_328_000)
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        store.record(
            delta: TrafficDelta(uploaded: 1, downloaded: 1),
            networkID: "Home", networkName: "Home", networkKind: .regularWiFi, at: firstDay
        )
        store.flush()
        store.record(
            delta: TrafficDelta(uploaded: 1, downloaded: 1),
            networkID: "Home", networkName: "Home", networkKind: .mobileHotspot, at: secondDay
        )
        store.flush()
        XCTAssertEqual(store.networks().first?.kind, .mobileHotspot)
    }
}
