import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var monitor: BatteryMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            status
            if showsTransferRates {
                Divider()
                transferRates
            }
            Divider()
            settings
            Divider()
            actions
        }
        .padding(16)
        .frame(width: 360)
        .onAppear { monitor.setMenuPresented(true) }
        .onDisappear { monitor.setMenuPresented(false) }
    }

    private var transferRates: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                metricColumn(
                    title: "实时速率",
                    download: monitor.transferRates.formattedDownload,
                    upload: monitor.transferRates.formattedUpload
                )
                Divider()
                    .frame(height: 70)
                metricColumn(
                    title: "今日流量",
                    download: monitor.todayUsage.formattedDownload,
                    upload: monitor.todayUsage.formattedUpload
                )
            }
        }
    }

    private func metricColumn(title: String, download: String, upload: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.bold())
            metricRow(title: "下载", value: download, color: .blue, symbol: "arrow.down.circle.fill")
            metricRow(title: "上传", value: upload, color: .green, symbol: "arrow.up.circle.fill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricRow(title: String, value: String, color: Color, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(title)
                .foregroundStyle(color)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .monospacedDigit()
        }
    }

    private var header: some View {
        HStack {
            StatusIcon(monitor: monitor, size: CGSize(width: 36, height: 21))
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mwifi")
                    .font(.headline)
                Text(primaryStatus)
                    .font(.title2.bold())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(headerDetailTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Image(systemName: headerDetailSymbol)
                    Text(headerDetailValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.secondary.opacity(0.1), in: Capsule())
                .frame(maxWidth: 135, alignment: .trailing)
                if monitor.isRefreshing {
                    ProgressView().controlSize(.mini)
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch monitor.state {
        case .loading:
            Label("正在读取移动 WiFi…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .connected(let reading):
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    reading.isCharging ? "正在充电" : "使用电池供电",
                    systemImage: reading.isCharging ? "bolt.fill" : "wifi"
                )
                Label(monitor.networkName, systemImage: "wifi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastUpdated = monitor.lastUpdated {
                    Text("更新时间：\(lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .networkOnly:
            VStack(alignment: .leading, spacing: 6) {
                Label(monitor.networkName, systemImage: monitor.networkKind == .mobileHotspot ? "personalhotspot" : "wifi")
                    .font(.headline)
                Text("设备电量不可读取")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastUpdated = monitor.lastUpdated {
                    Text("更新时间：\(lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .unavailable(let message):
            VStack(alignment: .leading, spacing: 5) {
                Label("未连接移动 WiFi", systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("提醒设置").font(.subheadline.bold())
            if case .connected = monitor.state {
                Stepper("低电量：\(monitor.warningThreshold)%", value: $monitor.warningThreshold, in: 15...50, step: 5)
                Stepper("紧急电量：\(monitor.emergencyThreshold)%", value: $monitor.emergencyThreshold, in: 5...20, step: 5)
            } else if case .networkOnly = monitor.state {
                Picker("网络类型", selection: Binding(
                    get: { monitor.networkKind },
                    set: { monitor.setNetworkKind($0) }
                )) {
                    ForEach(NetworkKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                Text("当前网络不提供设备电量，因此不会发送电量提醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("登录时启动", isOn: Binding(
                get: { monitor.launchAtLogin },
                set: { monitor.setLaunchAtLogin($0) }
            ))
            if let error = monitor.launchAtLoginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("每 5 分钟自动检查一次")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            Button {
                Task { await monitor.refresh(showActivity: true) }
            } label: {
                Label("立即刷新", systemImage: "arrow.clockwise")
            }
            .disabled(monitor.isRefreshing)

            Button {
                monitor.usageStore.flush()
                openWindow(id: "traffic-details")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("流量详情", systemImage: "chart.bar.xaxis")
            }

            Spacer()

            Button("退出") { NSApplication.shared.terminate(nil) }
        }
    }

    private var primaryStatus: String {
        switch monitor.state {
        case .loading: "读取中"
        case .connected(let reading): "\(reading.percentage)%"
        case .networkOnly: monitor.networkKind.displayName
        case .unavailable: "未连接"
        }
    }

    private var statusColor: Color {
        switch monitor.state {
        case .loading, .unavailable: return .secondary
        case .networkOnly: return .blue
        case .connected(let reading):
            if reading.isCharging { return .green }
            if reading.percentage <= monitor.emergencyThreshold { return .red }
            if reading.percentage <= monitor.warningThreshold { return .orange }
            return .primary
        }
    }

    private var showsTransferRates: Bool {
        switch monitor.state {
        case .connected, .networkOnly: true
        case .loading, .unavailable: false
        }
    }

    private var headerDetailTitle: String {
        if case .connected = monitor.state { return "运营商" }
        return "网络类型"
    }

    private var headerDetailValue: String {
        if case .connected = monitor.state { return monitor.carrierName }
        return monitor.networkKind.displayName
    }

    private var headerDetailSymbol: String {
        if case .connected = monitor.state { return "antenna.radiowaves.left.and.right" }
        return monitor.networkKind == .mobileHotspot ? "personalhotspot" : "wifi"
    }
}
