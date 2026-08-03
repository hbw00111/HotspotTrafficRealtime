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
    private var lastFrameAt: Date?
    private var isForeground = true
    private let foregroundPollInterval: TimeInterval = 5
    private let backgroundPollInterval: TimeInterval = 30
    private let foregroundHistoryInterval: TimeInterval = 60
    private let backgroundHistoryInterval: TimeInterval = 5 * 60
    private let heartbeatPersistenceInterval: TimeInterval = 60
    private var pendingRecords: [PendingKey: PendingRecord] = [:]
    private var pendingStartedAt: Date?
    private var lastPersistAt: Date?
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
        status.errorMessage = nil
        status.downloadBytesPerSecond = 0
        status.uploadBytesPerSecond = 0
        status.pollInterval = currentPollInterval
        status.usesLowPowerPolling = !isForeground
        pendingRecords.removeAll()
        pendingStartedAt = nil
        lastPersistAt = nil
        lastHeartbeatPersistAt = nil
        lastFrameAt = nil
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
        flushHistory(at: Date())
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
        if let lastFrameAt, date.timeIntervalSince(lastFrameAt) < currentPollInterval * 1.5 {
            return
        }
        status.lastSampleAt = date
        status.lastRecordCount = 0
        status.downloadBytesPerSecond = 0
        status.uploadBytesPerSecond = 0
        status.rateUpdatedAt = date
        recordNoTraffic(at: date)
        onStatus?(status)
    }

    private func recordNoTraffic(at date: Date) {
        if pendingRecords.isEmpty {
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
        store.append([], sampledAt: date)
        lastHeartbeatPersistAt = date
        onData?()
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
            let bytesIn = records.reduce(0) { $0 + $1.bytesIn }
            let bytesOut = records.reduce(0) { $0 + $1.bytesOut }
            let divisor = max(interval, 1)
            let downloadRate = Int64((Double(bytesIn) / divisor).rounded())
            let uploadRate = Int64((Double(bytesOut) / divisor).rounded())

            Task { @MainActor in
                guard let self, self.status.isRunning, self.streamGeneration == generation else { return }
                self.status.errorMessage = nil
                self.lastFrameAt = sampledAt
                self.status.lastSampleAt = sampledAt
                self.status.lastRecordCount = records.count
                self.status.downloadBytesPerSecond = downloadRate
                self.status.uploadBytesPerSecond = uploadRate
                self.status.rateUpdatedAt = sampledAt
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
                self.status.errorMessage = message
                self.onStatus?(self.status)
            }
        }

        nettopStream = stream
        stream.start()
    }

    private func accumulate(_ records: [TrafficRecord], at date: Date) {
        let isFirstSample = pendingStartedAt == nil
        if isFirstSample { pendingStartedAt = date }
        for record in records {
            let key = PendingKey(
                process: record.process,
                pid: record.pid,
                interfaceName: record.interfaceName,
                state: record.state
            )
            var pending = pendingRecords[key] ?? PendingRecord()
            pending.bytesIn += record.bytesIn
            pending.bytesOut += record.bytesOut
            pendingRecords[key] = pending
        }

        if isFirstSample || lastPersistAt == nil {
            flushHistory(at: date)
        } else if let lastPersistAt, date.timeIntervalSince(lastPersistAt) >= currentHistoryInterval {
            flushHistory(at: date)
        }
    }

    private func flushHistory(at date: Date) {
        guard let timestamp = pendingStartedAt else { return }
        let records = pendingRecords.map { key, value in
            TrafficRecord(
                timestamp: timestamp,
                process: key.process,
                pid: key.pid,
                interfaceName: key.interfaceName,
                state: key.state,
                bytesIn: value.bytesIn,
                bytesOut: value.bytesOut
            )
        }
        store.append(records, sampledAt: timestamp)
        pendingRecords.removeAll()
        pendingStartedAt = date
        lastPersistAt = date
        onData?()
    }

}

private struct PendingKey: Hashable {
    let process: String
    let pid: Int
    let interfaceName: String
    let state: String
}

private struct PendingRecord {
    var bytesIn: Int64 = 0
    var bytesOut: Int64 = 0
}
