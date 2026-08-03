import AppKit
import Foundation
import Combine

@MainActor
final class DashboardModel: ObservableObject {
    @Published var selectedRange: TrafficRange = .sevenDays {
        didSet { reload() }
    }
    @Published var customFrom: Date
    @Published var customTo: Date
    @Published private(set) var summary = TrafficSummary.empty
    @Published private(set) var todaySummary = TrafficSummary.empty
    @Published private(set) var collectorStatus = CollectorStatus()

    let store: TrafficStore
    let collector: TrafficCollector
    private var cancellables = Set<AnyCancellable>()

    init() {
        let today = Calendar.current.startOfDay(for: Date())
        customFrom = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
        customTo = today
        store = TrafficStore()
        collector = TrafficCollector(store: store)
        collectorStatus = collector.status
        collector.onData = { [weak self] in
            self?.reload()
        }
        collector.onStatus = { [weak self] status in
            self?.collectorStatus = status
        }
        observeApplicationActivity()
        collector.setForeground(NSApp.isActive)
        collector.start()
        reload()
    }

    func reload() {
        summary = store.summary(for: selectedRange, customFrom: customFrom, customTo: customTo)
        todaySummary = selectedRange == .today
            ? summary
            : store.summary(for: .today, customFrom: customFrom, customTo: customTo)
        collectorStatus = collector.status
    }

    func applyCustomRange() {
        guard selectedRange == .custom else { return }
        reload()
    }

    func toggleCollector() {
        collector.toggle()
        collectorStatus = collector.status
    }

    private func observeApplicationActivity() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.setApplicationActive(true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.setApplicationActive(false)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.collector.refreshNow()
            }
            .store(in: &cancellables)
    }

    private func setApplicationActive(_ isActive: Bool) {
        collector.setForeground(isActive)
        collectorStatus = collector.status
    }
}
