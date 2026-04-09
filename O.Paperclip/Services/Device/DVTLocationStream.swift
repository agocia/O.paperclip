import Foundation

final class DVTLocationStream: DVTStreaming, @unchecked Sendable {
    private var process: Process?
    private var inPipe: Pipe?
    private var outPipe: Pipe?
    private var errPipe: Pipe?
    private var currentHost: String?
    private var currentPort: String?
    private var nextSequence: Int = 1
    private var stdoutBuffer: String = ""
    private let stateLock = NSLock()
    private var isReady = false

    var isRunning: Bool {
        process?.isRunning == true
    }

    deinit {
        stop()
    }

    func start(
        host: String,
        port: String,
        onOutput: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws {
        try start(
            host: host,
            port: port,
            onOutput: onOutput,
            onError: onError,
            onStart: { _ in },
            onExit: onExit
        )
    }

    func start(
        host: String,
        port: String,
        onOutput: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void,
        onStart: @escaping @Sendable (Int32) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws {
        if isRunning, currentHost == host, currentPort == port {
            return
        }

        stop()

        guard let binaryPath = Bundle.main.path(forResource: "dvt-location-stream", ofType: nil) else {
            throw NSError(domain: "DVTLocationStream", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "找不到 dvt-location-stream 執行檔"
            ])
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = [host, port]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self.handleStdoutChunk(text, onOutput: onOutput)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            onError(text)
        }

        p.terminationHandler = { [weak self] proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            self?.invalidateStreamState(resetProcess: true)
            onExit(proc.terminationStatus)
        }

        try p.run()
        process = p
        inPipe = stdin
        outPipe = stdout
        errPipe = stderr
        currentHost = host
        currentPort = port
        nextSequence = 1
        resetBufferedOutput()
        setReady(false)
        onStart(p.processIdentifier)
        do {
            try waitUntilReady(timeout: 8.0)
        } catch {
            stop()
            throw error
        }
    }

    func send(latitude: Double, longitude: Double) throws {
        let sequence = nextSequence
        nextSequence += 1
        let line = String(
            format: "%d,\(AppConstants.Formatting.coordinatePrecision),\(AppConstants.Formatting.coordinatePrecision)\n",
            sequence,
            latitude,
            longitude
        )
        try writeCommand(line, required: true)
    }

    func clear() {
        try? writeCommand("CLEAR\n", required: false)
    }

    func stop() {
        try? writeCommand("QUIT\n", required: false)

        if let p = process, p.isRunning {
            p.terminate()
            Thread.sleep(forTimeInterval: AppConstants.Timeouts.dvtStreamStop)
            if p.isRunning { p.interrupt() }
        }

        outPipe?.fileHandleForReading.readabilityHandler = nil
        errPipe?.fileHandleForReading.readabilityHandler = nil
        invalidateStreamState(resetProcess: true)
        resetBufferedOutput()
        nextSequence = 1
    }

    private func writeCommand(_ command: String, required: Bool) throws {
        guard process?.isRunning == true, let fh = inPipe?.fileHandleForWriting else {
            invalidateStreamState(resetProcess: process?.isRunning != true)
            if required {
                throw NSError(domain: "DVTLocationStream", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "dvt stream stdin 無效"
                ])
            }
            return
        }

        guard let data = command.data(using: .utf8) else { return }
        do {
            try fh.write(contentsOf: data)
        } catch {
            invalidateStreamState(resetProcess: process?.isRunning != true)
            if required {
                throw error
            }
        }
    }

    private func handleStdoutChunk(_ chunk: String, onOutput: @escaping (String) -> Void) {
        stateLock.lock()
        stdoutBuffer += chunk
        while let nl = stdoutBuffer.firstIndex(of: "\n") {
            let line = String(stdoutBuffer[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
            stdoutBuffer.removeSubrange(...nl)
            if line.isEmpty { continue }
            if line == "READY" {
                isReady = true
            }
            stateLock.unlock()
            onOutput(line + "\n")
            stateLock.lock()
        }
        stateLock.unlock()
    }

    private func waitUntilReady(timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if readyState() { return }
            if process?.isRunning != true { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw NSError(domain: "DVTLocationStream", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "dvt-location-stream 啟動逾時"
        ])
    }

    private func invalidateStreamState(resetProcess: Bool = false) {
        stateLock.lock()
        isReady = false
        stdoutBuffer = ""
        stateLock.unlock()
        inPipe = nil
        outPipe = nil
        errPipe = nil
        if resetProcess {
            process = nil
        }
        currentHost = nil
        currentPort = nil
    }

    private func setReady(_ ready: Bool) {
        stateLock.lock()
        isReady = ready
        stateLock.unlock()
    }

    private func readyState() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isReady
    }

    private func resetBufferedOutput() {
        stateLock.lock()
        stdoutBuffer = ""
        stateLock.unlock()
    }
}
