import XCTest
@testable import Mwifi

final class NetworkTrafficSamplerTests: XCTestCase {
    func testCalculatesUploadAndDownloadRatesFromCounterDeltas() {
        let rates = NetworkTrafficSampler.calculateRates(
            previous: NetworkByteCounters(uploaded: 1_000, downloaded: 2_000),
            current: NetworkByteCounters(uploaded: 501_000, downloaded: 2_002_000),
            interval: 2
        )

        XCTAssertEqual(rates.uploadBytesPerSecond, 250_000)
        XCTAssertEqual(rates.downloadBytesPerSecond, 1_000_000)
        XCTAssertEqual(rates.formattedUpload, "0.25 MB/s")
        XCTAssertEqual(rates.formattedDownload, "1.00 MB/s")
    }

    func testCounterResetReturnsZeroInsteadOfNegativeRate() {
        let rates = NetworkTrafficSampler.calculateRates(
            previous: NetworkByteCounters(uploaded: 10, downloaded: 10),
            current: NetworkByteCounters(uploaded: 1, downloaded: 1),
            interval: 1
        )
        XCTAssertEqual(rates, .zero)
    }

    func testCountersContinueBeyondUInt32Range() {
        let sample = NetworkTrafficSampler.calculateSample(
            previous: NetworkByteCounters(uploaded: 4_294_967_000, downloaded: 8_589_934_000),
            current: NetworkByteCounters(uploaded: 4_295_968_000, downloaded: 8_592_934_000),
            interval: 1
        )
        XCTAssertEqual(sample.delta, TrafficDelta(uploaded: 1_001_000, downloaded: 3_000_000))
    }
}
