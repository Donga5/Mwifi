import AppKit
import Foundation
import OSLog
import SwiftUI

@MainActor
final class BatteryMonitor: ObservableObject {
    enum State: Equatable {
        case loading
        case connected(BatteryReading)
        case networkOnly
        case unavailable(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var transferRates: TransferRates = .zero
    @Published private(set) var todayUsage: TrafficTotals = .zero
    @Published private(set) var carrierName = "正在识别"
    @Published private(set) var networkName = "正在识别 Wi-Fi"
    @Published private(set) var networkKind: NetworkKind = .regularWiFi
    @Published var launchAtLogin: Bool
    @Published var launchAtLoginError: String?

    @Published var warningThreshold: Int {
        didSet {
            let normalized = min(max(warningThreshold, 15), 50)
            if warningThreshold != normalized {
                warningThreshold = normalized
                return
            }
            if emergencyThreshold > warningThreshold {
                emergencyThreshold = warningThreshold
            }
            defaults.set(warningThreshold, forKey: "warningThreshold")
        }
    }

    @Published var emergencyThreshold: Int {
        didSet {
            let normalized = min(max(emergencyThreshold, 5), min(20, warningThreshold))
            if emergencyThreshold != normalized {
                emergencyThreshold = normalized
                return
            }
            defaults.set(emergencyThreshold, forKey: "emergencyThreshold")
        }
    }

    private let client: RouterClient
    private let notifications: NotificationService
    private let wifiService: WiFiNetworkService
    private let currentNetwork: () -> WiFiNetwork?
    private let now: () -> Date
    private let trafficSampler: NetworkTrafficSampler
    let usageStore: TrafficUsageStore
    private var pollingTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var policy: NotificationPolicy
    private let defaults: UserDefaults
    private var activeNetwork: WiFiNetwork?
    private var isU30Network: Bool?
    private var lastRouterAttempt: Date?
    private var isRouterRequestInProgress = false
    private var isMenuPresented = false
    private let logger = Logger(subsystem: "com.zhaoguodong.mwifi", category: "BatteryMonitor")

    static let refreshInterval: Duration = .seconds(300)
    static let routerRetryInterval: Duration = .seconds(30)
    static let rateRefreshInterval: Duration = .seconds(1)

    init(
        client: RouterClient = RouterClient(),
        notifications: NotificationService = NotificationService(),
        wifiService: WiFiNetworkService? = nil,
        trafficSampler: NetworkTrafficSampler = NetworkTrafficSampler(),
        usageStore: TrafficUsageStore? = nil,
        defaults: UserDefaults = .standard,
        currentNetwork: (() -> WiFiNetwork?)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.client = client
        self.notifications = notifications
        let wifi = wifiService ?? WiFiNetworkService()
        self.wifiService = wifi
        self.currentNetwork = currentNetwork ?? { wifi.currentNetwork() }
        self.now = now
        self.trafficSampler = trafficSampler
        self.usageStore = usageStore ?? .shared
        self.defaults = defaults
        self.launchAtLogin = LaunchAtLoginService.isEnabled
        self.warningThreshold = defaults.object(forKey: "warningThreshold") as? Int ?? 20
        self.emergencyThreshold = defaults.object(forKey: "emergencyThreshold") as? Int ?? 10
        self.policy = NotificationPolicy(
            warningSent: defaults.bool(forKey: "warningNotificationSent"),
            emergencySent: defaults.bool(forKey: "emergencyNotificationSent"),
            chargingTargetSent: defaults.bool(forKey: "chargingTargetNotificationSent")
        )
        self.todayUsage = self.usageStore.todayTotals()
    }

    deinit {
        pollingTask?.cancel()
        persistenceTask?.cancel()
    }

    var menuTitle: String {
        switch state {
        case .loading: "--%"
        case .connected(let reading): "\(reading.percentage)%"
        case .networkOnly: transferRates.formattedDownload
        case .unavailable: "离线"
        }
    }

    func statusImage(foregroundColor: NSColor = .labelColor) -> NSImage {
        switch state {
        case .loading:
            return BatteryIcon.image(percentage: 0, isCharging: false, foregroundColor: foregroundColor)
        case .unavailable:
            return NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: "离线")!
        case .networkOnly:
            return NSImage(
                systemSymbolName: networkKind == .mobileHotspot ? "personalhotspot" : "wifi",
                accessibilityDescription: networkKind == .mobileHotspot ? "手机热点" : "Wi-Fi"
            )!
        case .connected(let reading):
            return BatteryIcon.image(percentage: reading.percentage, isCharging: reading.isCharging, foregroundColor: foregroundColor)
        }
    }

    func start() {
        guard pollingTask == nil else { return }
        persistenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: TrafficUsageStore.flushInterval)
                guard !Task.isCancelled, let self else { break }
                usageStore.flush()
            }
        }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await notifications.requestAuthorization()
            } catch {
                logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
            wifiService.requestAuthorizationIfNeeded()
            configureDefaultLaunchAtLoginIfNeeded()
            await refresh(showActivity: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.rateRefreshInterval)
                guard !Task.isCancelled else { break }
                await refresh(showActivity: false)
            }
        }
    }

    func setMenuPresented(_ isPresented: Bool) {
        isMenuPresented = isPresented
        if isPresented { Task { await refresh(showActivity: false) } }
    }

    func refresh(showActivity: Bool = true) async {
        guard !isRefreshing else { return }
        usageStore.flushIfNeeded()
        if showActivity { isRefreshing = true }
        defer {
            if showActivity { isRefreshing = false }
        }

        guard let network = currentNetwork() else {
            usageStore.flush()
            activeNetwork = nil
            isU30Network = nil
            lastRouterAttempt = nil
            trafficSampler.reset()
            transferRates = .zero
            carrierName = "无服务"
            networkName = "未连接 Wi-Fi"
            state = .unavailable("Mac 当前未连接 Wi-Fi")
            return
        }

        if activeNetwork != network {
            usageStore.flush()
            activeNetwork = network
            isU30Network = nil
            lastRouterAttempt = nil
            trafficSampler.reset()
        }

        networkName = network.ssid
        networkKind = savedKind(for: network.ssid) ?? NetworkClassifier.inferredKind(for: network.ssid)
        let trafficSample = trafficSampler.sampleWithUsage(interfaceName: network.interfaceName)
        transferRates = trafficSample.rates
        usageStore.record(
            delta: trafficSample.delta,
            networkID: network.ssid,
            networkName: network.ssid,
            networkKind: networkKind
        )
        todayUsage = usageStore.todayTotals()
        lastUpdated = Date()

        let routerInterval = isU30Network == true ? Self.refreshInterval : Self.routerRetryInterval
        let routerRefreshDue = lastRouterAttempt.map {
            now().timeIntervalSince($0) >= routerInterval.timeInterval
        } ?? true
        let shouldFetchRouter = showActivity || routerRefreshDue || (isU30Network == true && isMenuPresented)

        if shouldFetchRouter && !isRouterRequestInProgress {
            isRouterRequestInProgress = true
            lastRouterAttempt = now()
            defer { isRouterRequestInProgress = false }
            do {
                let snapshot = try await client.fetchStatus()
                guard activeNetwork == network else { return }
                isU30Network = true
                state = .connected(snapshot.battery)
                transferRates = snapshot.transferRates
                carrierName = snapshot.carrierName ?? "运营商未知"
                await evaluateNotification(for: snapshot.battery)
                return
            } catch {
                guard activeNetwork == network else { return }
                if isU30Network == nil { isU30Network = false }
            }
        }

        if isU30Network != true {
            state = .networkOnly
            carrierName = networkKind == .mobileHotspot ? "手机热点" : "非蜂窝设备"
        }
    }

    func setNetworkKind(_ kind: NetworkKind) {
        guard let ssid = activeNetwork?.ssid else { return }
        var saved = defaults.dictionary(forKey: "networkKindBySSID") as? [String: String] ?? [:]
        saved[ssid] = kind.rawValue
        defaults.set(saved, forKey: "networkKindBySSID")
        networkKind = kind
        carrierName = kind == .mobileHotspot ? "手机热点" : "非蜂窝设备"
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLogin = LaunchAtLoginService.isEnabled
            defaults.set(true, forKey: "didConfigureLaunchAtLogin")
            launchAtLoginError = nil
        } catch {
            launchAtLogin = LaunchAtLoginService.isEnabled
            launchAtLoginError = error.localizedDescription
        }
    }

    private func configureDefaultLaunchAtLoginIfNeeded() {
        guard !defaults.bool(forKey: "didConfigureLaunchAtLogin"),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else {
            return
        }
        do {
            try LaunchAtLoginService.setEnabled(true)
            launchAtLogin = LaunchAtLoginService.isEnabled
            defaults.set(true, forKey: "didConfigureLaunchAtLogin")
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }

    private func evaluateNotification(for reading: BatteryReading) async {
        let safeEmergencyThreshold = min(emergencyThreshold, warningThreshold)
        let alert = policy.evaluate(
            percentage: reading.percentage,
            isCharging: reading.isCharging,
            warningThreshold: warningThreshold,
            emergencyThreshold: safeEmergencyThreshold
        )
        defaults.set(policy.warningSent, forKey: "warningNotificationSent")
        defaults.set(policy.emergencySent, forKey: "emergencyNotificationSent")
        defaults.set(policy.chargingTargetSent, forKey: "chargingTargetNotificationSent")
        guard let alert else { return }

        do {
            try await notifications.send(alert)
            policy.recordDelivery(of: alert)
            defaults.set(policy.warningSent, forKey: "warningNotificationSent")
            defaults.set(policy.emergencySent, forKey: "emergencyNotificationSent")
            defaults.set(policy.chargingTargetSent, forKey: "chargingTargetNotificationSent")
        } catch {
            logger.error("Notification delivery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func savedKind(for ssid: String) -> NetworkKind? {
        let saved = defaults.dictionary(forKey: "networkKindBySSID") as? [String: String]
        return saved?[ssid].flatMap(NetworkKind.init(rawValue:))
    }
}

struct StatusIcon: View {
    @ObservedObject var monitor: BatteryMonitor
    var size = CGSize(width: 24, height: 14)
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: monitor.statusImage(foregroundColor: colorScheme == .dark ? .white : .black))
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
    }
}

enum BatteryIcon {
    static func image(
        percentage: Int,
        isCharging: Bool,
        foregroundColor: NSColor = .labelColor
    ) -> NSImage {
        let fraction = CGFloat(min(max(percentage, 0), 100)) / 100
        let image = NSImage(size: NSSize(width: 24, height: 14), flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true
            foregroundColor.withAlphaComponent(0.85).setStroke()
            let outline = NSBezierPath(
                roundedRect: NSRect(x: 0.5, y: 1.5, width: 20, height: 11),
                xRadius: 2.5, yRadius: 2.5
            )
            outline.lineWidth = 1
            outline.stroke()
            foregroundColor.withAlphaComponent(0.5).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 22, y: 5, width: 1.5, height: 4),
                xRadius: 0.75, yRadius: 0.75
            ).fill()

            let fillWidth = 17 * fraction
            if fillWidth > 0 {
                (percentage < 30 ? NSColor.systemYellow : foregroundColor).setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: 2, y: 3, width: fillWidth, height: 8),
                    xRadius: min(1, fillWidth / 2), yRadius: 1
                ).fill()
            }

            if isCharging {
                let bolt = NSBezierPath()
                bolt.move(to: NSPoint(x: 12, y: 10.5))
                bolt.line(to: NSPoint(x: 8.7, y: 6.4))
                bolt.line(to: NSPoint(x: 11, y: 6.4))
                bolt.line(to: NSPoint(x: 10, y: 3.5))
                bolt.line(to: NSPoint(x: 14.5, y: 8))
                bolt.line(to: NSPoint(x: 11.9, y: 8))
                bolt.close()

                // Keep a narrow clear halo around the bolt without touching the outline.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSColor.black.setStroke()
                bolt.lineWidth = 1.4
                bolt.lineJoinStyle = .round
                bolt.stroke()
                NSGraphicsContext.restoreGraphicsState()
                foregroundColor.setFill()
                bolt.fill()
            }
            return true
        }
        // Template images discard color, so preserve the yellow fill and resolve the
        // outline color from the host view's color scheme in StatusIcon.
        image.isTemplate = false
        image.accessibilityDescription = "电量 \(percentage)%" + (isCharging ? "，正在充电" : "")
        return image
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
