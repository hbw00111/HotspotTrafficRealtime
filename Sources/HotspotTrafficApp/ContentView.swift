import Charts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var detailSection: DetailSection = .applications

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if model.selectedRange == .custom {
                    customRangeControls
                }

                if let error = model.collectorStatus.errorMessage {
                    notice(icon: "exclamationmark.triangle.fill", color: .orange, text: error)
                }

                summaryPanel

                if model.summary.sampleCount == 0 {
                    emptyState
                } else {
                    dashboard
                    detailsPanel
                }
            }
            .padding(22)
        }
        .frame(minWidth: 940, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text("热点流量")
                    .font(.system(size: 20, weight: .semibold))
                Text(model.summary.lastSample.map { "最近采样 \(dateTime($0))" } ?? "等待本地采样")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 18)

            HStack(spacing: 7) {
                Circle()
                    .fill(collectorStateColor)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(collectorStateTitle)
                        .font(.system(size: 11, weight: .medium))
                    Text(collectorRefreshLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 150, alignment: .leading)

            Picker("时间范围", selection: $model.selectedRange) {
                ForEach(TrafficRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 270)

            Button {
                model.toggleCollector()
            } label: {
                Label(
                    model.collectorStatus.isRunning ? "停止" : "开始",
                    systemImage: model.collectorStatus.isRunning ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(model.collectorStatus.isRunning ? .secondary : .accentColor)
        }
    }

    private var customRangeControls: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
            DatePicker("开始", selection: $model.customFrom, displayedComponents: .date)
            DatePicker("结束", selection: $model.customTo, displayedComponents: .date)
            Button("应用") { model.applyCustomRange() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay(panelBorder)
    }

    private var summaryPanel: some View {
        Panel {
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(model.collectorStatus.isHealthy ? Color.green : Color.secondary)
                                .frame(width: 7, height: 7)
                            Text("实时速率")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text("当前热点连接")
                            .font(.system(size: 15, weight: .semibold))
                    }

                    Spacer()

                    LiveRateTile(
                        title: "下载",
                        value: liveSpeed(model.collectorStatus.downloadBytesPerSecond),
                        icon: "arrow.down",
                        tint: .blue
                    )
                    Divider().frame(height: 38)
                    LiveRateTile(
                        title: "上传",
                        value: liveSpeed(model.collectorStatus.uploadBytesPerSecond),
                        icon: "arrow.up",
                        tint: uploadColor
                    )
                    Divider().frame(height: 38)
                    LiveRateTile(
                        title: "合计",
                        value: liveSpeed(model.collectorStatus.downloadBytesPerSecond + model.collectorStatus.uploadBytesPerSecond),
                        icon: "arrow.up.arrow.down",
                        tint: .secondary
                    )
                }
                .padding(18)

                Divider()

                HStack(spacing: 0) {
                    MetricTile(title: "总流量", value: bytes(model.summary.totalBytes), detail: rangeTitle, accent: .primary)
                    Divider().frame(height: 52)
                    MetricTile(title: "下载", value: bytes(model.summary.bytesIn), detail: "接收数据", accent: .blue)
                    Divider().frame(height: 52)
                    MetricTile(title: "上传", value: bytes(model.summary.bytesOut), detail: "发送数据", accent: uploadColor)
                    Divider().frame(height: 52)
                    MetricTile(title: "活跃应用", value: "\(model.summary.apps.count)", detail: "\(model.summary.sampleCount) 条采样", accent: .primary)
                }
                .padding(.vertical, 15)
            }
        }
    }

    private var dashboard: some View {
        HStack(alignment: .top, spacing: 16) {
            Panel {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionTitle(title: "流量趋势", subtitle: model.selectedRange == .today ? "按小时" : "按天")
                        Spacer()
                        ChartLegend(color: .blue, text: "下载")
                        ChartLegend(color: uploadColor, text: "上传")
                    }

                    if model.summary.points.allSatisfy({ $0.totalBytes == 0 }) {
                        emptyChart
                    } else {
                        trafficChart
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity)

            Panel {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionTitle(title: "应用排行", subtitle: "流量占用")
                        Spacer()
                        Text("Top 5")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    appRanking
                }
                .padding(18)
            }
            .frame(width: 318)
        }
    }

    private var trafficChart: some View {
        Chart {
            ForEach(model.summary.points) { point in
                LineMark(
                    x: .value("时间", point.date),
                    y: .value("下载", point.bytesIn),
                    series: .value("方向", "下载")
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("时间", point.date),
                    y: .value("上传", point.bytesOut),
                    series: .value("方向", "上传")
                )
                .foregroundStyle(uploadColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...chartMaximum)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: model.selectedRange == .today ? 6 : 7)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisTick().foregroundStyle(.tertiary)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(model.selectedRange == .today ? dateTime(date, timeOnly: true) : dateLabel(date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let number = value.as(Int64.self) {
                        Text(bytes(number, compact: true))
                    }
                }
            }
        }
        .frame(height: 252)
    }

    private var appRanking: some View {
        VStack(alignment: .leading, spacing: 15) {
            if model.summary.apps.isEmpty {
                Text("还没有应用流量")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, minHeight: 218, alignment: .center)
            } else {
                let topValue = max(model.summary.apps.first?.totalBytes ?? 1, 1)
                ForEach(model.summary.apps.prefix(5)) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(appColor(app.colorIndex))
                                .frame(width: 7, height: 7)
                            Text(app.process)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text(bytes(app.totalBytes, compact: true))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        ProgressView(value: Double(app.totalBytes), total: Double(topValue))
                            .progressViewStyle(.linear)
                            .tint(appColor(app.colorIndex))
                    }
                }
            }
        }
    }

    private var detailsPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: detailSection.title, subtitle: "\(detailRows.count) 项")
                    Spacer()
                    Picker("明细类型", selection: $detailSection) {
                        Text("应用").tag(DetailSection.applications)
                        Text("隧道").tag(DetailSection.tunnels)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                Table(detailRows) {
                    TableColumn("进程") { app in
                        HStack(spacing: 8) {
                            Circle().fill(appColor(app.colorIndex)).frame(width: 7, height: 7)
                            Text(app.process).fontWeight(.medium)
                        }
                    }
                    TableColumn("类型") { app in
                        Text(app.category).foregroundStyle(.secondary)
                    }
                    TableColumn("总流量") { app in
                        Text(bytes(app.totalBytes)).monospacedDigit()
                    }
                    TableColumn("下载") { app in
                        Text(bytes(app.bytesIn)).monospacedDigit()
                    }
                    TableColumn("上传") { app in
                        Text(bytes(app.bytesOut)).monospacedDigit()
                    }
                    TableColumn("活跃天数") { app in
                        Text("\(app.activeDays) 天").monospacedDigit()
                    }
                    TableColumn("最近记录") { app in
                        Text(app.lastSeen.map { dateTime($0) } ?? "--")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 218)
            }
            .padding(18)
        }
    }

    private var emptyState: some View {
        Panel {
            VStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("还没有采样记录")
                    .font(.system(size: 15, weight: .semibold))
                Text("连接热点后，应用流量会记录在这里")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 230)
        }
    }

    private var emptyChart: some View {
        Text("这个时间范围还没有流量")
            .foregroundStyle(.secondary)
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, minHeight: 252)
    }

    private func notice(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 11))
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
    }

    private var detailRows: [AppUsage] {
        detailSection == .applications ? model.summary.apps : model.summary.tunnels
    }

    private var chartMaximum: Int64 {
        max(model.summary.points.flatMap { [$0.bytesIn, $0.bytesOut] }.max() ?? 1, 1)
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: 7)
            .stroke(Color.primary.opacity(0.09), lineWidth: 1)
    }

    private var rangeTitle: String {
        switch model.selectedRange {
        case .today: return "今天"
        case .sevenDays: return "最近 7 天"
        case .thirtyDays: return "最近 30 天"
        case .custom: return "自定义范围"
        }
    }

    private var uploadColor: Color {
        Color(red: 0.91, green: 0.34, blue: 0.29)
    }

    private func appColor(_ index: Int) -> Color {
        [.blue, .green, .orange, .purple, .red, .gray, .yellow][index % 7]
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
            return status.lastSampleAt.map { "最近 \(dateTime($0))" } ?? "等待首次采样"
        }
        let seconds = max(Int(status.pollInterval.rounded()), 1)
        return status.usesLowPowerPolling ? "低功耗 · \(seconds) 秒" : "\(seconds) 秒刷新"
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

private enum DetailSection: String, Hashable {
    case applications
    case tunnels

    var title: String {
        switch self {
        case .applications: return "应用明细"
        case .tunnels: return "隧道明细"
        }
    }
}

private struct Panel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            )
    }
}

private struct SectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(minWidth: 122, alignment: .leading)
    }
}

private struct ChartLegend: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 13, height: 3)
            Text(text)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}
