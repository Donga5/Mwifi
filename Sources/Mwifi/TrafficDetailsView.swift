import Charts
import SwiftUI

struct TrafficDetailsView: View {
    @ObservedObject var store: TrafficUsageStore
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedNetworkID = "*"
    @State private var usage: [DailyTrafficUsage] = []
    @State private var networks: [TrafficNetwork] = []
    @State private var hoveredDate: Date?

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            toolbar
            summary
            chartSection
            if let error = store.persistenceError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(22)
        .frame(minWidth: 680, minHeight: 480)
        .onAppear {
            store.flush()
            reload()
        }
        .onChange(of: displayedMonth) { _ in reload() }
        .onChange(of: selectedNetworkID) { _ in reload() }
        .onReceive(store.$revision) { _ in reload() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("流量统计")
                    .font(.title2.bold())
                Text("仅统计 Mwifi 运行期间的本机 Wi-Fi 流量")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("网络", selection: $selectedNetworkID) {
                Text("所有网络").tag("*")
                ForEach(networks) { network in
                    Text(network.name).tag(network.id)
                }
            }
            .labelsHidden()
            .frame(width: 190)

            Button { moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .help("上个月")

            Text(monthTitle)
                .font(.headline)
                .monospacedDigit()
                .frame(width: 105)

            Button { moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .help("下个月")
            .disabled(isCurrentMonth)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summaryTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            HStack(spacing: 0) {
                summaryMetric("下载", value: totals.formattedDownload, color: .blue)
                Divider().frame(height: 42)
                summaryMetric("上传", value: totals.formattedUpload, color: .green)
                Divider().frame(height: 42)
                summaryMetric("合计", value: totals.formattedTotal, color: .primary)
            }
        }
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func summaryMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("每日流量")
                    .font(.headline)
                Spacer()
                if let hoveredUsage {
                    Text("\(hoveredUsage.date.formatted(date: .abbreviated, time: .omitted))  下载 \(hoveredUsage.totals.formattedDownload)  上传 \(hoveredUsage.totals.formattedUpload)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if usage.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("本月暂无流量记录")
                        .font(.headline)
                    Text("Mwifi 会在运行期间自动统计当前 Wi-Fi 的流量。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                Chart {
                    ForEach(usage) { item in
                        BarMark(
                            x: .value("日期", item.date, unit: .day),
                            y: .value("流量", item.downloaded)
                        )
                        .foregroundStyle(by: .value("方向", "下载"))

                        BarMark(
                            x: .value("日期", item.date, unit: .day),
                            y: .value("流量", item.uploaded)
                        )
                        .foregroundStyle(by: .value("方向", "上传"))
                    }

                    if let hoveredDate {
                        RuleMark(x: .value("选择日期", hoveredDate, unit: .day))
                            .foregroundStyle(.secondary.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartForegroundStyleScale(["下载": Color.blue, "上传": Color.green])
                .chartLegend(position: .top, alignment: .leading, spacing: 14)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .foregroundStyle(.secondary.opacity(0.25))
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine()
                            .foregroundStyle(.secondary.opacity(0.2))
                        AxisValueLabel {
                            if let bytes = value.as(UInt64.self) {
                                Text(ByteCountFormatter.trafficString(bytes))
                            }
                        }
                    }
                }
                .chartXScale(domain: monthDomain)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let frame = geometry[proxy.plotAreaFrame]
                                    let x = location.x - frame.origin.x
                                    if let date: Date = proxy.value(atX: x) {
                                        hoveredDate = calendar.startOfDay(for: date)
                                    }
                                case .ended:
                                    hoveredDate = nil
                                }
                            }
                    }
                }
                .frame(minHeight: 300)
            }
        }
    }

    private var totals: TrafficTotals {
        usage.reduce(.zero) { result, item in
            TrafficTotals(
                uploaded: result.uploaded &+ item.uploaded,
                downloaded: result.downloaded &+ item.downloaded
            )
        }
    }

    private var hoveredUsage: DailyTrafficUsage? {
        guard let hoveredDate else { return nil }
        return usage.first { calendar.isDate($0.date, inSameDayAs: hoveredDate) }
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.year().month(.abbreviated))
    }

    private var summaryTitle: String {
        guard isCurrentMonth else { return "当月累计（整月）" }
        let components = calendar.dateComponents([.month, .day], from: Date())
        return "本月累计（截至 \(components.month ?? 0) 月 \(components.day ?? 0) 日）"
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private var monthDomain: ClosedRange<Date> {
        let interval = calendar.dateInterval(of: .month, for: displayedMonth)!
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        return interval.start...end
    }

    private func moveMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = next
        hoveredDate = nil
    }

    private func reload() {
        networks = store.networks()
        let filter = selectedNetworkID == "*" ? nil : selectedNetworkID
        usage = store.dailyUsage(in: displayedMonth, networkID: filter)
        if filter != nil, !networks.contains(where: { $0.id == selectedNetworkID }) {
            selectedNetworkID = "*"
        }
    }
}
