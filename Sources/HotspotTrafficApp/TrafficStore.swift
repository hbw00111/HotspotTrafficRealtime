import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class TrafficStore {
    private var database: OpaquePointer?
    private let lock = NSLock()
    init(databaseURL: URL? = nil) {
        let pathURL: URL
        if let databaseURL {
            pathURL = databaseURL
        } else {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            pathURL = applicationSupport
                .appendingPathComponent("HotspotTraffic", isDirectory: true)
                .appendingPathComponent("traffic.sqlite3")
        }
        let directory = pathURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = pathURL.path

        let openResult = path.withCString {
            sqlite3_open_v2($0, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        }
        if openResult != SQLITE_OK {
            database = nil
        } else {
            execute("PRAGMA journal_mode = WAL;")
            execute("PRAGMA wal_autocheckpoint = 128;")
            execute("""
                CREATE TABLE IF NOT EXISTS samples (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ts REAL NOT NULL,
                    interface TEXT NOT NULL,
                    process_count INTEGER NOT NULL,
                    bytes_in INTEGER NOT NULL,
                    bytes_out INTEGER NOT NULL,
                    total_bytes INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS process_deltas (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    sample_id INTEGER NOT NULL,
                    ts REAL NOT NULL,
                    process TEXT NOT NULL,
                    pid INTEGER NOT NULL DEFAULT 0,
                    interface TEXT NOT NULL,
                    state TEXT NOT NULL DEFAULT '',
                    bytes_in INTEGER NOT NULL,
                    bytes_out INTEGER NOT NULL,
                    total_bytes INTEGER NOT NULL,
                    is_tunnel INTEGER NOT NULL DEFAULT 0,
                    FOREIGN KEY (sample_id) REFERENCES samples(id)
                );
                CREATE INDEX IF NOT EXISTS idx_process_deltas_ts ON process_deltas(ts);
                CREATE INDEX IF NOT EXISTS idx_process_deltas_process_ts ON process_deltas(process, ts);
                CREATE INDEX IF NOT EXISTS idx_process_deltas_tunnel_ts ON process_deltas(is_tunnel, ts);
            """)
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func append(_ records: [TrafficRecord], sampledAt: Date) {
        let rows = records.filter { $0.totalBytes > 0 }
        let grouped = Dictionary(grouping: rows) { record in
            Int64((record.timestamp.timeIntervalSince1970 * 1000).rounded())
        }

        lock.lock()
        defer { lock.unlock() }
        execute("BEGIN")
        defer { execute("COMMIT") }

        guard let sampleStatement = prepare("""
            INSERT INTO samples (ts, interface, process_count, bytes_in, bytes_out, total_bytes)
            VALUES (?, ?, ?, ?, ?, ?)
        """), let processStatement = prepare("""
            INSERT INTO process_deltas
                (sample_id, ts, process, pid, interface, state, bytes_in, bytes_out, total_bytes, is_tunnel)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """) else { return }
        defer {
            sqlite3_finalize(sampleStatement)
            sqlite3_finalize(processStatement)
        }

        guard !grouped.isEmpty else {
            _ = insertSample(
                using: sampleStatement,
                timestamp: sampledAt,
                interface: "expensive",
                processCount: 0,
                bytesIn: 0,
                bytesOut: 0
            )
            return
        }

        for group in grouped.values {
            guard let first = group.first else { continue }
            let bytesIn = group.reduce(0) { $0 + $1.bytesIn }
            let bytesOut = group.reduce(0) { $0 + $1.bytesOut }
            guard let sampleID = insertSample(
                using: sampleStatement,
                timestamp: first.timestamp,
                interface: first.interfaceName,
                processCount: group.count,
                bytesIn: bytesIn,
                bytesOut: bytesOut
            ) else { continue }

            for record in group {
                reset(processStatement)
                sqlite3_bind_int64(processStatement, 1, sampleID)
                sqlite3_bind_double(processStatement, 2, record.timestamp.timeIntervalSince1970)
                bindText(processStatement, 3, record.process)
                sqlite3_bind_int64(processStatement, 4, Int64(record.pid))
                bindText(processStatement, 5, record.interfaceName)
                bindText(processStatement, 6, record.state)
                sqlite3_bind_int64(processStatement, 7, record.bytesIn)
                sqlite3_bind_int64(processStatement, 8, record.bytesOut)
                sqlite3_bind_int64(processStatement, 9, record.totalBytes)
                sqlite3_bind_int64(processStatement, 10, isTunnelProcess(record.process) ? 1 : 0)
                _ = sqlite3_step(processStatement)
            }
        }
    }

    private func insertSample(
        using statement: OpaquePointer?,
        timestamp: Date,
        interface: String,
        processCount: Int,
        bytesIn: Int64,
        bytesOut: Int64
    ) -> Int64? {
        reset(statement)
        sqlite3_bind_double(statement, 1, timestamp.timeIntervalSince1970)
        bindText(statement, 2, interface)
        sqlite3_bind_int64(statement, 3, Int64(processCount))
        sqlite3_bind_int64(statement, 4, bytesIn)
        sqlite3_bind_int64(statement, 5, bytesOut)
        sqlite3_bind_int64(statement, 6, bytesIn + bytesOut)
        guard sqlite3_step(statement) == SQLITE_DONE else { return nil }
        return sqlite3_last_insert_rowid(database)
    }

    func summary(for range: TrafficRange, customFrom: Date, customTo: Date) -> TrafficSummary {
        let bounds = range.bounds(from: customFrom, to: customTo)
        lock.lock()
        defer { lock.unlock() }

        let metadata = summaryMetadata(from: bounds)
        guard metadata.sampleCount > 0 else { return .empty }

        let appTotals = totals(from: bounds, isTunnel: false)
        let tunnelTotals = totals(from: bounds, isTunnel: true)
        let points = usagePoints(for: range, bounds: bounds)
        let apps = aggregateApps(from: bounds, isTunnel: false)
        let tunnels = aggregateApps(from: bounds, isTunnel: true)

        return TrafficSummary(
            points: points,
            apps: apps,
            tunnels: tunnels,
            totalBytes: appTotals.totalBytes,
            bytesIn: appTotals.bytesIn,
            bytesOut: appTotals.bytesOut,
            tunnelBytes: tunnelTotals.totalBytes,
            tunnelIn: tunnelTotals.bytesIn,
            tunnelOut: tunnelTotals.bytesOut,
            tunnelProcesses: tunnels.map(\.process).sorted(),
            sampleCount: metadata.sampleCount,
            lastSample: metadata.lastSample,
            isPreview: false
        )
    }

    private struct SummaryMetadata {
        let sampleCount: Int
        let lastSample: Date?
    }

    private struct Totals {
        let bytesIn: Int64
        let bytesOut: Int64

        var totalBytes: Int64 { bytesIn + bytesOut }
    }

    private func summaryMetadata(from bounds: DateBounds) -> SummaryMetadata {
        guard let statement = prepare("""
            SELECT COUNT(*), MAX(ts)
            FROM samples
            WHERE ts >= ? AND ts < ?
        """) else { return SummaryMetadata(sampleCount: 0, lastSample: nil) }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, bounds.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, bounds.end.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return SummaryMetadata(sampleCount: 0, lastSample: nil)
        }

        let lastSample = sqlite3_column_type(statement, 1) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        return SummaryMetadata(
            sampleCount: Int(sqlite3_column_int64(statement, 0)),
            lastSample: lastSample
        )
    }

    private func totals(from bounds: DateBounds, isTunnel: Bool) -> Totals {
        guard let statement = prepare("""
            SELECT COALESCE(SUM(bytes_in), 0), COALESCE(SUM(bytes_out), 0)
            FROM process_deltas
            WHERE ts >= ? AND ts < ? AND is_tunnel = ?
        """) else { return Totals(bytesIn: 0, bytesOut: 0) }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, bounds.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, bounds.end.timeIntervalSince1970)
        sqlite3_bind_int(statement, 3, isTunnel ? 1 : 0)
        guard sqlite3_step(statement) == SQLITE_ROW else { return Totals(bytesIn: 0, bytesOut: 0) }
        return Totals(
            bytesIn: sqlite3_column_int64(statement, 0),
            bytesOut: sqlite3_column_int64(statement, 1)
        )
    }

    private func usagePoints(for range: TrafficRange, bounds: DateBounds) -> [UsagePoint] {
        guard let statement = prepare("""
            SELECT
                COALESCE(SUM(bytes_in), 0),
                COALESCE(SUM(bytes_out), 0),
                COUNT(DISTINCT process)
            FROM process_deltas
            WHERE ts >= ? AND ts < ? AND is_tunnel = 0
        """) else { return [] }
        defer { sqlite3_finalize(statement) }

        let calendar = Calendar.current
        let component: Calendar.Component = range == .today ? .hour : .day
        let count = range == .today ? 24 : daysBetween(bounds.start, bounds.end, calendar: calendar)
        let start = calendar.startOfDay(for: bounds.start)

        return (0..<count).map { offset in
            let date = calendar.date(byAdding: component, value: offset, to: start) ?? start
            let next = calendar.date(byAdding: component, value: 1, to: date) ?? date
            reset(statement)
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, next.timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return UsagePoint(date: date, label: "", totalBytes: 0, bytesIn: 0, bytesOut: 0, activeApps: 0)
            }

            let bytesIn = sqlite3_column_int64(statement, 0)
            let bytesOut = sqlite3_column_int64(statement, 1)
            return UsagePoint(
                date: date,
                label: dateLabel(date, format: range == .today ? "HH:mm" : "M/d"),
                totalBytes: bytesIn + bytesOut,
                bytesIn: bytesIn,
                bytesOut: bytesOut,
                activeApps: Int(sqlite3_column_int64(statement, 2))
            )
        }
    }

    private func daysBetween(_ start: Date, _ end: Date, calendar: Calendar) -> Int {
        let firstDay = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end.addingTimeInterval(-1))
        return max((calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1, 1)
    }

    private func aggregateApps(from bounds: DateBounds, isTunnel: Bool) -> [AppUsage] {
        guard let statement = prepare("""
            SELECT
                process,
                COALESCE(SUM(bytes_in), 0),
                COALESCE(SUM(bytes_out), 0),
                COUNT(DISTINCT date(ts, 'unixepoch', 'localtime')),
                MAX(ts),
                COUNT(*)
            FROM process_deltas
            WHERE ts >= ? AND ts < ? AND is_tunnel = ?
            GROUP BY process
            ORDER BY SUM(total_bytes) DESC
        """) else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, bounds.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, bounds.end.timeIntervalSince1970)
        sqlite3_bind_int(statement, 3, isTunnel ? 1 : 0)

        var apps: [AppUsage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let process = columnText(statement, 0)
            let lastSeen = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            apps.append(AppUsage(
                process: process,
                category: category(for: process),
                bytesIn: sqlite3_column_int64(statement, 1),
                bytesOut: sqlite3_column_int64(statement, 2),
                activeDays: Int(sqlite3_column_int64(statement, 3)),
                lastSeen: lastSeen,
                sampleCount: Int(sqlite3_column_int64(statement, 5)),
                colorIndex: apps.count
            ))
        }
        return apps
    }

    private func category(for process: String) -> String {
        let name = process.lowercased()
        if isTunnelProcess(process) { return "隧道" }
        if name.range(of: "safari|chrome|firefox|arc|edge|webkit", options: .regularExpression) != nil { return "浏览器" }
        if name.range(of: "wechat|weixin|qq|telegram|discord|slack|messages|mail", options: .regularExpression) != nil { return "通讯" }
        if name.range(of: "spotify|music|youtube|tv|podcast|netflix|bilibili", options: .regularExpression) != nil { return "媒体" }
        if name.range(of: "code|xcode|terminal|iterm|ssh|docker|npm|node|python|git", options: .regularExpression) != nil { return "开发" }
        if name.range(of: "icloud|cloudd|onedrive|dropbox|drive|backup|syncthing", options: .regularExpression) != nil { return "同步" }
        if name.range(of: "apple|launchd|mdns|apsd|rapportd|identity|trustd|softwareupdated", options: .regularExpression) != nil { return "系统" }
        return "其他"
    }

    private func dateLabel(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func execute(_ sql: String) {
        _ = sql.withCString { sqlite3_exec(database, $0, nil, nil, nil) }
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        let result = sql.withCString { sqlite3_prepare_v2(database, $0, -1, &statement, nil) }
        guard result == SQLITE_OK else { return nil }
        return statement
    }

    private func reset(_ statement: OpaquePointer?) {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) }
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }
}

func isTunnelProcess(_ process: String) -> Bool {
    process.range(of: "macpackettunnel|shadowrocket|packet[ -]?tunnel|tun2socks|clash|mihomo|surge", options: [.regularExpression, .caseInsensitive]) != nil
}
