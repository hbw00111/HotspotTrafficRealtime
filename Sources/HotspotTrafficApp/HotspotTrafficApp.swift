import AppKit
import SwiftUI

@main
struct HotspotTrafficApp: App {
    @StateObject private var model = DashboardModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 1180, height: 820)

        MenuBarExtra("热点流量", systemImage: "antenna.radiowaves.left.and.right") {
            Text(model.collectorStatus.isRunning ? "正在采集热点流量" : "采集已暂停")
            Text("↓ \(liveSpeed(model.collectorStatus.downloadBytesPerSecond))  ↑ \(liveSpeed(model.collectorStatus.uploadBytesPerSecond))")
            if let lastSample = model.collectorStatus.lastSampleAt {
                Text("最近采样：\(lastSample.formatted(date: .abbreviated, time: .shortened))")
            }
            Divider()
            Button(model.collectorStatus.isRunning ? "停止采集" : "启动采集") {
                model.toggleCollector()
            }
            Button("打开统计窗口") {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
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
}
