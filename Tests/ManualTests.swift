import Foundation

@main @MainActor
enum ManualTests {
    static func main() async throws {
        try parserTests()
        policyTests()
        classifierTests()
        trafficRateTests()
        try trafficUsageStoreTests()
        try await batteryMonitorTests()
        print("All Mwifi tests passed")
    }

    private static func batteryMonitorTests() async throws {
        let batteryData = Data(#"{"battery_vol_percent":"89","battery_charging":"0","network_provider_fullname":"中国移动"}"#.utf8)
        let network = WiFiNetwork(ssid: "ZTE_TestNetwork", interfaceName: "mwifi-test")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RouterRequestStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let suite = "MwifiTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        var activeNetwork: WiFiNetwork? = network
        func makeMonitor() throws -> BatteryMonitor {
            BatteryMonitor(
                client: RouterClient(session: session),
                usageStore: try TrafficUsageStore(path: ":memory:"),
                defaults: defaults,
                currentNetwork: { activeNetwork },
                now: { date }
            )
        }

        RouterRequestStub.reset([.failure(URLError(.timedOut)), .success(batteryData)])
        let manual = try makeMonitor()
        await manual.refresh(showActivity: false)
        precondition(manual.state == .networkOnly)
        await manual.refresh()
        FileHandle.standardOutput.write(Data("Manual refresh after first timeout: \(manual.state), requests: \(RouterRequestStub.requestCount)\n".utf8))
        precondition(manual.state == .connected(BatteryReading(percentage: 89, isCharging: false)),
                     "Manual refresh must recover after a failed first probe")
        precondition(manual.carrierName == "中国移动")
        precondition(manual.menuTitle == "89%")
        precondition(RouterRequestStub.requestCount == 2)

        RouterRequestStub.reset([.failure(URLError(.timedOut)), .success(batteryData)])
        let automatic = try makeMonitor()
        await automatic.refresh(showActivity: false)
        await automatic.refresh(showActivity: false)
        precondition(RouterRequestStub.requestCount == 1, "Do not retry every traffic-sampling tick")
        date = date.addingTimeInterval(30)
        await automatic.refresh(showActivity: false)
        precondition(automatic.state == .connected(BatteryReading(percentage: 89, isCharging: false)),
                     "Automatic retry must recover without changing Wi-Fi")
        precondition(RouterRequestStub.requestCount == 2)
        date = date.addingTimeInterval(1)
        await automatic.refresh(showActivity: false)
        precondition(RouterRequestStub.requestCount == 2, "Keep the five-minute cadence after success")
        date = date.addingTimeInterval(300)
        RouterRequestStub.reset([.success(batteryData)])
        await automatic.refresh(showActivity: false)
        precondition(RouterRequestStub.requestCount == 1)

        RouterRequestStub.reset([.failure(URLError(.cannotConnectToHost)), .success(batteryData)])
        let switched = try makeMonitor()
        await switched.refresh(showActivity: false)
        activeNetwork = WiFiNetwork(ssid: "ZTE_other", interfaceName: "mwifi-test")
        await switched.refresh(showActivity: false)
        precondition(switched.state == .connected(BatteryReading(percentage: 89, isCharging: false)),
                     "Changing networks must reset the retry delay")
        activeNetwork = nil
        await switched.refresh(showActivity: false)
        precondition(switched.state == .unavailable("Mac 当前未连接 Wi-Fi"))
        print("Battery monitor regressions passed: manual retry, automatic recovery, cadence, network reset")
    }

    private static func parserTests() throws {
        let u30Data = Data(#"{"battery_vol_percent":"36","battery_charging":"0"}"#.utf8)
        let u30Reading = try RouterResponseParser.parse(u30Data).battery
        precondition(u30Reading == BatteryReading(percentage: 36, isCharging: false))

        let fallbackData = Data(#"{"battery_pers":"82%","external_charging_flag":"1"}"#.utf8)
        let fallbackReading = try RouterResponseParser.parse(fallbackData).battery
        precondition(fallbackReading == BatteryReading(percentage: 82, isCharging: true))

        let invalidData = Data(#"{"battery_vol_percent":"120"}"#.utf8)
        do {
            _ = try RouterResponseParser.parse(invalidData)
            preconditionFailure("Invalid percentages must be rejected")
        } catch RouterResponseParser.ParseError.invalidPercentage {
            // Expected.
        }

        let ratesData = Data(#"{"battery_vol_percent":"36","realtime_tx_thrpt":"180000","realtime_rx_thrpt":"2350000"}"#.utf8)
        let rates = try RouterResponseParser.parse(ratesData).transferRates
        precondition(rates.formattedUpload == "0.18 MB/s")
        precondition(rates.formattedDownload == "2.35 MB/s")

        let u30RatesData = Data(#"{"flux_realtime_tx_thrpt":810,"flux_realtime_rx_thrpt":17278,"battery_vol_percent":"55"}"#.utf8)
        let u30Rates = try RouterResponseParser.parse(u30RatesData).transferRates
        precondition(u30Rates.uploadBytesPerSecond == 810)
        precondition(u30Rates.downloadBytesPerSecond == 17_278)
        precondition(u30Rates.formattedUpload == "<0.01 MB/s")
        precondition(u30Rates.formattedDownload == "0.02 MB/s")

        let carrierData = Data(#"{"sim_spn_name_data":"","network_provider_fullname":"中国移动","network_provider":"中国移动","battery_vol_percent":"53"}"#.utf8)
        let carrierName = try RouterResponseParser.parse(carrierData).carrierName
        precondition(carrierName == "中国移动")
    }

    private static func policyTests() {
        var policy = NotificationPolicy(warningSent: false, emergencySent: false, chargingTargetSent: false)
        precondition(policy.evaluate(percentage: 20, isCharging: false, warningThreshold: 20, emergencyThreshold: 10) == .warning(20))
        precondition(policy.evaluate(percentage: 20, isCharging: false, warningThreshold: 20, emergencyThreshold: 10) == .warning(20))
        policy.recordDelivery(of: .warning(20))
        precondition(policy.evaluate(percentage: 18, isCharging: false, warningThreshold: 20, emergencyThreshold: 10) == nil)
        precondition(policy.evaluate(percentage: 10, isCharging: false, warningThreshold: 20, emergencyThreshold: 10) == .emergency(10))
        policy.recordDelivery(of: .emergency(10))
        precondition(policy.evaluate(percentage: 8, isCharging: false, warningThreshold: 20, emergencyThreshold: 10) == nil)
        precondition(policy.evaluate(percentage: 30, isCharging: false, warningThreshold: 20, emergencyThreshold: 10) == nil)
        precondition(policy.evaluate(percentage: 19, isCharging: false, warningThreshold: 20, emergencyThreshold: 10) == .warning(19))

        var jumpPolicy = NotificationPolicy(warningSent: false, emergencySent: false, chargingTargetSent: false)
        precondition(jumpPolicy.evaluate(percentage: 7, isCharging: false, warningThreshold: 20, emergencyThreshold: 10) == .emergency(7))
        jumpPolicy.recordDelivery(of: .emergency(7))
        precondition(jumpPolicy.evaluate(percentage: 7, isCharging: false, warningThreshold: 20, emergencyThreshold: 10) == nil)

        var chargingPolicy = NotificationPolicy(warningSent: false, emergencySent: false, chargingTargetSent: false)
        precondition(chargingPolicy.evaluate(percentage: 59, isCharging: true, warningThreshold: 20, emergencyThreshold: 10) == nil)
        precondition(chargingPolicy.evaluate(percentage: 60, isCharging: true, warningThreshold: 20, emergencyThreshold: 10) == .chargingTargetReached(60))
        precondition(chargingPolicy.evaluate(percentage: 60, isCharging: true, warningThreshold: 20, emergencyThreshold: 10) == .chargingTargetReached(60))
        chargingPolicy.recordDelivery(of: .chargingTargetReached(60))
        precondition(chargingPolicy.evaluate(percentage: 80, isCharging: true, warningThreshold: 20, emergencyThreshold: 10) == nil)
        precondition(chargingPolicy.evaluate(percentage: 80, isCharging: false, warningThreshold: 20, emergencyThreshold: 10) == nil)
        precondition(chargingPolicy.evaluate(percentage: 65, isCharging: true, warningThreshold: 20, emergencyThreshold: 10) == .chargingTargetReached(65))
    }

    private static func classifierTests() {
        precondition(NetworkClassifier.inferredKind(for: "Test's iPhone") == .mobileHotspot)
        precondition(NetworkClassifier.inferredKind(for: "AndroidAP_1234") == .mobileHotspot)
        precondition(NetworkClassifier.inferredKind(for: "Office-5G") == .regularWiFi)
    }

    private static func trafficRateTests() {
        let rates = NetworkTrafficSampler.calculateRates(
            previous: NetworkByteCounters(uploaded: 1_000, downloaded: 2_000),
            current: NetworkByteCounters(uploaded: 501_000, downloaded: 2_002_000),
            interval: 2
        )
        precondition(rates.uploadBytesPerSecond == 250_000)
        precondition(rates.downloadBytesPerSecond == 1_000_000)
        precondition(rates.formattedUpload == "0.25 MB/s")
        precondition(rates.formattedDownload == "1.00 MB/s")

        let resetRates = NetworkTrafficSampler.calculateRates(
            previous: NetworkByteCounters(uploaded: 10, downloaded: 10),
            current: NetworkByteCounters(uploaded: 1, downloaded: 1),
            interval: 1
        )
        precondition(resetRates == .zero)

        let beyond32Bit = NetworkTrafficSampler.calculateSample(
            previous: NetworkByteCounters(uploaded: 4_294_967_000, downloaded: 8_589_934_000),
            current: NetworkByteCounters(uploaded: 4_295_968_000, downloaded: 8_592_934_000),
            interval: 1
        )
        precondition(beyond32Bit.delta == TrafficDelta(uploaded: 1_001_000, downloaded: 3_000_000))
    }

    private static func trafficUsageStoreTests() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = try TrafficUsageStore(path: ":memory:", calendar: calendar)
        let firstDay = Date(timeIntervalSince1970: 1_751_328_000) // 2025-07-01 UTC
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!

        store.record(
            delta: TrafficDelta(uploaded: 200, downloaded: 1_000),
            networkID: "Home",
            networkName: "Home",
            networkKind: .regularWiFi,
            at: firstDay
        )
        store.record(
            delta: TrafficDelta(uploaded: 300, downloaded: 2_000),
            networkID: "iPhone",
            networkName: "iPhone",
            networkKind: .mobileHotspot,
            at: firstDay
        )
        precondition(store.totals(for: firstDay) == TrafficTotals(uploaded: 500, downloaded: 3_000))
        precondition(store.totals(for: firstDay, networkID: "Home") == TrafficTotals(uploaded: 200, downloaded: 1_000))
        // Persist the earlier day's metadata before the later day's update.
        // A single dictionary batch has no chronological write order.
        store.flush()

        store.record(
            delta: TrafficDelta(uploaded: 100, downloaded: 500),
            networkID: "Home",
            networkName: "Home",
            networkKind: .mobileHotspot,
            at: secondDay
        )
        store.flush()

        let allUsage = store.dailyUsage(in: firstDay)
        precondition(allUsage.count == 2)
        precondition(allUsage[0].totals == TrafficTotals(uploaded: 500, downloaded: 3_000))
        precondition(allUsage[1].totals == TrafficTotals(uploaded: 100, downloaded: 500))

        let homeUsage = store.dailyUsage(in: firstDay, networkID: "Home")
        precondition(homeUsage.count == 2)
        let networks = store.networks()
        precondition(networks.count == 2)
        precondition(networks.first(where: { $0.id == "Home" })?.kind == .mobileHotspot)
    }
}

private final class RouterRequestStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [Result<Data, URLError>] = []
    nonisolated(unsafe) private static var count = 0

    static var requestCount: Int { lock.withLock { count } }

    static func reset(_ results: [Result<Data, URLError>]) {
        lock.withLock {
            responses = results
            count = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let result = Self.lock.withLock {
            Self.count += 1
            return Self.responses.isEmpty ? .failure(URLError(.cannotConnectToHost)) : Self.responses.removeFirst()
        }
        switch result {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .success(let data):
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}
