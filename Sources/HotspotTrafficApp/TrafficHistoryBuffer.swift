import Foundation

struct TrafficHistoryBatch {
    let sampledAt: Date
    let records: [TrafficRecord]
}

struct TrafficHistoryBuffer {
    private var pendingRecords: [PendingKey: PendingRecord] = [:]
    private var pendingBytesIn: Int64 = 0
    private var pendingBytesOut: Int64 = 0
    private var pendingStartedAt: Date?
    private var lastFlushAt: Date?
    private var isAwaitingPersistence = false

    var hasPendingRecords: Bool {
        !pendingRecords.isEmpty
    }

    mutating func append(
        _ records: [TrafficRecord],
        at date: Date,
        flushInterval: TimeInterval
    ) -> TrafficHistoryBatch? {
        guard !records.isEmpty || hasPendingRecords else { return nil }

        for record in records {
            guard let batchBytesIn = ByteCount.adding(pendingBytesIn, record.bytesIn),
                  let batchBytesOut = ByteCount.adding(pendingBytesOut, record.bytesOut),
                  ByteCount.adding(batchBytesIn, batchBytesOut) != nil else { continue }
            let key = PendingKey(
                process: record.process,
                pid: record.pid,
                interfaceName: record.interfaceName,
                state: record.state
            )
            let pending = pendingRecords[key] ?? PendingRecord()
            guard let accumulated = pending.adding(record) else { continue }
            if pendingStartedAt == nil {
                pendingStartedAt = date
            }
            pendingRecords[key] = accumulated
            pendingBytesIn = batchBytesIn
            pendingBytesOut = batchBytesOut
        }

        let shouldFlush = isAwaitingPersistence || (lastFlushAt.map {
            date.timeIntervalSince($0) >= flushInterval
        } ?? true)
        if shouldFlush {
            return flush()
        }
        return nil
    }

    mutating func flush() -> TrafficHistoryBatch? {
        guard let sampledAt = pendingStartedAt, hasPendingRecords else {
            return nil
        }

        let records = pendingRecords.map { key, value in
            TrafficRecord(
                timestamp: sampledAt,
                process: key.process,
                pid: key.pid,
                interfaceName: key.interfaceName,
                state: key.state,
                bytesIn: value.bytesIn,
                bytesOut: value.bytesOut
            )
        }
        isAwaitingPersistence = true
        return TrafficHistoryBatch(sampledAt: sampledAt, records: records)
    }

    mutating func markPersisted(at date: Date) {
        guard hasPendingRecords else { return }
        pendingRecords.removeAll(keepingCapacity: true)
        pendingBytesIn = 0
        pendingBytesOut = 0
        pendingStartedAt = nil
        lastFlushAt = date
        isAwaitingPersistence = false
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

    func adding(_ record: TrafficRecord) -> PendingRecord? {
        guard let nextBytesIn = ByteCount.adding(bytesIn, record.bytesIn),
              let nextBytesOut = ByteCount.adding(bytesOut, record.bytesOut),
              ByteCount.adding(nextBytesIn, nextBytesOut) != nil else { return nil }
        return PendingRecord(
            bytesIn: nextBytesIn,
            bytesOut: nextBytesOut
        )
    }
}
