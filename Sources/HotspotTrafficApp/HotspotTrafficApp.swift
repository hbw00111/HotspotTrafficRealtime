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
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 1180, height: 820)

        MenuBarExtra {
            Text(model.collectorStatus.isRunning ? "正在采集热点流量" : "采集已暂停")

            Text("下载  \(liveSpeed(model.collectorStatus.downloadBytesPerSecond))")
            Text("上传  \(liveSpeed(model.collectorStatus.uploadBytesPerSecond))")
            Text("今日  \(bytes(model.todaySummary.totalBytes))")

            if let lastSample = model.collectorStatus.lastSampleAt {
                Text("最近采样：\(lastSample.formatted(date: .abbreviated, time: .shortened))")
            }

            Divider()

            Menu("菜单栏组件") {
                Toggle("图标", isOn: $showMenuBarIcon)
                Toggle("实时下载", isOn: $showMenuBarDownload)
                Toggle("实时上传", isOn: $showMenuBarUpload)
                Toggle("今日用量", isOn: $showMenuBarUsage)
            }

            Divider()

            Button(model.collectorStatus.isRunning ? "停止采集" : "启动采集") {
                model.toggleCollector()
            }
            Button("打开统计窗口") {
                NSApp.activate(ignoringOtherApps: true)
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
        .menuBarExtraStyle(.menu)
    }

    private var hasVisibleMenuBarComponent: Bool {
        showMenuBarIcon || showMenuBarDownload || showMenuBarUpload || showMenuBarUsage
    }

    private func liveSpeed(_ value: Int64) -> String {
        guard model.collectorStatus.rateUpdatedAt != nil else { return "--" }
        let units = ["B", "KB", "MB", "GB"]
        var amount = Double(max(value, 0))
        var index = 0
        while amount >= 1024 && index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        let digits = index == 0 ? 0 : amount >= 100 ? 0 : 1
        return "\(amount.formatted(.number.precision(.fractionLength(digits)))) \(units[index])/s"
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
