import Foundation
import SQLite3

@main
enum CoreVerification {
    static func main() {
        verifyEmptyHeartbeat()
        verifyTrafficAndTunnelStorage()
        verifyHistoricalSummaryHandlesLargeTotals()
        verifyWeeklyRange()
        verifyNettopParser()
        verifyOversizedNettopValue()
        verifyHistoryBufferStartsEachBatchAtItsFirstRecord()
        verifyHistoryBufferRejectsOverflowingAccumulation()
        verifyMissingFramesBecomeStale()
        verifyInvalidDatabasePathIsRejected()
        verifyWriteFailureIsReported()
        verifyConcurrentStorageAccess()
        print("Core verification passed: 12 checks")
    }

    private static func verifyEmptyHeartbeat() {
        withStore { store in
            let sampledAt = Date()
            try store.append([], sampledAt: sampledAt)

            let summary = store.summary(for: .today, customFrom: sampledAt, customTo: sampledAt)
            check(summary.sampleCount == 1, "empty sample was not stored")
            check(summary.totalBytes == 0, "empty sample has traffic totals")
            check(summary.lastSample != nil, "empty sample has no timestamp")
            checkClose(summary.lastSample, sampledAt, "empty sample timestamp changed")
        }
    }

    private static func verifyTrafficAndTunnelStorage() {
        withStore { store in
            let sampledAt = Date()
            try store.append([
                TrafficRecord(
                    timestamp: sampledAt,
                    process: "Safari",
                    pid: 101,
                    interfaceName: "en0",
                    state: "ESTABLISHED",
                    bytesIn: 1_024,
                    bytesOut: 256
                ),
                TrafficRecord(
                    timestamp: sampledAt,
                    process: "Shadowrocket",
                    pid: 202,
                    interfaceName: "en0",
                    state: "ESTABLISHED",
                    bytesIn: 512,
                    bytesOut: 128
                )
            ], sampledAt: sampledAt)

            let summary = store.summary(for: .today, customFrom: sampledAt, customTo: sampledAt)
            check(summary.sampleCount == 1, "traffic sample count is wrong")
            check(summary.bytesIn == 1_024 && summary.bytesOut == 256, "app traffic totals are wrong")
            check(summary.totalBytes == 1_280, "app traffic total is wrong")
            check(summary.apps.map(\.process) == ["Safari"], "normal app was not retained")
            check(summary.tunnelBytes == 640, "tunnel traffic was not separated")
            check(summary.tunnels.map(\.process) == ["Shadowrocket"], "tunnel process was not retained")
            checkClose(summary.lastSample, sampledAt, "traffic sample timestamp changed")
        }
    }

    private static func verifyWeeklyRange() {
        withStore { store in
            let sampledAt = Date().addingTimeInterval(-2 * 24 * 60 * 60)
            try store.append([
                TrafficRecord(
                    timestamp: sampledAt,
                    process: "Mail",
                    pid: 303,
                    interfaceName: "en0",
                    state: "ESTABLISHED",
                    bytesIn: 2_048,
                    bytesOut: 512
                )
            ], sampledAt: sampledAt)

            let summary = store.summary(for: .sevenDays, customFrom: sampledAt, customTo: sampledAt)
            check(summary.sampleCount == 1, "weekly range missed a prior-day sample")
            check(summary.totalBytes == 2_560, "weekly total is wrong")
            check(summary.apps.map(\.process) == ["Mail"], "weekly app aggregation is wrong")
        }
    }

    private static func verifyHistoricalSummaryHandlesLargeTotals() {
        withStore { store in
            let sampledAt = Date(timeIntervalSince1970: 1_700_000_000)
            let largeValue: Int64 = 5_000_000_000_000_000_000
            try store.append([
                record(process: "Safari", bytesIn: largeValue, bytesOut: 0, at: sampledAt)
            ], sampledAt: sampledAt)
            try store.append([
                record(
                    process: "Safari",
                    bytesIn: 0,
                    bytesOut: largeValue,
                    at: sampledAt.addingTimeInterval(1)
                )
            ], sampledAt: sampledAt.addingTimeInterval(1))

            let summary = store.summary(
                for: .custom,
                customFrom: sampledAt,
                customTo: sampledAt.addingTimeInterval(1)
            )
            check(summary.totalBytes == Int64.max, "historical total overflow was not saturated")
            check(
                summary.points.contains { $0.totalBytes == Int64.max },
                "usage point overflow was not saturated"
            )
            check(summary.apps.first?.totalBytes == Int64.max, "app total overflow was not saturated")

            try store.append([
                record(
                    process: "Mail",
                    bytesIn: largeValue,
                    bytesOut: 0,
                    at: sampledAt.addingTimeInterval(2)
                )
            ], sampledAt: sampledAt.addingTimeInterval(2))
            let directionOverflowSummary = store.summary(
                for: .custom,
                customFrom: sampledAt,
                customTo: sampledAt.addingTimeInterval(2)
            )
            check(
                directionOverflowSummary.bytesIn == Int64.max,
                "historical direction overflow was reported as zero"
            )
            check(
                directionOverflowSummary.totalBytes == Int64.max,
                "historical direction overflow changed the saturated total"
            )

            try store.append([
                record(
                    process: "Safari",
                    bytesIn: largeValue,
                    bytesOut: 0,
                    at: sampledAt.addingTimeInterval(3)
                )
            ], sampledAt: sampledAt.addingTimeInterval(3))
            let processOverflowSummary = store.summary(
                for: .custom,
                customFrom: sampledAt,
                customTo: sampledAt.addingTimeInterval(3)
            )
            check(
                processOverflowSummary.apps.first { $0.process == "Safari" }?.bytesIn == Int64.max,
                "overflowing process aggregate disappeared from app history"
            )
        }

        withStore { store in
            let sampledAt = Date(timeIntervalSince1970: 1_700_000_000)
            let exactValue: Int64 = 9_007_199_254_740_992
            try store.append([
                record(process: "Safari", bytesIn: exactValue, bytesOut: 0, at: sampledAt)
            ], sampledAt: sampledAt)
            try store.append([
                record(
                    process: "Safari",
                    bytesIn: 1,
                    bytesOut: 0,
                    at: sampledAt.addingTimeInterval(1)
                )
            ], sampledAt: sampledAt.addingTimeInterval(1))

            let summary = store.summary(
                for: .custom,
                customFrom: sampledAt,
                customTo: sampledAt.addingTimeInterval(1)
            )
            check(summary.bytesIn == exactValue + 1, "exact historical total lost integer precision")
            check(summary.apps.first?.totalBytes == exactValue + 1, "app ranking total lost integer precision")

            try store.append([
                record(
                    process: "Mail",
                    bytesIn: exactValue,
                    bytesOut: 0,
                    at: sampledAt.addingTimeInterval(2)
                )
            ], sampledAt: sampledAt.addingTimeInterval(2))
            let rankedSummary = store.summary(
                for: .custom,
                customFrom: sampledAt,
                customTo: sampledAt.addingTimeInterval(2)
            )
            check(
                rankedSummary.apps.map(\.process) == ["Safari", "Mail"],
                "large app totals were ranked without integer precision"
            )
        }
    }

    private static func verifyNettopParser() {
        let sampledAt = Date(timeIntervalSince1970: 1_700_000_000)
        let output = """
        time,process,pid,interface,state,bytes_in,bytes_out
        1700000000,Safari,101,en0,ESTABLISHED,1024,512
        1700000000,Mail.202,202,en0,ESTABLISHED,2 KB,1 KB
        """
        let records = NettopParser.parse(output, sampledAt: sampledAt)

        check(records.count == 2, "CSV rows were not parsed")
        check(records[0].process == "Safari" && records[0].pid == 101, "first process was parsed incorrectly")
        check(records[0].bytesIn == 1_024 && records[0].bytesOut == 512, "first process bytes are wrong")
        check(records[1].process == "Mail" && records[1].pid == 202, "PID suffix was parsed incorrectly")
        check(records[1].bytesIn == 2_048 && records[1].bytesOut == 1_024, "unit conversion is wrong")
        check(records[1].timestamp == sampledAt, "parser changed the sample timestamp")
        check(NettopParser.parse("").isEmpty, "empty nettop output should produce no records")

        let streamRecords = NettopParser.parseFrame([
            ",bytes_in,bytes_out,",
            "Safari.101,1024,512,",
            "Shadowrocket.202,2048,1024,"
        ], sampledAt: sampledAt)
        check(streamRecords.map(\.process) == ["Safari", "Shadowrocket"], "stream process rows were not parsed")
        check(streamRecords.map(\.totalBytes) == [1_536, 3_072], "stream byte totals are wrong")
    }

    private static func verifyOversizedNettopValue() {
        let oversizedValue = String(repeating: "9", count: 400)
        let records = NettopParser.parseFrame([
            "Safari.101,\(oversizedValue),1,"
        ])

        check(records.count == 1, "oversized byte field discarded the valid row")
        check(records[0].bytesIn == 0, "oversized byte field was not ignored")
        check(records[0].bytesOut == 1, "valid byte field next to oversized data changed")

        let overflowingTotal = NettopParser.parseFrame([
            "Safari.101,5000000000000000000,5000000000000000000,"
        ])
        check(overflowingTotal.isEmpty, "overflowing row total was accepted")

        let overflowingFrame = NettopParser.parseFrame([
            "Safari.101,5000000000000000000,0,",
            "Mail.202,5000000000000000000,0,"
        ])
        check(overflowingFrame.isEmpty, "overflowing frame total was accepted")
    }

    private static func verifyHistoryBufferStartsEachBatchAtItsFirstRecord() {
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = firstDate.addingTimeInterval(5)
        var buffer = TrafficHistoryBuffer()

        let firstBatch = buffer.append([
            record(process: "Safari", bytesIn: 100, bytesOut: 10, at: firstDate)
        ], at: firstDate, flushInterval: 60)
        checkClose(firstBatch?.sampledAt, firstDate, "first batch timestamp is wrong")
        check(firstBatch?.records.first?.totalBytes == 110, "first batch totals are wrong")
        check(buffer.hasPendingRecords, "batch was cleared before persistence succeeded")

        let retryBatch = buffer.append([], at: firstDate.addingTimeInterval(1), flushInterval: 60)
        checkClose(retryBatch?.sampledAt, firstDate, "failed batch was not available for retry")
        buffer.markPersisted(at: firstDate.addingTimeInterval(1))
        check(!buffer.hasPendingRecords, "persisted batch stayed pending")

        let prematureBatch = buffer.append([
            record(process: "Safari", bytesIn: 200, bytesOut: 20, at: secondDate)
        ], at: secondDate, flushInterval: 60)
        check(prematureBatch == nil, "second batch flushed too early")
        let forcedBatch = buffer.flush()
        checkClose(forcedBatch?.sampledAt, secondDate, "forced batch timestamp is wrong")
        let forcedRetry = buffer.append(
            [],
            at: firstDate.addingTimeInterval(6),
            flushInterval: 60
        )
        checkClose(forcedRetry?.sampledAt, secondDate, "forced batch was not available for retry")
        buffer.markPersisted(at: firstDate.addingTimeInterval(6))

        let thirdDate = firstDate.addingTimeInterval(10)
        let thirdPrematureBatch = buffer.append([
            record(process: "Safari", bytesIn: 300, bytesOut: 30, at: thirdDate)
        ], at: thirdDate, flushInterval: 60)
        check(thirdPrematureBatch == nil, "third batch flushed too early")
        let thirdBatch = buffer.append(
            [],
            at: firstDate.addingTimeInterval(66),
            flushInterval: 60
        )
        checkClose(thirdBatch?.sampledAt, thirdDate, "third batch reused the previous timestamp")
        check(thirdBatch?.records.first?.totalBytes == 330, "third batch totals are wrong")
        buffer.markPersisted(at: firstDate.addingTimeInterval(66))
        check(buffer.flush() == nil, "empty buffer produced a duplicate sample")
    }

    private static func verifyHistoryBufferRejectsOverflowingAccumulation() {
        let sampledAt = Date(timeIntervalSince1970: 1_700_000_000)
        let largeValue: Int64 = 5_000_000_000_000_000_000

        var rejectedInitialBuffer = TrafficHistoryBuffer()
        let rejectedInitialBatch = rejectedInitialBuffer.append([
            record(process: "Safari", bytesIn: largeValue, bytesOut: largeValue, at: sampledAt)
        ], at: sampledAt, flushInterval: 60)
        check(rejectedInitialBatch == nil, "overflowing initial record produced a batch")
        check(!rejectedInitialBuffer.hasPendingRecords, "overflowing initial record stayed pending")
        let nextDate = sampledAt.addingTimeInterval(1)
        let validBatch = rejectedInitialBuffer.append([
            record(process: "Safari", bytesIn: 1, bytesOut: 0, at: nextDate)
        ], at: nextDate, flushInterval: 60)
        checkClose(validBatch?.sampledAt, nextDate, "rejected record changed the next batch timestamp")

        var fieldOverflowBuffer = TrafficHistoryBuffer()
        _ = fieldOverflowBuffer.append([
            record(process: "Safari", bytesIn: largeValue, bytesOut: 0, at: sampledAt)
        ], at: sampledAt, flushInterval: 60)
        let fieldOverflowBatch = fieldOverflowBuffer.append([
            record(process: "Safari", bytesIn: largeValue, bytesOut: 0, at: sampledAt)
        ], at: sampledAt.addingTimeInterval(1), flushInterval: 60)
        check(
            fieldOverflowBatch?.records.first?.bytesIn == largeValue,
            "overflowing byte field corrupted the pending batch"
        )

        var totalOverflowBuffer = TrafficHistoryBuffer()
        _ = totalOverflowBuffer.append([
            record(process: "Safari", bytesIn: largeValue, bytesOut: 0, at: sampledAt)
        ], at: sampledAt, flushInterval: 60)
        let totalOverflowBatch = totalOverflowBuffer.append([
            record(process: "Safari", bytesIn: 0, bytesOut: largeValue, at: sampledAt)
        ], at: sampledAt.addingTimeInterval(1), flushInterval: 60)
        check(
            totalOverflowBatch?.records.first?.bytesOut == 0,
            "overflowing record total corrupted the pending batch"
        )

        var batchOverflowBuffer = TrafficHistoryBuffer()
        _ = batchOverflowBuffer.append([
            record(process: "Safari", bytesIn: largeValue, bytesOut: 0, at: sampledAt)
        ], at: sampledAt, flushInterval: 60)
        let batchOverflowBatch = batchOverflowBuffer.append([
            record(process: "Mail", bytesIn: largeValue, bytesOut: 0, at: sampledAt)
        ], at: sampledAt.addingTimeInterval(1), flushInterval: 60)
        check(
            batchOverflowBatch?.records.map(\.process) == ["Safari"],
            "overflowing batch total blocked the pending batch"
        )
    }

    private static func verifyInvalidDatabasePathIsRejected() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HotspotTrafficInvalidStore-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try TrafficStore(databaseURL: directory)
            fatalError("Verification failed: invalid database path was accepted")
        } catch {
            check(
                error.localizedDescription.contains("数据库"),
                "database open error has no useful context"
            )
        }
    }

    private static func verifyMissingFramesBecomeStale() {
        let frameDate = Date(timeIntervalSince1970: 1_700_000_000)
        var status = CollectorStatus()
        status.isRunning = true
        status.startedAt = frameDate
        status.recordFrame(
            at: frameDate,
            recordCount: 2,
            downloadBytesPerSecond: 100,
            uploadBytesPerSecond: 20
        )

        status.recordMissingFrame(at: frameDate.addingTimeInterval(30))

        checkClose(status.lastSampleAt, frameDate, "heartbeat replaced the last real frame time")
        check(status.downloadBytesPerSecond == 0, "missing frame did not clear download rate")
        check(status.uploadBytesPerSecond == 0, "missing frame did not clear upload rate")
        check(
            status.isStale(at: frameDate.addingTimeInterval(91)),
            "collector stayed healthy without real frames"
        )

        status.recordStorageFailure("database write failed")
        status.recordFrame(
            at: frameDate.addingTimeInterval(92),
            recordCount: 1,
            downloadBytesPerSecond: 10,
            uploadBytesPerSecond: 2
        )
        check(status.errorMessage != nil, "network frame hid the storage failure")
        status.recordStorageSuccess()
        check(status.errorMessage == nil, "successful storage write did not clear its failure")
    }

    private static func verifyWriteFailureIsReported() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HotspotTrafficRejectedWrite-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("traffic.sqlite3")
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try TrafficStore(databaseURL: databaseURL)
            try installRejectingSampleTrigger(at: databaseURL)
            let store = try TrafficStore(databaseURL: databaseURL)

            do {
                try store.append([], sampledAt: Date())
                fatalError("Verification failed: rejected write was reported as successful")
            } catch {
                check(
                    error.localizedDescription.contains("写入"),
                    "database write error has no useful context"
                )
            }
        } catch {
            fatalError("Verification failed: rejected-write fixture failed: \(error)")
        }
    }

    private static func verifyConcurrentStorageAccess() {
        withStore { store in
            let queue = DispatchQueue(label: "verify.concurrent-store", attributes: .concurrent)
            let group = DispatchGroup()
            let sampledAt = Date()

            for index in 0..<20 {
                group.enter()
                queue.async {
                    do {
                        try store.append([
                            TrafficRecord(
                                timestamp: sampledAt.addingTimeInterval(-Double(index)),
                                process: "ConcurrentApp",
                                pid: index + 1,
                                interfaceName: "en0",
                                state: "ESTABLISHED",
                                bytesIn: 1_024,
                                bytesOut: 256
                            )
                        ], sampledAt: sampledAt)
                    } catch {
                        fatalError("Verification failed: concurrent write failed: \(error)")
                    }
                    group.leave()
                }

                group.enter()
                queue.async {
                    _ = store.summary(for: .today, customFrom: sampledAt, customTo: sampledAt)
                    group.leave()
                }
            }

            group.wait()
            let summary = store.summary(for: .today, customFrom: sampledAt, customTo: sampledAt)
            check(summary.sampleCount == 20, "concurrent writes lost samples")
            check(summary.totalBytes == 25_600, "concurrent traffic total is wrong")
        }
    }

    private static func withStore(_ body: (TrafficStore) throws -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HotspotTrafficVerification-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try body(TrafficStore(databaseURL: directory.appendingPathComponent("traffic.sqlite3")))
        } catch {
            fatalError("Verification failed: test database could not open: \(error)")
        }
    }

    private static func record(
        process: String,
        bytesIn: Int64,
        bytesOut: Int64,
        at date: Date
    ) -> TrafficRecord {
        TrafficRecord(
            timestamp: date,
            process: process,
            pid: 101,
            interfaceName: "en0",
            state: "ESTABLISHED",
            bytesIn: bytesIn,
            bytesOut: bytesOut
        )
    }

    private static func installRejectingSampleTrigger(at databaseURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw NSError(domain: "CoreVerification", code: 1)
        }
        defer { sqlite3_close(database) }

        let sql = """
            CREATE TRIGGER reject_sample_insert
            BEFORE INSERT ON samples
            BEGIN
                SELECT RAISE(ABORT, 'forced write failure');
            END;
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "CoreVerification", code: 2)
        }
    }

    private static func checkClose(_ actual: Date?, _ expected: Date, _ message: String) {
        guard let actual else { fatalError(message) }
        check(abs(actual.timeIntervalSince(expected)) < 0.001, message)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Verification failed: \(message)") }
    }
}
