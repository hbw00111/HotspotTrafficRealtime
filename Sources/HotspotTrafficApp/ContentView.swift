import Charts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                liveTraffic
                overview
                if let error = model.collectorStatus.errorMessage {
                    notice(icon: "exclamationmark.triangle.fill", color: .orange, text: error)
                }
                if model.summary.sampleCount == 0 {
                    emptyState
                } else {
                    dashboard
                    details
                    if !model.summary.tunnels.isEmpty {
                        tunnelDetails
                    }
                }
            }
            .padding(28)
        }
        .frame(minWidth: 980, minHeight: 700)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private var liveTraffic: some View {
        Surface {
            HStack(spacing: 20) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(model.collectorStatus.isHealthy ? .green : .secondary)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        sectionKicker("实时速率")
                        Text("热点当前上下行")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                }

                Spacer()

                LiveRateTile(
                    title: "下载",
                    value: liveSpeed(model.collectorStatus.downloadBytesPerSecond),
                    icon: "arrow.down",
                    tint: .blue
                )
                Divider().frame(height: 42)
                LiveRateTile(
                    title: "上传",
                    value: liveSpeed(model.collectorStatus.uploadBytesPerSecond),
                    icon: "arrow.up",
                    tint: .orange
                )
                Divider().frame(height: 42)
                LiveRateTile(
                    title: "合计",
                    value: liveSpeed(model.collectorStatus.downloadBytesPerSecond + model.collectorStatus.uploadBytesPerSecond),
                    icon: "arrow.up.arrow.down",
                    tint: .green
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 42, height: 42)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text("PERSONAL HOTSPOT")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.green)
                Text("热点流量")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
            }

            Spacer()

            HStack(spacing: 9) {
                    Circle()
                    .fill(collectorStateColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(collectorStateTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Text(collectorRefreshLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Button(model.collectorStatus.isRunning ? "停止采集" : "启动采集") {
                model.toggleCollector()
            }
            .buttonStyle(.borderedProminent)
            .tint(model.collectorStatus.isRunning ? .secondary : .green)
        }
    }

    private var overview: some View {
        Surface {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        sectionKicker("流量总览")
                        Text(rangeTitle)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text(model.summary.lastSample.map { "最近采样 \(dateTime($0))" } ?? "还没有本地采样")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    rangeControls
                }

                Divider()

                HStack(spacing: 0) {
                    MetricTile(title: "总流量", value: bytes(model.summary.totalBytes), detail: model.summary.apps.first.map { "最高 · \($0.process)" } ?? "下载与上传", accent: .green)
                    Divider().frame(height: 58)
                    MetricTile(title: "下载", value: bytes(model.summary.bytesIn), detail: "接收数据", accent: .blue)
                    Divider().frame(height: 58)
                    MetricTile(title: "上传", value: bytes(model.summary.bytesOut), detail: "发送数据", accent: .orange)
                    Divider().frame(height: 58)
                    MetricTile(title: "活跃应用", value: "\(model.summary.apps.count)", detail: "\(model.summary.sampleCount) 条采样", accent: .purple)
                }

                if model.summary.tunnelBytes > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("已分离隧道传输 \(bytes(model.summary.tunnelBytes)) · \(model.summary.tunnelProcesses.joined(separator: "、"))")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var rangeControls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Picker("时间范围", selection: $model.selectedRange) {
                ForEach(TrafficRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 310)

            if model.selectedRange == .custom {
                HStack(spacing: 8) {
                    DatePicker("开始", selection: $model.customFrom, displayedComponents: .date)
                    DatePicker("结束", selection: $model.customTo, displayedComponents: .date)
                    Button("应用") { model.applyCustomRange() }
                        .buttonStyle(.bordered)
                }
                .font(.system(size: 11))
            }
        }
    }

    private var dashboard: some View {
        HStack(alignment: .top, spacing: 18) {
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionKicker("时间趋势")
                            Text(model.selectedRange == .today ? "今天的流量分布" : "每天的流量走向")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        Spacer()
                        Text(model.selectedRange == .today ? "按小时" : "按天")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if model.summary.points.allSatisfy({ $0.totalBytes == 0 }) {
                        emptyChart
                    } else {
                        trafficChart
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionKicker("应用排行")
                            Text("谁用得最多")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        Spacer()
                        Text("Top 5")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    appRanking
                }
            }
            .frame(width: 330)
        }
    }

    private var trafficChart: some View {
        Chart(model.summary.points) { point in
            AreaMark(
                x: .value("时间", point.date),
                y: .value("流量", point.totalBytes)
            )
            .foregroundStyle(Color.green.opacity(0.16))
            LineMark(
                x: .value("时间", point.date),
                y: .value("流量", point.totalBytes)
            )
            .foregroundStyle(.green)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            PointMark(
                x: .value("时间", point.date),
                y: .value("流量", point.totalBytes)
            )
            .foregroundStyle(.green)
            .symbolSize(24)
        }
        .chartYScale(domain: 0...max(model.summary.points.map(\.totalBytes).max() ?? 1, 1))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: model.selectedRange == .today ? 6 : 7)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisTick().foregroundStyle(.secondary)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(model.selectedRange == .today ? dateTime(date, timeOnly: true) : dateLabel(date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let number = value.as(Int64.self) { Text(bytes(number, compact: true)) }
                }
            }
        }
        .frame(height: 278)
    }

    private var appRanking: some View {
        VStack(alignment: .leading, spacing: 17) {
            if model.summary.apps.isEmpty {
                Text("还没有应用流量")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, minHeight: 190, alignment: .center)
            } else {
                let topTotal = max(model.summary.apps.map(\.totalBytes).reduce(0, +), 1)
                ForEach(model.summary.apps.prefix(5)) { app in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Circle().fill(appColor(app.colorIndex)).frame(width: 8, height: 8)
                            Text(app.process).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(app.category).font(.system(size: 10)).foregroundStyle(.secondary)
                            Spacer()
                            Text(bytes(app.totalBytes, compact: true)).font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        ProgressView(value: Double(app.totalBytes), total: Double(topTotal))
                            .tint(appColor(app.colorIndex))
                    }
                }
            }
        }
    }

    private var details: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionKicker("明细")
                        Text("应用流量明细")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Text("\(model.summary.apps.count) 个应用")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Table(model.summary.apps) {
                    TableColumn("应用") { app in
                        HStack(spacing: 8) {
                            Circle().fill(appColor(app.colorIndex)).frame(width: 7, height: 7)
                            Text(app.process).fontWeight(.semibold)
                        }
                    }
                    TableColumn("类型") { app in Text(app.category).foregroundStyle(.secondary) }
                    TableColumn("总流量") { app in Text(bytes(app.totalBytes)).monospacedDigit() }
                    TableColumn("下载") { app in Text(bytes(app.bytesIn)).monospacedDigit() }
                    TableColumn("上传") { app in Text(bytes(app.bytesOut)).monospacedDigit() }
                    TableColumn("活跃天数") { app in Text("\(app.activeDays) 天").monospacedDigit() }
                    TableColumn("最近记录") { app in Text(app.lastSeen.map { dateTime($0) } ?? "--").foregroundStyle(.secondary) }
                }
                .frame(minHeight: 220)
            }
        }
    }

    private var tunnelDetails: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionKicker("隧道流量")
                        Text("小火箭与传输层")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Text("单独统计，不混入应用排行")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                ForEach(model.summary.tunnels) { tunnel in
                    HStack(spacing: 14) {
                        Circle()
                            .fill(appColor(tunnel.colorIndex))
                            .frame(width: 8, height: 8)
                        Text(tunnel.process)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 180, alignment: .leading)
                        Text(tunnel.category)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(bytes(tunnel.totalBytes))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            Text("↓ \(bytes(tunnel.bytesIn, compact: true))  ↑ \(bytes(tunnel.bytesOut, compact: true))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    if tunnel.id != model.summary.tunnels.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        Surface {
            VStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                Text("还没有采样记录")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("连接热点后保持采集，数据会按进程写入本机历史。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        }
    }

    private var emptyChart: some View {
        Text("这个时间范围还没有流量")
            .foregroundStyle(.secondary)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, minHeight: 278)
    }

    private func notice(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 12))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sectionKicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(.green)
    }

    private var rangeTitle: String {
        switch model.selectedRange {
        case .today: return "今天的应用流量汇总"
        case .sevenDays: return "最近 7 天的应用流量汇总"
        case .thirtyDays: return "最近 30 天的应用流量汇总"
        case .custom: return "自定义范围的应用流量汇总"
        }
    }

    private func appColor(_ index: Int) -> Color {
        [.green, .blue, .orange, .purple, .red, .gray, .yellow][index % 7]
    }

    private func bytes(_ value: Int64, compact: Bool = false) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = Double(max(value, 0))
        var index = 0
        while amount >= 1024 && index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        if index == 0 { return "\(Int(amount.rounded())) B" }
        let digits = compact ? (amount >= 100 ? 0 : 1) : (amount >= 100 ? 0 : amount >= 10 ? 1 : 2)
        return "\(amount.formatted(.number.precision(.fractionLength(digits)))) \(units[index])"
    }

    private func liveSpeed(_ value: Int64) -> String {
        guard model.collectorStatus.rateUpdatedAt != nil else { return "--" }
        return "\(bytes(value, compact: true))/s"
    }

    private var collectorRefreshLabel: String {
        let status = model.collectorStatus
        guard status.isRunning else { return "采集已暂停" }
        if status.isStale {
            return status.lastSampleAt.map { "采集延迟 · 最近 \(dateTime($0))" } ?? "等待首次采样"
        }
        let seconds = max(Int(status.pollInterval.rounded()), 1)
        return status.usesLowPowerPolling
            ? "后台低功耗 · \(seconds) 秒刷新"
            : "热点接口 · \(seconds) 秒刷新"
    }

    private var collectorStateTitle: String {
        let status = model.collectorStatus
        if !status.isRunning { return "已暂停" }
        if status.errorMessage != nil { return "采集异常" }
        return status.isStale ? "采集延迟" : "正在采集"
    }

    private var collectorStateColor: Color {
        let status = model.collectorStatus
        if status.isHealthy { return .green }
        return status.isRunning ? .orange : .secondary
    }

    private func dateTime(_ date: Date, timeOnly: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = timeOnly ? "HH:mm" : "M 月 d 日 HH:mm"
        return formatter.string(from: date)
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

private struct Surface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

private struct LiveRateTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
