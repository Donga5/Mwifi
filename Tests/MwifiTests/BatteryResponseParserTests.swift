import Foundation
import XCTest
@testable import Mwifi

final class BatteryResponseParserTests: XCTestCase {
    func testParsesU30AirBatteryResponse() throws {
        let data = Data(#"{"battery_vol_percent":"36","battery_charging":"0"}"#.utf8)
        XCTAssertEqual(
            try RouterResponseParser.parse(data).battery,
            BatteryReading(percentage: 36, isCharging: false)
        )
    }

    func testFallsBackToBatteryPersAndChargingFlag() throws {
        let data = Data(#"{"battery_pers":"82%","external_charging_flag":"1"}"#.utf8)
        XCTAssertEqual(
            try RouterResponseParser.parse(data).battery,
            BatteryReading(percentage: 82, isCharging: true)
        )
    }

    func testRejectsInvalidPercentage() {
        let data = Data(#"{"battery_vol_percent":"120"}"#.utf8)
        XCTAssertThrowsError(try RouterResponseParser.parse(data))
    }

    func testParsesTransferRatesAsBytesPerSecond() throws {
        let data = Data(#"{"battery_vol_percent":"36","realtime_tx_thrpt":"180000","realtime_rx_thrpt":"2350000"}"#.utf8)
        let rates = try RouterResponseParser.parse(data).transferRates
        XCTAssertEqual(rates.formattedUpload, "0.18 MB/s")
        XCTAssertEqual(rates.formattedDownload, "2.35 MB/s")
    }

    func testParsesU30AirFluxTransferRateFields() throws {
        let data = Data(#"{"flux_realtime_tx_thrpt":810,"flux_realtime_rx_thrpt":17278,"battery_vol_percent":"55"}"#.utf8)
        let rates = try RouterResponseParser.parse(data).transferRates
        XCTAssertEqual(rates.uploadBytesPerSecond, 810)
        XCTAssertEqual(rates.downloadBytesPerSecond, 17_278)
        XCTAssertEqual(rates.formattedUpload, "<0.01 MB/s")
        XCTAssertEqual(rates.formattedDownload, "0.02 MB/s")
    }

    func testParsesU30AirChineseCarrierName() throws {
        let data = Data(#"{"sim_spn_name_data":"","network_provider_fullname":"中国移动","network_provider":"中国移动","battery_vol_percent":"53"}"#.utf8)
        XCTAssertEqual(try RouterResponseParser.parse(data).carrierName, "中国移动")
    }

    func testFallsBackToNetworkProviderAndIgnoresBlankNames() throws {
        let data = Data(#"{"network_provider_fullname":"  ","network_provider":"中国联通","battery_vol_percent":"53"}"#.utf8)
        XCTAssertEqual(try RouterResponseParser.parse(data).carrierName, "中国联通")
    }
}
