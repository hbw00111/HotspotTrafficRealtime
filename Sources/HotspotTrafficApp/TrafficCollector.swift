import Foundation
import Combine
import Dispatch

@MainActor
final class TrafficCollector: ObservableObject {
    @Published private(set) var status = CollectorStatus()

    private let store: TrafficStore
    private var nettopStream: NettopStream?
    private let heartbeatQueue = DispatchQueue(label: "local.hotspot-traffic.heartbeat", qos: .utility)
    private var heartbeatTimer: DispatchSourceTimer?
    private var activity: NSObjectProtocol?
    private var streamGeneration = 0
    private var isForeground = true
    private let foregroundPollInterval: TimeInterval = 5
    private let backgroundPollInterval: TimeInterval = 30
    private let foregroundHistoryInterval: TimeInterval = 60
    private let backgroundHistoryInterval: TimeInterval = 5 * 60
    private let heartbeatPersistenceInterval: TimeInterval = 60
    private var historyBuffer = TrafficHistoryBuffer()
    private var lastHeartbeatPersistAt: Date?
    var onData: (() -> Void)?
    var onStatus: ((CollectorStatus) -> Void)?

    init(store: TrafficStore) {
        self.store = store
    }

    func setForeground(_ foreground: Bool) {
        guard isForeground != foreground else { return }
        isForeground = foreground
        status.pollInterval = currentPollInterval
        status.usesLowPowerPolling = !foreground

        guard status.isRunning else { return }
        startNettopStream()
        scheduleHeartbeat()
        onStatus?(status)
    }

    func start() {
        guard !status.isRunning else { return }
        status.isRunning = true
        status.startedAt = Date()
        status.lastSampleAt = nil
        status.lastRecordCount = 0
        status.resetErrors()
        status.downloadBytesPerSecond = 0
        status.uploadBytesPerSecond = 0
        status.rateUpdatedAt = nil
        status.pollInterval = currentPollInterval
        status.usesLowPowerPolling = !isForeground
        if !historyBuffer.hasPendingRecords {
            historyBuffer = TrafficHistoryBuffer()
        }
        lastHeartbeatPersistAt = nil
        beginMonitoringActivity()
        startNettopStream()
        recordHeartbeatIfNeeded(at: Date())
        scheduleHeartbeat()
        onStatus?(status)
    }

    func stop() {
        streamGeneration += 1
        nettopStream?.stop()
        nettopStream = nil
        cancelHeartbeat()
        persist(historyBuffer.flush(), confirmedAt: Date())
        status.isRunning = false
        status.startedAt = nil
        status.downloadBytesPerSecond = 0
        status.uploadBytesPerSecond = 0
        status.pollInterval = 0
        status.usesLowPowerPolling = false
        endMonitoringActivity()
        onStatus?(status)
    }

    func toggle() {
        status.isRunning ? stop() : start()
    }

    private var currentPollInterval: TimeInterval {
        isForeground ? foregroundPollInterval : backgroundPollInterval
    }

    private var currentHistoryInterval: TimeInterval {
        isForeground ? foregroundHistoryInterval : backgroundHistoryInterval
    }

    func refreshNow() {
        guard status.isRunning else { return }
        recordHeartbeatIfNeeded(at: Date())
        startNettopStream()
    }

    private func scheduleHeartbeat() {
        cancelHeartbeat()
        let interval = currentPollInterval
        let timer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        let milliseconds = Int((interval * 1_000).rounded())
        timer.schedule(
            deadline: .now() + .milliseconds(milliseconds),
            repeating: .milliseconds(milliseconds),
            leeway: .milliseconds(max(milliseconds / 5, 1))
        )
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.recordHeartbeatIfNeeded(at: Date())
            }
        }
        heartbeatTimer = timer
        timer.resume()
    }

    private func cancelHeartbeat() {
        heartbeatTimer?.setEventHandler {}
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func recordHeartbeatIfNeeded(at date: Date) {
        guard status.isRunning else { return }
        if let lastSampleAt = status.lastSampleAt,
           date.timeIntervalSince(lastSampleAt) < currentPollInterval * 1.5 {
            return
        }
        status.recordMissingFrame(at: date)
        recordNoTraffic(at: date)
        onStatus?(status)
    }

    private func recordNoTraffic(at date: Date) {
        if !historyBuffer.hasPendingRecords {
            persistHeartbeatIfNeeded(at: date)
        } else {
            accumulate([], at: date)
        }
    }

    private func persistHeartbeatIfNeeded(at date: Date) {
        if let lastHeartbeatPersistAt,
           date.timeIntervalSince(lastHeartbeatPersistAt) < heartbeatPersistenceInterval {
            return
        }
        persist([], sampledAt: date) {
            self.lastHeartbeatPersistAt = date
        }
    }

    private func beginMonitoringActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Monitor personal hotspot traffic while the app is in the background"
        )
    }

    private func endMonitoringActivity() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    private func startNettopStream() {
        streamGeneration += 1
        let generation = streamGeneration
        let interval = currentPollInterval
        nettopStream?.stop()

        let stream = NettopStream(sampleInterval: interval)
        stream.onFrame = { [weak self] lines, sampledAt in
            let records = NettopParser.parseFrame(lines, sampledAt: sampledAt)
            let bytesIn = ByteCount.sum(records.lazy.map(\.bytesIn)) ?? Int64.max
            let bytesOut = ByteCount.sum(records.lazy.map(\.bytesOut)) ?? Int64.max
            let divisor = max(interval, 1)
            let downloadRate = Int64((Double(bytesIn) / divisor).rounded())
            let uploadRate = Int64((Double(bytesOut) / divisor).rounded())

            Task { @MainActor in
                guard let self, self.status.isRunning, self.streamGeneration == generation else { return }
                self.status.recordFrame(
                    at: sampledAt,
                    recordCount: records.count,
                    downloadBytesPerSecond: downloadRate,
                    uploadBytesPerSecond: uploadRate
                )
                if records.isEmpty {
                    self.recordNoTraffic(at: sampledAt)
                } else {
                    self.accumulate(records, at: sampledAt)
                }
                self.onStatus?(self.status)
            }
        }
        stream.onFailure = { [weak self] message in
            Task { @MainActor in
                guard let self, self.status.isRunning, self.streamGeneration == generation else { return }
                self.status.downloadBytesPerSecond = 0
                self.status.uploadBytesPerSecond = 0
                self.status.recordStreamFailure(message)
                self.onStatus?(self.status)
            }
        }

        nettopStream = stream
        stream.start()
    }

    private func accumulate(_ records: [TrafficRecord], at date: Date) {
        let batch = historyBuffer.append(
            records,
            at: date,
            flushInterval: currentHistoryInterval
        )
        persist(batch, confirmedAt: date)
    }

    private func persist(_ batch: TrafficHistoryBatch?, confirmedAt date: Date) {
        guard let batch else { return }
        persist(batch.records, sampledAt: batch.sampledAt) {
            self.historyBuffer.markPersisted(at: date)
        }
    }

    private func persist(
        _ records: [TrafficRecord],
        sampledAt: Date,
        onSuccess: () -> Void
    ) {
        do {
            try store.append(records, sampledAt: sampledAt)
            onSuccess()
            status.recordStorageSuccess()
            onData?()
        } catch {
            reportStoreError(error)
        }
    }

    private func reportStoreError(_ error: Error) {
        status.recordStorageFailure(error.localizedDescription)
        onStatus?(status)
    }
}
