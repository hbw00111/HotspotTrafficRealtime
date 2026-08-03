import Foundation

enum TrafficRange: String, CaseIterable, Identifiable {
    case today
    case sevenDays
    case thirtyDays
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今天"
        case .sevenDays: return "7 天"
        case .thirtyDays: return "30 天"
        case .custom: return "自定义"
        }
    }
}

struct DateBounds {
    let start: Date
    let end: Date
}

extension TrafficRange {
    func bounds(from customFrom: Date, to customTo: Date, calendar: Calendar = .current) -> DateBounds {
        let now = Date()
        let today = calendar.startOfDay(for: now)

        switch self {
        case .today:
            return DateBounds(start: today, end: now)
        case .sevenDays:
            return DateBounds(
                start: calendar.date(byAdding: .day, value: -6, to: today) ?? today,
                end: now
            )
        case .thirtyDays:
            return DateBounds(
                start: calendar.date(byAdding: .day, value: -29, to: today) ?? today,
                end: now
            )
        case .custom:
            let start = calendar.startOfDay(for: min(customFrom, customTo))
            let endDay = calendar.startOfDay(for: max(customFrom, customTo))
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return DateBounds(start: start, end: end)
        }
    }
}

struct TrafficRecord {
    let timestamp: Date
    let process: String
    let pid: Int
    let interfaceName: String
    let state: String
    let bytesIn: Int64
    let bytesOut: Int64

    var totalBytes: Int64 { bytesIn + bytesOut }
}

struct UsagePoint: Identifiable {
    let date: Date
    let label: String
    let totalBytes: Int64
    let bytesIn: Int64
    let bytesOut: Int64
    let activeApps: Int

    var id: Date { date }
}

struct AppUsage: Identifiable {
    let process: String
    let category: String
    let bytesIn: Int64
    let bytesOut: Int64
    let activeDays: Int
    let lastSeen: Date?
    let sampleCount: Int
    let colorIndex: Int

    var id: String { process }
    var totalBytes: Int64 { bytesIn + bytesOut }
}

struct TrafficSummary {
    let points: [UsagePoint]
    let apps: [AppUsage]
    let tunnels: [AppUsage]
    let totalBytes: Int64
    let bytesIn: Int64
    let bytesOut: Int64
    let tunnelBytes: Int64
    let tunnelIn: Int64
    let tunnelOut: Int64
    let tunnelProcesses: [String]
    let sampleCount: Int
    let lastSample: Date?
    let isPreview: Bool

    static let empty = TrafficSummary(
        points: [],
        apps: [],
        tunnels: [],
        totalBytes: 0,
        bytesIn: 0,
        bytesOut: 0,
        tunnelBytes: 0,
        tunnelIn: 0,
        tunnelOut: 0,
        tunnelProcesses: [],
        sampleCount: 0,
        lastSample: nil,
        isPreview: false
    )
}

struct CollectorStatus {
    var isRunning = false
    var startedAt: Date?
    var lastSampleAt: Date?
    var lastRecordCount = 0
    var downloadBytesPerSecond: Int64 = 0
    var uploadBytesPerSecond: Int64 = 0
    var rateUpdatedAt: Date?
    var pollInterval: TimeInterval = 0
    var usesLowPowerPolling = false
    var errorMessage: String?

    var isStale: Bool {
        guard isRunning else { return false }
        guard let referenceDate = lastSampleAt ?? startedAt else { return true }
        let gracePeriod = max(pollInterval * 3, 90)
        return Date().timeIntervalSince(referenceDate) > gracePeriod
    }

    var isHealthy: Bool {
        isRunning && errorMessage == nil && !isStale
    }
}
