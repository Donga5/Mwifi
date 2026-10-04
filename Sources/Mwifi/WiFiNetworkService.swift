import CoreLocation
import CoreWLAN
import Foundation

enum NetworkKind: String, CaseIterable, Identifiable, Sendable {
    case mobileHotspot
    case regularWiFi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mobileHotspot: "手机热点"
        case .regularWiFi: "普通 Wi-Fi"
        }
    }
}

struct WiFiNetwork: Equatable, Sendable {
    let ssid: String
    let interfaceName: String
}

enum NetworkClassifier {
    static func inferredKind(for ssid: String) -> NetworkKind {
        let normalized = ssid.lowercased()
        let hotspotMarkers = [
            "iphone", "android", "hotspot", "personal hotspot", "个人热点",
            "手机热点", "huawei", "honor", "xiaomi", "redmi", "oppo", "vivo"
        ]
        return hotspotMarkers.contains(where: normalized.contains) ? .mobileHotspot : .regularWiFi
    }
}

@MainActor
final class WiFiNetworkService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let client = CWWiFiClient.shared()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func currentNetwork() -> WiFiNetwork? {
        guard let interface = client.interface(), interface.serviceActive() else { return nil }
        let interfaceName = interface.interfaceName ?? "en0"
        let ssid = interface.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines)
        return WiFiNetwork(
            ssid: (ssid?.isEmpty == false ? ssid : nil) ?? "未授权读取 Wi-Fi 名称",
            interfaceName: interfaceName
        )
    }
}
