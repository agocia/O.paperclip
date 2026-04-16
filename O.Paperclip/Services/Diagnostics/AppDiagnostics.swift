import SwiftUI
import AppKit
import Combine
import Darwin

struct UnexpectedTerminationRecord: Codable {
    let previousSessionID: String
    let startedAt: Date
    let detectedAt: Date
    let reason: String
}

private struct ActiveSessionMarker: Codable {
    let sessionID: String
    let startedAt: Date
    var lastKnownPhase: String
}

enum DiagnosticsPaths {
    private static let appFolderName: String = {
        let bundleID = Bundle.main.bundleIdentifier ?? "O.Paperclip"
        return bundleID.replacingOccurrences(of: ".", with: "-")
    }()

    static var appSupportDirectoryURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = base
            .appendingPathComponent(appFolderName, isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var logsDirectoryURL: URL {
        directoryURL(named: "Logs")
    }

    static func directoryURL(named name: String) -> URL {
        let url = appSupportDirectoryURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func logFileURL(named filename: String) -> URL {
        logsDirectoryURL.appendingPathComponent(filename)
    }

    static var activeSessionURL: URL { logFileURL(named: "active-session.json") }
    static var incidentsURL: URL { logFileURL(named: "incidents.jsonl") }
    static var signalLogURL: URL { logFileURL(named: "crash-signals.log") }
    static var lifecycleLogURL: URL { logFileURL(named: "app-lifecycle.jsonl") }
}

private enum CrashSignalMonitor {
    nonisolated(unsafe) private static var signalLogFD: Int32 = -1
    private static let signalLogStore = RotatingRuntimeLogStore(
        logURL: DiagnosticsPaths.signalLogURL,
        maxBytes: DiagnosticsLogLimits.compactMaxBytes
    )

    static func installIfNeeded() {
        guard signalLogFD == -1 else { return }

        signalLogStore.prepareForAppend(resetIfOversized: true)
        let path = DiagnosticsPaths.signalLogURL.path
        signalLogFD = open(path, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR)
        guard signalLogFD != -1 else { return }

        [SIGABRT, SIGILL, SIGSEGV, SIGBUS, SIGTRAP, SIGFPE].forEach { signal in
            Darwin.signal(signal, signalHandler)
        }
    }

    private static let signalHandler: @convention(c) (Int32) -> Void = { signal in
        guard signalLogFD != -1 else { return }

        let message: StaticString
        switch signal {
        case SIGABRT: message = "SIGABRT\n"
        case SIGILL: message = "SIGILL\n"
        case SIGSEGV: message = "SIGSEGV\n"
        case SIGBUS: message = "SIGBUS\n"
        case SIGTRAP: message = "SIGTRAP\n"
        case SIGFPE: message = "SIGFPE\n"
        default: message = "SIGNAL\n"
        }

        message.withUTF8Buffer { buffer in
            _ = Darwin.write(signalLogFD, buffer.baseAddress, buffer.count)
        }
    }
}

private let uncaughtExceptionLogStore = RotatingRuntimeLogStore(
    logURL: DiagnosticsPaths.logFileURL(named: "uncaught-exceptions.log"),
    maxBytes: DiagnosticsLogLimits.compactMaxBytes
)

@MainActor
final class AppDiagnostics: ObservableObject, DiagnosticsProviding {
    static let shared = AppDiagnostics()

    @Published private(set) var lastUnexpectedTermination: UnexpectedTerminationRecord?

    let logsDirectoryURL = DiagnosticsPaths.logsDirectoryURL

    private var currentSession = ActiveSessionMarker(
        sessionID: UUID().uuidString,
        startedAt: Date(),
        lastKnownPhase: "launching"
    )
    private var didSetup = false
    private var terminationObserver: NSObjectProtocol?
    private let lifecycleLogStore = RotatingRuntimeLogStore(logURL: DiagnosticsPaths.lifecycleLogURL)
    private let incidentsLogStore = RotatingRuntimeLogStore(logURL: DiagnosticsPaths.incidentsURL)

    private init() {}

    func setupIfNeeded() {
        guard !didSetup else { return }
        didSetup = true

        LegacyAppSupportMigrator.migrateIfNeeded()
        lifecycleLogStore.prepareForAppend(resetIfOversized: true)
        incidentsLogStore.prepareForAppend(resetIfOversized: true)
        uncaughtExceptionLogStore.prepareForAppend(resetIfOversized: true)
        CrashSignalMonitor.installIfNeeded()
        installExceptionHandler()
        detectPreviousUnexpectedTermination()
        persistActiveSession()
        appendLifecycleEvent(kind: "launch", metadata: ["sessionID": currentSession.sessionID])

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.markCleanShutdown(reason: "willTerminate")
            }
        }
    }

    func noteScenePhase(_ phase: ScenePhase) {
        currentSession.lastKnownPhase = "\(phase)"
        persistActiveSession()
        appendLifecycleEvent(kind: "scenePhase", metadata: ["phase": "\(phase)"])
    }

    func markCleanShutdown(reason: String) {
        appendLifecycleEvent(kind: "shutdown", metadata: ["reason": reason])
        try? FileManager.default.removeItem(at: DiagnosticsPaths.activeSessionURL)
    }

    func openLogsDirectory() {
        NSWorkspace.shared.open(logsDirectoryURL)
    }

    private func detectPreviousUnexpectedTermination() {
        guard
            let data = try? Data(contentsOf: DiagnosticsPaths.activeSessionURL),
            let previous = try? JSONDecoder().decode(ActiveSessionMarker.self, from: data)
        else {
            return
        }

        let record = UnexpectedTerminationRecord(
            previousSessionID: previous.sessionID,
            startedAt: previous.startedAt,
            detectedAt: Date(),
            reason: "偵測到上一個 session 沒有正常結束，可能是閒置時 crash 或被系統強制終止。"
        )
        lastUnexpectedTermination = record
        appendJSONLine(record, using: incidentsLogStore)
    }

    private func persistActiveSession() {
        guard let data = try? JSONEncoder().encode(currentSession) else { return }
        try? data.write(to: DiagnosticsPaths.activeSessionURL, options: .atomic)
    }

    private func appendLifecycleEvent(kind: String, metadata: [String: String]) {
        let payload = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "kind": kind,
            "sessionID": currentSession.sessionID,
            "metadata": metadata
        ] as [String: Any]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: data, encoding: .utf8)
        else {
            return
        }
        appendLine(line, using: lifecycleLogStore)
    }

    private func appendJSONLine<T: Encodable>(_ value: T, using store: RotatingRuntimeLogStore) {
        guard let data = try? JSONEncoder().encode(value),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        appendLine(line, using: store)
    }

    private func appendLine(_ line: String, using store: RotatingRuntimeLogStore) {
        store.appendLine(line)
    }

    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(exception.name.rawValue): \(exception.reason ?? "unknown")\n"
            uncaughtExceptionLogStore.appendLine(line.trimmingCharacters(in: .newlines))
        }
    }
}
