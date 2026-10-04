import Foundation

struct RouterClient: Sendable {
    enum ClientError: LocalizedError {
        case invalidURL
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: "设备地址无效"
            case .unexpectedResponse: "无法连接移动 WiFi"
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = RouterClient.makeSession()) {
        self.session = session
    }

    func fetchStatus() async throws -> RouterSnapshot {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "192.168.0.1"
        components.path = "/goform/goform_get_cmd_process"
        components.queryItems = [
            URLQueryItem(name: "isTest", value: "false"),
            URLQueryItem(name: "multi_data", value: "1"),
            URLQueryItem(
                name: "cmd",
                value: "battery_vol_percent,battery_pers,battery_charging,battery_charg_type,external_charging_flag,flux_realtime_tx_thrpt,flux_realtime_rx_thrpt,realtime_tx_thrpt,realtime_rx_thrpt,network_provider_fullname,network_provider,sim_spn_name_data,spn_name_data"
            ),
            URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1_000)))
        ]
        guard let url = components.url else { throw ClientError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("http://192.168.0.1/index.html", forHTTPHeaderField: "Referer")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Mwifi/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ClientError.unexpectedResponse
        }
        return try RouterResponseParser.parse(data)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }
}
