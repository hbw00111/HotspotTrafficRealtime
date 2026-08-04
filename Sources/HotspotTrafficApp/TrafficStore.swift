import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum TrafficStoreError: LocalizedError {
    case applicationSupportUnavailable
    case directoryCreationFailed(path: String, reason: String)
    case databaseOpenFailed(path: String, reason: String)
    case databaseSetupFailed(path: String, reason: String)
    case databaseWriteFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "找不到本地应用数据目录"
        case let .directoryCreationFailed(path, reason):
            return "流量数据库目录创建失败（\(path)）：\(reason)"
        case let .databaseOpenFailed(path, reason):
            return "流量数据库打开失败（\(path)）：\(reason)"
        case let .databaseSetupFailed(path, reason):
            return "流量数据库初始化失败（\(path)）：\(reason)"
        case let .databaseWriteFailed(reason):
            return "流量数据库写入失败：\(reason)"
        }
    }
}

final class TrafficStore: @unchecked Sendable {
    private var database: OpaquePointer?
    private let lock = NSLock()

    init(databaseURL: URL? = nil) throws {
        let pathURL: URL
        if let databaseURL {
            pathURL = databaseURL
        } else {
            guard let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw TrafficStoreError.applicationSupportUnavailable
            }
            pathURL = applicationSupport
                .appendingPathComponent("HotspotTraffic", isDirectory: true)
                .appendingPathComponent("traffic.sqlite3")
        }
        let directory = pathURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw TrafficStoreError.directoryCreationFailed(
                path: directory.path,
                reason: error.localizedDescription
            )
        }
        let path = pathURL.path

        let openResult = path.withCString {
            sqlite3_open_v2($0, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        }
        guard openResult == SQLITE_OK else {
            let reason = databaseErrorMessage
            if let database { sqlite3_close(database) }
            database = nil
            throw TrafficStoreError.databaseOpenFailed(path: path, reason: reason)
        }

        sqlite3_busy_timeout(database, 2_000)
        let setupResult = execute("""
            PRAGMA journal_mode = WAL;
            PRAGMA wal_autocheckpoint = 128;
            PRAGMA foreign_keys = ON;
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
        guard setupResult == SQLITE_OK else {
            let reason = databaseErrorMessage
            if let database { sqlite3_close(database) }
            database = nil
            throw TrafficStoreError.databaseSetupFailed(path: path, reason: reason)
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func append(_ records: [TrafficRecord], sampledAt: Date) throws {
        let rows = records.filter { $0.bytesIn > 0 || $0.bytesOut > 0 }
        let grouped = Dictionary(grouping: rows) { record in
            Int64((record.timestamp.timeIntervalSince1970 * 1000).rounded())
        }

        lock.lock()
        defer { lock.unlock() }
        guard execute("BEGIN IMMEDIATE") == SQLITE_OK else {
            throw writeError("无法开始事务")
        }
        var shouldRollback = true
        defer {
            if shouldRollback { execute("ROLLBACK") }
        }

        guard let sampleStatement = prepare("""
            INSERT INTO samples (ts, interface, process_count, bytes_in, bytes_out, total_bytes)
            VALUES (?, ?, ?, ?, ?, ?)
        """) else {
            throw writeError("无法准备采样写入")
        }
        defer { sqlite3_finalize(sampleStatement) }

        guard let processStatement = prepare("""
            INSERT INTO process_deltas
                (sample_id, ts, process, pid, interface, state, bytes_in, bytes_out, total_bytes, is_tunnel)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """) else {
            throw writeError("无法准备进程写入")
        }
        defer { sqlite3_finalize(processStatement) }

        guard !grouped.isEmpty else {
            _ = try insertSample(
                using: sampleStatement,
                timestamp: sampledAt,
                interface: "expensive",
                processCount: 0,
                bytesIn: 0,
                bytesOut: 0
            )
            try commitWrite()
            shouldRollback = false
            return
        }

        for group in grouped.values {
            guard let first = group.first else { continue }
            let bytesIn = try sum(group.map(\.bytesIn))
            let bytesOut = try sum(group.map(\.bytesOut))
            let sampleID = try insertSample(
                using: sampleStatement,
                timestamp: first.timestamp,
                interface: first.interfaceName,
                processCount: group.count,
                bytesIn: bytesIn,
                bytesOut: bytesOut
            )

            for record in group {
                let totalBytes = try sum([record.bytesIn, record.bytesOut])
                reset(processStatement)
                sqlite3_bind_int64(processStatement, 1, sampleID)
                sqlite3_bind_double(processStatement, 2, record.timestamp.timeIntervalSince1970)
                bindText(processStatement, 3, record.process)
                sqlite3_bind_int64(processStatement, 4, Int64(record.pid))
                bindText(processStatement, 5, record.interfaceName)
                bindText(processStatement, 6, record.state)
                sqlite3_bind_int64(processStatement, 7, record.bytesIn)
                sqlite3_bind_int64(processStatement, 8, record.bytesOut)
                sqlite3_bind_int64(processStatement, 9, totalBytes)
                sqlite3_bind_int64(processStatement, 10, isTunnelProcess(record.process) ? 1 : 0)
                guard sqlite3_step(processStatement) == SQLITE_DONE else {
                    throw writeError("进程记录写入被拒绝")
                }
            }
        }
        try commitWrite()
        shouldRollback = false
    }

    private func insertSample(
        using statement: OpaquePointer?,
        timestamp: Date,
        interface: String,
        processCount: Int,
        bytesIn: Int64,
        bytesOut: Int64
    ) throws -> Int64 {
        let totalBytes = try sum([bytesIn, bytesOut])
        reset(statement)
        sqlite3_bind_double(statement, 1, timestamp.timeIntervalSince1970)
        bindText(statement, 2, interface)
        sqlite3_bind_int64(statement, 3, Int64(processCount))
        sqlite3_bind_int64(statement, 4, bytesIn)
        sqlite3_bind_int64(statement, 5, bytesOut)
        sqlite3_bind_int64(statement, 6, totalBytes)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw writeError("采样记录写入被拒绝")
        }
        return sqlite3_last_insert_rowid(database)
    }

    private func commitWrite() throws {
        guard execute("COMMIT") == SQLITE_OK else {
            throw writeError("事务提交失败")
        }
    }

    private func sum(_ values: [Int64]) throws -> Int64 {
        guard let total = ByteCount.sum(values) else {
            throw TrafficStoreError.databaseWriteFailed(reason: "字节计数超出范围")
        }
        return total
    }

    private func writeError(_ context: String) -> TrafficStoreError {
        .databaseWriteFailed(reason: "\(context)：\(databaseErrorMessage)")
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

        var totalBytes: Int64 { ByteCount.saturatedAdding(bytesIn, bytesOut) }
    }

    private enum StoredByteColumn: String {
        case bytesIn = "bytes_in"
        case bytesOut = "bytes_out"
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

    private func totals(from bounds: DateBounds, isTunnel: Bool, process: String? = nil) -> Totals {
        let statement: OpaquePointer?
        if process == nil {
            statement = prepare("""
                SELECT SUM(bytes_in), SUM(bytes_out)
                FROM process_deltas
                WHERE ts >= ? AND ts < ? AND is_tunnel = ?
            """)
        } else {
            statement = prepare("""
                SELECT SUM(bytes_in), SUM(bytes_out)
                FROM process_deltas
                WHERE ts >= ? AND ts < ? AND is_tunnel = ? AND process = ?
            """)
        }
        guard let statement else { return Totals(bytesIn: 0, bytesOut: 0) }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, bounds.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, bounds.end.timeIntervalSince1970)
        sqlite3_bind_int(statement, 3, isTunnel ? 1 : 0)
        if let process { bindText(statement, 4, process) }
        if sqlite3_step(statement) == SQLITE_ROW {
            return Totals(
                bytesIn: sqlite3_column_int64(statement, 0),
                bytesOut: sqlite3_column_int64(statement, 1)
            )
        }
        return Totals(
            bytesIn: storedByteTotal(.bytesIn, from: bounds, isTunnel: isTunnel, process: process),
            bytesOut: storedByteTotal(.bytesOut, from: bounds, isTunnel: isTunnel, process: process)
        )
    }

    private func usagePoints(for range: TrafficRange, bounds: DateBounds) -> [UsagePoint] {
        guard let statement = prepare("""
            SELECT
                SUM(bytes_in),
                SUM(bytes_out),
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

            let result = sqlite3_step(statement)
            let pointBounds = DateBounds(start: date, end: next)
            let pointTotals = result == SQLITE_ROW
                ? Totals(
                    bytesIn: sqlite3_column_int64(statement, 0),
                    bytesOut: sqlite3_column_int64(statement, 1)
                )
                : totals(from: pointBounds, isTunnel: false)
            let activeApps = result == SQLITE_ROW
                ? Int(sqlite3_column_int64(statement, 2))
                : activeProcessCount(from: pointBounds)
            return UsagePoint(
                date: date,
                label: dateLabel(date, format: range == .today ? "HH:mm" : "M/d"),
                totalBytes: pointTotals.totalBytes,
                bytesIn: pointTotals.bytesIn,
                bytesOut: pointTotals.bytesOut,
                activeApps: activeApps
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
                SUM(bytes_in),
                SUM(bytes_out),
                COUNT(DISTINCT date(ts, 'unixepoch', 'localtime')),
                MAX(ts),
                COUNT(*)
            FROM process_deltas
            WHERE ts >= ? AND ts < ? AND is_tunnel = ?
            GROUP BY process
        """) else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, bounds.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, bounds.end.timeIntervalSince1970)
        sqlite3_bind_int(statement, 3, isTunnel ? 1 : 0)

        var apps: [AppUsage] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
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
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else {
            return aggregateAppsAfterOverflow(from: bounds, isTunnel: isTunnel)
        }
        return rank(apps)
    }

    private func aggregateAppsAfterOverflow(from bounds: DateBounds, isTunnel: Bool) -> [AppUsage] {
        guard let statement = prepare("""
            SELECT
                process,
                COUNT(DISTINCT date(ts, 'unixepoch', 'localtime')),
                MAX(ts),
                COUNT(*)
            FROM process_deltas
            WHERE ts >= ? AND ts < ? AND is_tunnel = ?
            GROUP BY process
        """) else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, bounds.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, bounds.end.timeIntervalSince1970)
        sqlite3_bind_int(statement, 3, isTunnel ? 1 : 0)

        var apps: [AppUsage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let process = columnText(statement, 0)
            let processTotals = totals(from: bounds, isTunnel: isTunnel, process: process)
            let lastSeen = sqlite3_column_type(statement, 2) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            apps.append(AppUsage(
                process: process,
                category: category(for: process),
                bytesIn: processTotals.bytesIn,
                bytesOut: processTotals.bytesOut,
                activeDays: Int(sqlite3_column_int64(statement, 1)),
                lastSeen: lastSeen,
                sampleCount: Int(sqlite3_column_int64(statement, 3)),
                colorIndex: apps.count
            ))
        }
        return rank(apps)
    }

    private func rank(_ apps: [AppUsage]) -> [AppUsage] {
        apps.sorted {
            if $0.totalBytes != $1.totalBytes { return $0.totalBytes > $1.totalBytes }
            return $0.process.localizedCaseInsensitiveCompare($1.process) == .orderedAscending
        }.enumerated().map { index, app in
            AppUsage(
                process: app.process,
                category: app.category,
                bytesIn: app.bytesIn,
                bytesOut: app.bytesOut,
                activeDays: app.activeDays,
                lastSeen: app.lastSeen,
                sampleCount: app.sampleCount,
                colorIndex: index
            )
        }
    }

    private func activeProcessCount(from bounds: DateBounds) -> Int {
        guard let statement = prepare("""
            SELECT COUNT(DISTINCT process)
            FROM process_deltas
            WHERE ts >= ? AND ts < ? AND is_tunnel = 0
        """) else { return 0 }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, bounds.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, bounds.end.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func storedByteTotal(
        _ column: StoredByteColumn,
        from bounds: DateBounds,
        isTunnel: Bool,
        process: String?
    ) -> Int64 {
        let processFilter = process == nil ? "" : " AND process = ?"
        guard let statement = prepare("""
            SELECT SUM(\(column.rawValue))
            FROM process_deltas
            WHERE ts >= ? AND ts < ? AND is_tunnel = ?\(processFilter)
        """) else { return 0 }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, bounds.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, bounds.end.timeIntervalSince1970)
        sqlite3_bind_int(statement, 3, isTunnel ? 1 : 0)
        if let process { bindText(statement, 4, process) }
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return sqlite3_column_int64(statement, 0) }
        return result == SQLITE_ERROR && databaseErrorMessage.contains("integer overflow") ? Int64.max : 0
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

    @discardableResult
    private func execute(_ sql: String) -> Int32 {
        sql.withCString { sqlite3_exec(database, $0, nil, nil, nil) }
    }

    private var databaseErrorMessage: String {
        guard let database else { return "SQLite 连接不可用" }
        return String(cString: sqlite3_errmsg(database))
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
