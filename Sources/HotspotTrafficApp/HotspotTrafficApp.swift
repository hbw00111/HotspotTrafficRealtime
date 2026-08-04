import AppKit
import SwiftUI

@main
struct HotspotTrafficApp: App {
    @StateObject private var model = DashboardModel()
    @AppStorage("menuBar.showIcon") private var showMenuBarIcon = true
    @AppStorage("menuBar.showDownload") private var showMenuBarDownload = true
    @AppStorage("menuBar.showUpload") private var showMenuBarUpload = true
    @AppStorage("menuBar.showUsage") private var showMenuBarUsage = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarDashboard(model: model) {
                DashboardWindowController.shared.show(model: model)
            }
        } label: {
            HStack(spacing: 5) {
                if showMenuBarIcon {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                }
                if showMenuBarDownload {
                    Text("↓\(menuRate(model.collectorStatus.downloadBytesPerSecond))")
                }
                if showMenuBarUpload {
                    Text("↑\(menuRate(model.collectorStatus.uploadBytesPerSecond))")
                }
                if showMenuBarUsage {
                    Text("∑\(menuBytes(model.todaySummary.totalBytes))")
                }
                if !hasVisibleMenuBarComponent {
                    Text("HT")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var hasVisibleMenuBarComponent: Bool {
        showMenuBarIcon || showMenuBarDownload || showMenuBarUpload || showMenuBarUsage
    }

    private func menuRate(_ value: Int64) -> String {
        guard model.collectorStatus.rateUpdatedAt != nil else { return "--" }
        return menuBytes(value) + "/s"
    }

    private func menuBytes(_ value: Int64) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var amount = Double(max(value, 0))
        var index = 0
        while amount >= 1024 && index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        let digits = index == 0 || amount >= 100 ? 0 : 1
        return "\(amount.formatted(.number.precision(.fractionLength(digits))))\(units[index])"
    }
}

private struct MenuBarDashboard: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: DashboardModel
    let openDashboard: () -> Void
    @AppStorage("menuBar.showIcon") private var showMenuBarIcon = true
    @AppStorage("menuBar.showDownload") private var showMenuBarDownload = true
    @AppStorage("menuBar.showUpload") private var showMenuBarUpload = true
    @AppStorage("menuBar.showUsage") private var showMenuBarUsage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("热点流量")
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(model.collectorStatus.isHealthy ? TrafficTheme.signal : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(model.collectorStatus.isRunning ? "正在采集" : "已暂停")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭统计面板")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            HStack(spacing: 18) {
                CompactLiveMetric(
                    title: "实时下载",
                    value: liveSpeed(model.collectorStatus.downloadBytesPerSecond),
                    symbol: "arrow.down",
                    color: TrafficTheme.download
                )
                CompactLiveMetric(
                    title: "实时上传",
                    value: liveSpeed(model.collectorStatus.uploadBytesPerSecond),
                    symbol: "arrow.up",
                    color: TrafficTheme.upload
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(TrafficTheme.hero)

            VStack(alignment: .leading, spacing: 12) {
                Picker("时间范围", selection: $model.selectedRange) {
                    Text("今天").tag(TrafficRange.today)
                    Text("7 天").tag(TrafficRange.sevenDays)
                    Text("30 天").tag(TrafficRange.thirtyDays)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("应用流量")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(bytes(model.summary.totalBytes))
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("活跃应用")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("\(model.summary.apps.count)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }

                Divider()

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TOP PROCESSES")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(TrafficTheme.signal)
                        Text("应用排行")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Spacer()
                    Text("TOP 5")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: 5) {
                    if model.summary.apps.isEmpty {
                        Text("暂无应用流量")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        ForEach(model.summary.apps.prefix(5)) { app in
                            HStack(spacing: 8) {
                                ProcessBadge(name: app.process, category: app.category, compact: true)
                                Text(app.process)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(bytes(app.totalBytes))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(minHeight: 116, alignment: .top)
            }
            .padding(16)

            HStack(spacing: 12) {
                Menu {
                    Toggle("图标", isOn: $showMenuBarIcon)
                    Toggle("实时下载", isOn: $showMenuBarDownload)
                    Toggle("实时上传", isOn: $showMenuBarUpload)
                    Toggle("今日用量", isOn: $showMenuBarUsage)
                } label: {
                    Image(systemName: "menubar.rectangle")
                }
                .menuStyle(.borderlessButton)
                .help("菜单栏组件")

                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        openDashboard()
                    }
                } label: {
                    Label("完整统计", systemImage: "chart.xyaxis.line")
                }

                Spacer()

                Button {
                    model.toggleCollector()
                } label: {
                    Image(systemName: model.collectorStatus.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .help(model.collectorStatus.isRunning ? "暂停采集" : "开始采集")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color.primary.opacity(0.035))
        }
        .frame(width: 390, height: 460)
        .background(TrafficTheme.canvas)
    }

    private func liveSpeed(_ value: Int64) -> String {
        guard model.collectorStatus.rateUpdatedAt != nil else { return "--" }
        return "\(bytes(value))/s"
    }

    private func bytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = Double(max(value, 0))
        var index = 0
        while amount >= 1024 && index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        let digits = index == 0 ? 0 : amount >= 100 ? 0 : 1
        return "\(amount.formatted(.number.precision(.fractionLength(digits)))) \(units[index])"
    }

}

@MainActor
private final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    static let shared = DashboardWindowController()

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(model: DashboardModel) {
        if window == nil {
            let content = ContentView()
                .environmentObject(model)
            let hostingController = NSHostingController(rootView: content)
            let dashboardWindow = NSWindow(contentViewController: hostingController)
            dashboardWindow.title = "热点流量"
            dashboardWindow.setContentSize(NSSize(width: 1180, height: 820))
            dashboardWindow.minSize = NSSize(width: 940, height: 680)
            dashboardWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            dashboardWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            dashboardWindow.isReleasedWhenClosed = false
            dashboardWindow.delegate = self
            dashboardWindow.center()
            window = dashboardWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

private struct CompactLiveMetric: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
