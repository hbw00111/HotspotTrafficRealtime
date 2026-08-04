import AppKit
import Combine
import Foundation

final class ProcessIconResolver: ObservableObject {
    static let shared = ProcessIconResolver()

    @Published private(set) var revision = 0

    private struct Candidate {
        let url: URL
        let aliases: [String]
    }

    private var cachedIcons: [String: NSImage] = [:]
    private var missingIcons = Set<String>()
    private var installedApps: [Candidate]?

    private init() {
        DispatchQueue.global(qos: .utility).async {
            let applications = Self.loadInstalledApps()
            DispatchQueue.main.async { [weak self] in
                self?.installedApps = applications
                self?.revision += 1
            }
        }
    }

    func icon(for process: String) -> NSImage? {
        let key = Self.normalize(process)
        guard !key.isEmpty else { return nil }
        if let icon = cachedIcons[key] { return icon }
        if missingIcons.contains(key) { return nil }
        guard let installedApps else { return nil }
        if let candidate = bestCandidate(for: key, in: installedApps) {
            let icon = NSWorkspace.shared.icon(forFile: candidate.url.path)
            icon.size = NSSize(width: 64, height: 64)
            cachedIcons[key] = icon
            return icon
        }

        missingIcons.insert(key)
        return nil
    }

    private func bestCandidate(for process: String, in candidates: [Candidate]) -> Candidate? {
        let match = candidates.max {
            Self.score(process: process, aliases: $0.aliases) < Self.score(process: process, aliases: $1.aliases)
        }
        guard let match, Self.score(process: process, aliases: match.aliases) > 0 else { return nil }
        return match
    }

    private static func score(process: String, aliases: [String]) -> Int {
        aliases.reduce(0) { best, alias in
            guard !alias.isEmpty else { return best }
            if process == alias { return max(best, 1_000 + alias.count) }
            if process.hasPrefix(alias), alias.count >= 5 { return max(best, 700 + alias.count) }
            if alias.hasPrefix(process), process.count >= 6 { return max(best, 600 + process.count) }
            if process.contains(alias), alias.count >= 7 { return max(best, 400 + alias.count) }
            return best
        }
    }

    private static func loadInstalledApps() -> [Candidate] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]

        var seen = Set<String>()
        var candidates: [Candidate] = []
        let keys: [URLResourceKey] = [.isDirectoryKey]

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if enumerator.level > 3 {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                guard seen.insert(url.path).inserted else { continue }
                candidates.append(Candidate(url: url, aliases: aliases(for: url)))
            }
        }
        return candidates
    }

    private static func aliases(for url: URL, additional: [String?] = []) -> [String] {
        let bundle = Bundle(url: url)
        let values: [String?] = [
            url.deletingPathExtension().lastPathComponent,
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
            bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
            bundle?.bundleIdentifier
        ] + additional

        return Array(Set(values.compactMap { value in
            guard let value else { return nil }
            let normalized = normalize(value)
            return normalized.isEmpty ? nil : normalized
        }))
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }
}
