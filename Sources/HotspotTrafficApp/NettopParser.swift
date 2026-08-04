import Foundation

enum NettopParser {
    private static let units: [String: Double] = [
        "b": 1,
        "kb": 1024,
        "kib": 1024,
        "mb": 1024 * 1024,
        "mib": 1024 * 1024,
        "gb": 1024 * 1024 * 1024,
        "gib": 1024 * 1024 * 1024,
        "tb": 1024 * 1024 * 1024 * 1024,
        "tib": 1024 * 1024 * 1024 * 1024
    ]

    static func parse(_ output: String, sampledAt: Date = Date()) -> [TrafficRecord] {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let headerIndexes = lines.indices.filter { index in
            let line = lines[index].lowercased()
            return line.contains("bytes_in") && line.contains("bytes_out")
        }
        guard let headerIndex = headerIndexes.last else { return [] }
        guard headerIndex + 1 < lines.count else { return [] }

        let headers = csvFields(lines[headerIndex]).map(normalizeHeader)
        let processIndex = findColumn(headers, names: ["process", "proc", "application", "name"], fallback: 1)
        let pidIndex = findColumn(headers, names: ["pid", "process_id"], fallback: -1)
        let interfaceIndex = findColumn(headers, names: ["interface", "if"], fallback: 2)
        let stateIndex = findColumn(headers, names: ["state"], fallback: 3)
        let bytesInIndex = findColumn(headers, names: ["bytes_in", "bytes_received", "rx_bytes"], fallback: 4)
        let bytesOutIndex = findColumn(headers, names: ["bytes_out", "bytes_sent", "tx_bytes"], fallback: 5)

        let records: [TrafficRecord] = lines[(headerIndex + 1)...].compactMap { line in
            let fields = csvFields(line)
            let maxIndex = max(processIndex, max(bytesInIndex, bytesOutIndex))
            guard maxIndex >= 0, fields.count > maxIndex else { return nil }

            let processInfo = parseProcess(fields[processIndex])
            let explicitPID = pidIndex >= 0 && fields.count > pidIndex ? Int(parseNumber(fields[pidIndex])) : 0
            let bytesIn = parseNumber(fields[bytesInIndex])
            let bytesOut = parseNumber(fields[bytesOutIndex])
            guard hasValidTotal(bytesIn: bytesIn, bytesOut: bytesOut) else { return nil }

            return TrafficRecord(
                timestamp: sampledAt,
                process: processInfo.name,
                pid: explicitPID > 0 ? explicitPID : processInfo.pid,
                interfaceName: field(fields, at: interfaceIndex).isEmpty ? "expensive" : field(fields, at: interfaceIndex),
                state: field(fields, at: stateIndex),
                bytesIn: bytesIn,
                bytesOut: bytesOut
            )
        }
        return hasValidFrameTotal(records) ? records : []
    }

    static func parseFrame(
        _ lines: [String],
        sampledAt: Date = Date(),
        interfaceName: String = "expensive"
    ) -> [TrafficRecord] {
        let records: [TrafficRecord] = lines.compactMap { line in
            let fields = csvFields(line)
            guard fields.count >= 3 else { return nil }

            let processValue = field(fields, at: 0)
            guard !processValue.isEmpty else { return nil }
            let processInfo = parseProcess(processValue)
            let bytesIn = parseNumber(field(fields, at: 1))
            let bytesOut = parseNumber(field(fields, at: 2))
            guard hasValidTotal(bytesIn: bytesIn, bytesOut: bytesOut) else { return nil }

            return TrafficRecord(
                timestamp: sampledAt,
                process: processInfo.name,
                pid: processInfo.pid,
                interfaceName: interfaceName,
                state: "",
                bytesIn: bytesIn,
                bytesOut: bytesOut
            )
        }
        return hasValidFrameTotal(records) ? records : []
    }

    private static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            if character == "\"", quoted, next == "\"" {
                field.append("\"")
                index += 1
            } else if character == "\"" {
                quoted.toggle()
            } else if character == ",", !quoted {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }

        fields.append(field)
        return fields
    }

    private static func normalizeHeader(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    private static func findColumn(_ headers: [String], names: [String], fallback: Int) -> Int {
        names.compactMap { headers.firstIndex(of: $0) }.first ?? fallback
    }

    private static func field(_ fields: [String], at index: Int) -> String {
        guard index >= 0, index < fields.count else { return "" }
        return fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseNumber(_ value: String) -> Int64 {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard !raw.isEmpty, raw != "-", raw != "--" else { return 0 }
        let pattern = #"^([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*([a-zA-Z]+)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let numberRange = Range(match.range(at: 1), in: raw),
              let number = Double(raw[numberRange]) else { return 0 }
        let unit = match.range(at: 2).location == NSNotFound
            ? ""
            : Range(match.range(at: 2), in: raw).map { String(raw[$0]).lowercased() } ?? ""
        let bytes = number * (units[unit.isEmpty ? "b" : unit] ?? 1)
        guard bytes.isFinite, bytes >= 0, bytes < Double(Int64.max) else { return 0 }
        return Int64(bytes.rounded())
    }

    private static func hasValidTotal(bytesIn: Int64, bytesOut: Int64) -> Bool {
        guard let total = ByteCount.adding(bytesIn, bytesOut) else { return false }
        return total > 0
    }

    private static func hasValidFrameTotal(_ records: [TrafficRecord]) -> Bool {
        var bytesIn: Int64 = 0
        var bytesOut: Int64 = 0
        for record in records {
            guard let nextBytesIn = ByteCount.adding(bytesIn, record.bytesIn),
                  let nextBytesOut = ByteCount.adding(bytesOut, record.bytesOut) else { return false }
            bytesIn = nextBytesIn
            bytesOut = nextBytesOut
        }
        return ByteCount.adding(bytesIn, bytesOut) != nil
    }

    private static func parseProcess(_ value: String) -> (name: String, pid: Int) {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dot = raw.lastIndex(of: ".") else { return (raw.isEmpty ? "未知进程" : raw, 0) }
        let suffix = String(raw[raw.index(after: dot)...])
        guard let pid = Int(suffix) else { return (raw.isEmpty ? "未知进程" : raw, 0) }
        let name = String(raw[..<dot])
        return (name.isEmpty ? "未知进程" : name, pid)
    }
}
