import Charts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var detailSection: DetailSection = .applications

    var body: some View {
        VStack(spacing: 0) {
            commandBar
            Divider().opacity(0.55)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.selectedRange == .custom {
                        customRangeControls
                    }

                    if let error = model.collectorStatus.errorMessage {
                        errorBanner(error)
                    }

                    trafficOverview

                    if model.summary.sampleCount == 0 {
                        emptyState
                    } else {
                        analysisWorkbench
                        detailsPanel
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 30)
                .frame(maxWidth: 1280)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 940, minHeight: 680)
        .background(TrafficTheme.canvas)
    }

    private var commandBar: some View {
        HStack(spacing: 14) {
            BrandMark(size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("热点流量")
                    .font(.system(size: 19, weight: .semibold))
                Text(model.summary.lastSample.map { "更新于 \(dateTime($0))" } ?? "等待本地采样")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 22)

            CollectorBadge(
                title: collectorStateTitle,
                detail: collectorRefreshLabel,
                color: collectorStateColor
            )

            Picker("时间范围", selection: $model.selectedRange) {
                ForEach(TrafficRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 272)

            Button {
                model.toggleCollector()
            } label: {
                Image(systemName: model.collectorStatus.isRunning ? "pause.fill" : "play.fill")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(model.collectorStatus.isRunning ? TrafficTheme.ink : TrafficTheme.signal)
            .help(model.collectorStatus.isRunning ? "暂停采集" : "开始采集")
        }
        .padding(.horizontal, 24)
        .frame(height: 72)
        .background(TrafficTheme.canvas)
    }

    private var customRangeControls: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TrafficTheme.signal)
                .frame(width: 30, height: 30)
                .background(TrafficTheme.signal.opacity(0.11), in: RoundedRectangle(cornerRadius: 6))

            DatePicker("开始", selection: $model.customFrom, displayedComponents: .date)
            DatePicker("结束", selection: $model.customTo, displayedComponents: .date)
            Button("应用") { model.applyCustomRange() }
                .buttonStyle(.borderedProminent)
                .tint(TrafficTheme.signal)
            Spacer()
        }
        .font(.system(size: 11, weight: .medium))
        .padding(12)
        .background(TrafficTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(TrafficTheme.border(cornerRadius: 8))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TrafficTheme.warning)
            Text(message)
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(TrafficTheme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
        .overlay(TrafficTheme.border(cornerRadius: 7, color: TrafficTheme.warning.opacity(0.22)))
    }

    private var trafficOverview: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(rangeTitle.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.56))
                    Text(bytes(model.summary.totalBytes))
                        .font(.system(size: 47, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("应用产生的总流量")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.52))
                }

                Spacer(minLength: 20)

                SignalGlyph()
                    .frame(width: 96, height: 62)

                VStack(alignment: .leading, spacing: 13) {
                    LiveRateLine(
                        title: "实时下载",
                        value: liveSpeed(model.collectorStatus.downloadBytesPerSecond),
                        symbol: "arrow.down",
                        color: TrafficTheme.download
                    )
                    LiveRateLine(
                        title: "实时上传",
                        value: liveSpeed(model.collectorStatus.uploadBytesPerSecond),
                        symbol: "arrow.up",
                        color: TrafficTheme.upload
                    )
                }
                .frame(width: 190)
            }
            .padding(.horizontal, 24)
            .padding(.top, 23)
            .padding(.bottom, 21)

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)

            HStack(spacing: 0) {
                OverviewMetric(label: "下载", value: bytes(model.summary.bytesIn), color: TrafficTheme.download)
                darkDivider
                OverviewMetric(label: "上传", value: bytes(model.summary.bytesOut), color: TrafficTheme.upload)
                darkDivider
                OverviewMetric(label: "活跃应用", value: "\(model.summary.apps.count)", color: .white)
                darkDivider
                OverviewMetric(label: "隧道另列", value: bytes(model.summary.tunnelBytes), color: Color.white.opacity(0.82))
            }
            .padding(.vertical, 15)
        }
        .background(TrafficTheme.hero, in: RoundedRectangle(cornerRadius: 8))
        .overlay(TrafficTheme.border(cornerRadius: 8, color: Color.white.opacity(0.08)))
    }

    private var darkDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 37)
    }

    private var analysisWorkbench: some View {
        HStack(alignment: .top, spacing: 0) {
            trendSection
                .frame(maxWidth: .infinity)

            Divider()
                .padding(.vertical, 18)

            rankingSection
                .frame(width: 330)
        }
        .background(TrafficTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(TrafficTheme.border(cornerRadius: 8))
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "TRAFFIC HISTORY",
                title: "流量趋势",
                trailing: AnyView(
                    HStack(spacing: 13) {
                        LegendMark(color: TrafficTheme.download, text: "下载")
                        LegendMark(color: TrafficTheme.upload, text: "上传")
                    }
                )
            )

            if model.summary.points.allSatisfy({ $0.totalBytes == 0 }) {
                emptyChart
            } else {
                trafficChart
            }
        }
        .padding(20)
    }

    private var trafficChart: some View {
        Chart {
            ForEach(model.summary.points) { point in
                LineMark(
                    x: .value("时间", point.date),
                    y: .value("下载", point.bytesIn),
                    series: .value("方向", "下载")
                )
                .foregroundStyle(TrafficTheme.download)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("时间", point.date),
                    y: .value("上传", point.bytesOut),
                    series: .value("方向", "上传")
                )
                .foregroundStyle(TrafficTheme.upload)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...chartMaximum)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: model.selectedRange == .today ? 6 : 7)) { value in
                AxisGridLine().foregroundStyle(TrafficTheme.grid)
                AxisTick().foregroundStyle(.tertiary)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(model.selectedRange == .today ? dateTime(date, timeOnly: true) : dateLabel(date))
                            .font(.system(size: 9, weight: .medium))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(TrafficTheme.grid)
                AxisValueLabel {
                    if let number = value.as(Int64.self) {
                        Text(bytes(number, compact: true))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                }
            }
        }
        .frame(height: 270)
    }

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "TOP PROCESSES",
                title: "应用排行",
                trailing: AnyView(
                    Text("TOP 5")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                )
            )

            if model.summary.apps.isEmpty {
                Text("还没有应用流量")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 270)
            } else {
                let topValue = max(model.summary.apps.first?.totalBytes ?? 1, 1)
                VStack(spacing: 0) {
                    ForEach(Array(model.summary.apps.prefix(5).enumerated()), id: \.element.id) { index, app in
                        RankingRow(index: index + 1, app: app, topValue: topValue, byteLabel: bytes(app.totalBytes, compact: true))
                        if index < min(model.summary.apps.count, 5) - 1 {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PROCESS LEDGER")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(TrafficTheme.signal)
                    Text(detailSection.title)
                        .font(.system(size: 17, weight: .semibold))
                }

                Text("\(detailRows.count) 项")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("明细类型", selection: $detailSection) {
                    Text("应用").tag(DetailSection.applications)
                    Text("隧道").tag(DetailSection.tunnels)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 156)
            }

            Table(detailRows) {
                TableColumn("进程") { app in
                    HStack(spacing: 9) {
                        ProcessBadge(name: app.process, category: app.category, compact: true)
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
            .frame(minHeight: 230)
        }
        .padding(20)
        .background(TrafficTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(TrafficTheme.border(cornerRadius: 8))
    }

    private var emptyState: some View {
        HStack(spacing: 20) {
            SignalGlyph(empty: true)
                .frame(width: 116, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text("等待第一段流量")
                    .font(.system(size: 18, weight: .semibold))
                Text("连接热点并开始使用网络后，应用记录和趋势会出现在这里。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(model.collectorStatus.isRunning ? "监听中" : "采集已暂停")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(model.collectorStatus.isRunning ? TrafficTheme.signal : .secondary)
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 150)
        .background(TrafficTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(TrafficTheme.border(cornerRadius: 8))
    }

    private var emptyChart: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(TrafficTheme.signal.opacity(0.72))
            Text("这个时间范围还没有流量")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 270)
    }

    private func sectionHeader(eyebrow: String, title: String, trailing: AnyView) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(TrafficTheme.signal)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }
            Spacer()
            trailing
        }
    }

    private var detailRows: [AppUsage] {
        detailSection == .applications ? model.summary.apps : model.summary.tunnels
    }

    private var chartMaximum: Int64 {
        max(model.summary.points.flatMap { [$0.bytesIn, $0.bytesOut] }.max() ?? 1, 1)
    }

    private var rangeTitle: String {
        switch model.selectedRange {
        case .today: return "今天"
        case .sevenDays: return "最近 7 天"
        case .thirtyDays: return "最近 30 天"
        case .custom: return "自定义范围"
        }
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
        if status.isHealthy { return TrafficTheme.signal }
        return status.isRunning ? TrafficTheme.warning : .secondary
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

enum TrafficTheme {
    static let signal = Color(red: 0.22, green: 0.69, blue: 0.54)
    static let download = Color(red: 0.24, green: 0.66, blue: 0.78)
    static let upload = Color(red: 0.91, green: 0.42, blue: 0.32)
    static let warning = Color(red: 0.88, green: 0.60, blue: 0.18)
    static let hero = Color(red: 0.075, green: 0.086, blue: 0.10)
    static let ink = Color(red: 0.13, green: 0.15, blue: 0.17)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let grid = Color.primary.opacity(0.07)

    static func border(cornerRadius: CGFloat, color: Color = Color.primary.opacity(0.09)) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(color, lineWidth: 1)
    }
}

struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(TrafficTheme.ink)
            Image(systemName: "arrow.down.left.arrow.up.right")
                .font(.system(size: size * 0.39, weight: .semibold))
                .foregroundStyle(TrafficTheme.signal)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct CollectorBadge: View {
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 132, alignment: .leading)
    }
}

private struct LiveRateLine: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.48))
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

private struct OverviewMetric: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}

private struct SignalGlyph: View {
    var empty = false

    private let levels: [CGFloat] = [0.28, 0.46, 0.72, 0.42, 0.88, 0.58, 1.0, 0.66, 0.38, 0.76, 0.52, 0.31]

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 4) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(index))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(proxy.size.height * level, 4))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .opacity(empty ? 0.56 : 1)
    }

    private func barColor(_ index: Int) -> Color {
        if empty { return TrafficTheme.signal }
        return index < 7 ? TrafficTheme.download : TrafficTheme.upload
    }
}

private struct LegendMark: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 15, height: 3)
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct RankingRow: View {
    let index: Int
    let app: AppUsage
    let topValue: Int64
    let byteLabel: String

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", index))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .leading)

            ProcessBadge(name: app.process, category: app.category)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(app.process)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(byteLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.primary.opacity(0.07))
                        Rectangle()
                            .fill(TrafficTheme.signal)
                            .frame(width: proxy.size.width * CGFloat(Double(app.totalBytes) / Double(topValue)))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.vertical, 10)
    }
}

struct ProcessBadge: View {
    @ObservedObject private var iconResolver = ProcessIconResolver.shared
    let name: String
    var category = ""
    var compact = false

    var body: some View {
        Group {
            if let icon = iconResolver.icon(for: name) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(compact ? 1 : 2)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: compact ? 9 : 12, weight: .semibold))
                    .foregroundStyle(TrafficTheme.signal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(TrafficTheme.signal.opacity(0.1))
            }
        }
        .frame(width: compact ? 20 : 28, height: compact ? 20 : 28)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 6))
        .animation(.easeOut(duration: 0.16), value: iconResolver.revision)
    }

    private var fallbackSymbol: String {
        switch category {
        case "浏览器": return "globe"
        case "通讯": return "bubble.left.and.bubble.right.fill"
        case "媒体": return "play.rectangle.fill"
        case "开发": return "terminal.fill"
        case "同步": return "icloud.fill"
        case "系统": return "gearshape.2.fill"
        case "隧道": return "point.3.connected.trianglepath.dotted"
        default: return "app.dashed"
        }
    }
}
