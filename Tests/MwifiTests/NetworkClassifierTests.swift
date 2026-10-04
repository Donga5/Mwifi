import XCTest
@testable import Mwifi

final class NetworkClassifierTests: XCTestCase {
    func testRecognizesCommonPhoneHotspotNames() {
        XCTAssertEqual(NetworkClassifier.inferredKind(for: "Test’s iPhone"), .mobileHotspot)
        XCTAssertEqual(NetworkClassifier.inferredKind(for: "AndroidAP_1234"), .mobileHotspot)
        XCTAssertEqual(NetworkClassifier.inferredKind(for: "我的个人热点"), .mobileHotspot)
    }

    func testTreatsUnrecognizedNetworkAsRegularWiFi() {
        XCTAssertEqual(NetworkClassifier.inferredKind(for: "Office-5G"), .regularWiFi)
    }
}
