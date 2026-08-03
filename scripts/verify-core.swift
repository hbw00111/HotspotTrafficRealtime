import Foundation

@main
enum CoreVerification {
    static func main() {
        verifyEmptyHeartbeat()
        verifyTrafficAndTunnelStorage()
        verifyWeeklyRange()
        verifyNettopParser()
        print("Core verification passed: 4 checks")
    }

    private static func verifyEmptyHeartbeat() {
        withStore { store in
            let sampledAt = Date()
            store.append([], sampledAt: sampledAt)

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
            store.append([
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
            store.append([
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

    private static func withStore(_ body: (TrafficStore) -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HotspotTrafficVerification-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        body(TrafficStore(databaseURL: directory.appendingPathComponent("traffic.sqlite3")))
    }

    private static func checkClose(_ actual: Date?, _ expected: Date, _ message: String) {
        guard let actual else { fatalError(message) }
        check(abs(actual.timeIntervalSince(expected)) < 0.001, message)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Verification failed: \(message)") }
    }
}
