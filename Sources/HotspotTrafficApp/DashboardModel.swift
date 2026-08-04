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

    private let store: TrafficStore?
    private let collector: TrafficCollector?
    private var cancellables = Set<AnyCancellable>()
    private let summaryQueue = DispatchQueue(label: "local.hotspot-traffic.summary", qos: .utility)
    private var reloadGeneration = 0

    init() {
        let today = Calendar.current.startOfDay(for: Date())
        customFrom = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
        customTo = today
        let store: TrafficStore
        do {
            store = try TrafficStore()
        } catch {
            self.store = nil
            collector = nil
            collectorStatus.recordStorageFailure(error.localizedDescription)
            return
        }

        self.store = store
        let collector = TrafficCollector(store: store)
        self.collector = collector
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
        guard let store else { return }
        if let collector {
            collectorStatus = collector.status
        }
        reloadGeneration += 1
        let generation = reloadGeneration
        let range = selectedRange
        let from = customFrom
        let to = customTo

        summaryQueue.async { [weak self] in
            let result = autoreleasepool { () -> (TrafficSummary, TrafficSummary) in
                let summary = store.summary(for: range, customFrom: from, customTo: to)
                let todaySummary = range == .today
                    ? summary
                    : store.summary(for: .today, customFrom: from, customTo: to)
                return (summary, todaySummary)
            }

            DispatchQueue.main.async {
                guard let self, self.reloadGeneration == generation else { return }
                self.summary = result.0
                self.todaySummary = result.1
            }
        }
    }

    func applyCustomRange() {
        guard selectedRange == .custom else { return }
        reload()
    }

    func toggleCollector() {
        collector?.toggle()
        if let collector {
            collectorStatus = collector.status
        }
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
                self?.collector?.refreshNow()
            }
            .store(in: &cancellables)
    }

    private func setApplicationActive(_ isActive: Bool) {
        collector?.setForeground(isActive)
        if let collector {
            collectorStatus = collector.status
        }
    }
}
