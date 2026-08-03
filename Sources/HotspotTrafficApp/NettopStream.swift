import Foundation

final class NettopStream {
    var onFrame: (([String], Date) -> Void)?
    var onFailure: ((String) -> Void)?

    private let sampleInterval: Int
    private let queue = DispatchQueue(label: "local.hotspot-traffic.nettop", qos: .utility)
    private let frameDebounce: TimeInterval = 0.12

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var lineBuffer = Data()
    private var frameLines: [String] = []
    private var frameOpen = false
    private var droppedInitialFrame = false
    private var flushWork: DispatchWorkItem?
    private var shouldRun = false

    init(sampleInterval: TimeInterval) {
        self.sampleInterval = max(Int(sampleInterval.rounded()), 1)
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.shouldRun else { return }
            self.shouldRun = true
            self.launch()
        }
    }

    func stop() {
        queue.async {
            self.shouldRun = false
            self.process?.terminationHandler = nil
            if let process = self.process {
                self.terminateProcessTree(process)
            }
            self.process = nil
            self.releaseHandles()
        }
    }

    private func launch() {
        guard shouldRun, process == nil else { return }

        let task = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        task.arguments = [
            "-q", "/dev/null",
            "/usr/bin/nettop",
            "-P",
            "-d",
            "-L", "0",
            "-J", "bytes_in,bytes_out",
            "-x",
            "-n",
            "-t", "external",
            "-s", "\(sampleInterval)",
            "-c"
        ]
        task.qualityOfService = .utility
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = stderr

        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr
        resetFrameState()

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.queue.async { self?.consume(data) }
        }

        task.terminationHandler = { [weak self] finishedProcess in
            self?.queue.async {
                self?.handleTermination(finishedProcess)
            }
        }

        do {
            try task.run()
            process = task
        } catch {
            releaseHandles()
            guard shouldRun else { return }
            onFailure?("nettop 启动失败：\(error.localizedDescription)")
            scheduleRestart(after: 1)
        }
    }

    private func handleTermination(_ finishedProcess: Process) {
        guard process === finishedProcess else { return }
        let exitCode = finishedProcess.terminationStatus
        process = nil
        releaseHandles()
        guard shouldRun else { return }
        onFailure?("nettop 意外退出，状态码 \(exitCode)")
        scheduleRestart(after: 1)
    }

    private func terminateProcessTree(_ task: Process) {
        let processID = task.processIdentifier
        guard processID > 0 else {
            task.terminate()
            return
        }

        let childTerminator = Process()
        childTerminator.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        childTerminator.arguments = ["-TERM", "-P", "\(processID)"]
        try? childTerminator.run()
        childTerminator.waitUntilExit()
        task.terminate()
    }

    private func scheduleRestart(after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.launch()
        }
    }

    private func consume(_ data: Data) {
        guard shouldRun else { return }
        lineBuffer.append(data)
        if lineBuffer.count > 1_048_576 {
            lineBuffer.removeAll(keepingCapacity: true)
            return
        }

        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer[lineBuffer.startIndex..<newline]
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !line.isEmpty else { continue }

            if isFrameHeader(line) {
                flushFrame()
                frameOpen = true
                scheduleFrameFlush()
            } else {
                frameOpen = true
                frameLines.append(line)
                scheduleFrameFlush()
            }
        }
    }

    private func isFrameHeader(_ line: String) -> Bool {
        let normalized = line.lowercased()
        return normalized.contains("bytes_in") && normalized.contains("bytes_out")
    }

    private func scheduleFrameFlush() {
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushFrame()
        }
        flushWork = work
        queue.asyncAfter(deadline: .now() + frameDebounce, execute: work)
    }

    private func flushFrame() {
        guard frameOpen else { return }
        flushWork?.cancel()
        flushWork = nil
        frameOpen = false
        let frame = frameLines
        frameLines.removeAll(keepingCapacity: true)

        guard droppedInitialFrame else {
            droppedInitialFrame = true
            return
        }
        guard shouldRun else { return }
        onFrame?(frame, Date())
    }

    private func resetFrameState() {
        flushWork?.cancel()
        flushWork = nil
        lineBuffer.removeAll(keepingCapacity: true)
        frameLines.removeAll(keepingCapacity: true)
        frameOpen = false
        droppedInitialFrame = false
    }

    private func releaseHandles() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        flushWork?.cancel()
        flushWork = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        resetFrameState()
    }
}
