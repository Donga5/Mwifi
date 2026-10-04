import SwiftUI

@main
struct MwifiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor: BatteryMonitor

    @MainActor
    init() {
        let monitor = BatteryMonitor()
        _monitor = StateObject(wrappedValue: monitor)
        monitor.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
        } label: {
            Label {
                Text(monitor.menuTitle)
            } icon: {
                StatusIcon(monitor: monitor)
            }
        }
        .menuBarExtraStyle(.window)

        Window("流量统计", id: "traffic-details") {
            TrafficDetailsView(store: monitor.usageStore)
        }
        .defaultSize(width: 780, height: 560)
    }
}
