import AppKit
import Combine
import Darwin
import Foundation
import MapKit



private enum SimulateLocationMode: String {
    case dvt = "developer dvt"
    case legacy = "developer"

    func clearArgs(host: String, port: String) -> [String] {
        switch self {
        case .dvt:
            ["developer", "dvt", "simulate-location", "clear", "--rsd", host, port]
        case .legacy:
            ["developer", "simulate-location", "clear", "--rsd", host, port]
        }
    }

    func setArgs(host: String, port: String, latitude: Double, longitude: Double) -> [String] {
        let lat = String(format: AppConstants.Formatting.coordinatePrecision, latitude)
        let lon = String(format: AppConstants.Formatting.coordinatePrecision, longitude)
        switch self {
        case .dvt:
            return ["developer", "dvt", "simulate-location", "set", "--rsd", host, port, "--", lat, lon]
        case .legacy:
            return ["developer", "simulate-location", "set", "--rsd", host, port, "--", lat, lon]
        }
    }
}

private enum TunnelTransport: String, CaseIterable {
    case tcp
    case quic
}

private enum TunnelConnectionType: String {
    case usb
    case wifi
}

private final class LockedStringBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ chunk: String) {
        lock.lock()
        text += chunk
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}

private final class LockedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    func append(_ data: Data, toStdErr: Bool) {
        guard !data.isEmpty else { return }
        lock.lock()
        if toStdErr {
            stderr.append(data)
        } else {
            stdout.append(data)
        }
        lock.unlock()
    }

    func strings() -> (stdout: String, stderr: String) {
        lock.lock()
        defer { lock.unlock() }
        return (
            String(data: stdout, encoding: .utf8) ?? "",
            String(data: stderr, encoding: .utf8) ?? ""
        )
    }
}

enum PrivilegedTunnelPIDParser {
    static func parse(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int(trimmed), pid > 0 else { return nil }
        return pid
    }
}

enum DeviceLogRedactor {
    private static let redactedEndpoint = "[RSD REDACTED]"
    private static let redactedHost = "[RSD_HOST]"
    private static let redactedPort = "[RSD_PORT]"

    static func maskedIdentifier(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed.isEmpty ? "[not provided]" : trimmed }
        return "\(trimmed.prefix(4))...\(trimmed.suffix(4))"
    }

    static func maskedEndpoint(host: String, port: String) -> String {
        guard !host.isEmpty, !port.isEmpty else { return redactedEndpoint }
        return redactedEndpoint
    }

    static func sanitizedCommandString(_ args: [String]) -> String {
        var result: [String] = []
        var index = 0

        while index < args.count {
            let arg = args[index]

            if arg == "--udid", index + 1 < args.count {
                result.append(arg)
                result.append(maskedIdentifier(args[index + 1]))
                index += 2
                continue
            }

            if arg == "--rsd", index + 2 < args.count {
                result.append(arg)
                result.append(redactedHost)
                result.append(redactedPort)
                index += 3
                continue
            }

            if arg == "--", index + 2 < args.count,
               let latitude = Double(args[index + 1]),
               let longitude = Double(args[index + 2]),
               looksLikeCoordinatePair(latitude: latitude, longitude: longitude) {
                result.append(arg)
                result.append(String(format: "%.4f", latitude))
                result.append(String(format: "%.4f", longitude))
                index += 3
                continue
            }

            result.append(arg)
            index += 1
        }

        return sanitizedMessage(result.joined(separator: " "))
    }

    static func sanitizedMessage(_ text: String) -> String {
        var value = text
        value = replaceMatches(
            in: value,
            pattern: #"(UDID\s*)([A-Fa-f0-9-]{8,})"#,
            options: [.caseInsensitive]
        ) { match, source in
            let prefix = source.substring(with: match.range(at: 1))
            let identifier = source.substring(with: match.range(at: 2))
            return prefix + maskedIdentifier(identifier)
        }
        value = replaceMatches(
            in: value,
            pattern: #"--udid\s+([^\s]+)"#
        ) { match, source in
            "--udid \(maskedIdentifier(source.substring(with: match.range(at: 1))))"
        }
        value = replaceMatches(
            in: value,
            pattern: #"--rsd\s+([^\s]+)\s+(\d+)"#
        ) { _, _ in
            "--rsd \(redactedHost) \(redactedPort)"
        }
        value = replaceMatches(
            in: value,
            pattern: #"((?:RSD|rsd)[^\n:：]*[:：]\s*)([^\s]+):(\d+)"#
        ) { match, source in
            let prefix = source.substring(with: match.range(at: 1))
            return prefix + redactedEndpoint
        }
        value = replaceMatches(
            in: value,
            pattern: #"(Wi[‑-]?Fi:\s*)([^\)\s]+)"#
        ) { match, source in
            let prefix = source.substring(with: match.range(at: 1))
            let identifier = source.substring(with: match.range(at: 2))
            return prefix + maskedIdentifier(identifier)
        }
        value = replaceMatches(
            in: value,
            pattern: #"((?:localhost|(?:\d{1,3}\.){3}\d{1,3}|[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)):(\d{2,5})"#
        ) { _, _ in
            redactedEndpoint
        }
        value = replaceMatches(
            in: value,
            pattern: #"(-?\d{1,3}\.\d{4,})\s*,\s*(-?\d{1,3}\.\d{4,})"#
        ) { match, source in
            let latitude = Double(source.substring(with: match.range(at: 1)))
            let longitude = Double(source.substring(with: match.range(at: 2)))
            guard let latitude, let longitude,
                  looksLikeCoordinatePair(latitude: latitude, longitude: longitude) else {
                return source.substring(with: match.range)
            }
            return String(format: "%.4f, %.4f", latitude, longitude)
        }
        value = replaceMatches(
            in: value,
            pattern: #"--\s+(-?\d{1,3}\.\d{4,})\s+(-?\d{1,3}\.\d{4,})"#
        ) { match, source in
            let latitude = Double(source.substring(with: match.range(at: 1)))
            let longitude = Double(source.substring(with: match.range(at: 2)))
            guard let latitude, let longitude,
                  looksLikeCoordinatePair(latitude: latitude, longitude: longitude) else {
                return source.substring(with: match.range)
            }
            return String(format: "-- %.4f %.4f", latitude, longitude)
        }
        value = replaceMatches(
            in: value,
            pattern: #"(lat(?:itude)?=)(-?\d{1,3}\.\d{4,})"#,
            options: [.caseInsensitive]
        ) { match, source in
            let prefix = source.substring(with: match.range(at: 1))
            let value = Double(source.substring(with: match.range(at: 2))) ?? 0
            return prefix + String(format: "%.4f", value)
        }
        value = replaceMatches(
            in: value,
            pattern: #"(lon(?:gitude)?=)(-?\d{1,3}\.\d{4,})"#,
            options: [.caseInsensitive]
        ) { match, source in
            let prefix = source.substring(with: match.range(at: 1))
            let value = Double(source.substring(with: match.range(at: 2))) ?? 0
            return prefix + String(format: "%.4f", value)
        }
        return value
    }

    private static func looksLikeCoordinatePair(latitude: Double, longitude: Double) -> Bool {
        abs(latitude) <= 90 && abs(longitude) <= 180
    }

    private static func replaceMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        replacement: (NSTextCheckingResult, NSString) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            mutable.replaceCharacters(in: match.range, with: replacement(match, source))
        }
        return mutable as String
    }
}

final class RotatingRuntimeLogStore: @unchecked Sendable {
    let logURL: URL
    let backupURL: URL
    let maxBytes: UInt64
    private let fileManager: FileManager

    init(logURL: URL, maxBytes: UInt64 = 256 * 1024, fileManager: FileManager = .default) {
        self.logURL = logURL
        self.backupURL = logURL.deletingLastPathComponent().appendingPathComponent(logURL.lastPathComponent + ".1")
        self.maxBytes = maxBytes
        self.fileManager = fileManager
    }

    func appendLine(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        rotateIfNeeded(incomingBytes: UInt64(data.count))

        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: data)
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? (line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    private func rotateIfNeeded(incomingBytes: UInt64) {
        let currentSize = (try? fileManager.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber)?.uint64Value ?? 0
        guard currentSize + incomingBytes > maxBytes else { return }

        try? fileManager.removeItem(at: backupURL)
        if fileManager.fileExists(atPath: logURL.path) {
            try? fileManager.moveItem(at: logURL, to: backupURL)
        }
    }
}

private struct PrivilegedTunnelFiles {
    let directoryURL: URL
    let logURL: URL
    let pidURL: URL
    let stopURL: URL
    let scriptURL: URL

    static func makeDefault() -> Self {
        let directoryURL = DiagnosticsPaths.directoryURL(named: "PrivilegedTunnel")
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        return PrivilegedTunnelFiles(
            directoryURL: directoryURL,
            logURL: directoryURL.appendingPathComponent("opaperclip_tunnel.log"),
            pidURL: directoryURL.appendingPathComponent("opaperclip_tunnel.pid"),
            stopURL: directoryURL.appendingPathComponent("opaperclip_tunnel.stop"),
            scriptURL: directoryURL.appendingPathComponent("opaperclip_tunnel_wrapper.sh")
        )
    }
}

private enum PrivilegedTunnelArtifactPreparer {
    static func prepareReadableArtifacts(
        files: PrivilegedTunnelFiles,
        fileManager: FileManager = .default
    ) {
        for url in [files.logURL, files.pidURL] {
            if !fileManager.fileExists(atPath: url.path) {
                fileManager.createFile(atPath: url.path, contents: Data())
            } else {
                try? Data().write(to: url, options: .atomic)
            }
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
    }
}

struct TunnelOutputParser {
    nonisolated static func endpoint(in text: String) -> (host: String, port: String)? {
        if let host = firstMatch(text, pattern: "RSD\\s+Address:\\s*([^\\s\\n\\r]+)"),
           let port = firstMatch(text, pattern: "RSD\\s+Port:\\s*(\\d+)") {
            return (host.trimmingCharacters(in: .whitespacesAndNewlines), port)
        }

        if let host = firstMatch(text, pattern: "\"host\"\\s*:\\s*\"([^\"]+)\""),
           let port = firstMatch(text, pattern: "\"port\"\\s*:\\s*(\\d+)") {
            return (host.trimmingCharacters(in: .whitespacesAndNewlines), port)
        }

        let lines = text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let pair = lines.compactMap(scriptModeEndpoint(from:)).last {
            return pair
        }

        if let host = firstMatch(text, pattern: "--rsd\\s+([^\\s]+)\\s+(\\d+)") {
            let all = matches(text, pattern: "--rsd\\s+([^\\s]+)\\s+(\\d+)")
            if let last = all.last, last.count == 2 {
                return (last[0].trimmingCharacters(in: .whitespacesAndNewlines), last[1])
            }
            if let port = firstMatch(text, pattern: "--rsd\\s+[^\\s]+\\s+(\\d+)") {
                return (host.trimmingCharacters(in: .whitespacesAndNewlines), port)
            }
        }

        return nil
    }

    nonisolated static func immediateFailure(in text: String) -> String? {
        let lines = text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let fatalMarkers = [
            " error ",
            "error:",
            "exception",
            "traceback",
            "device is not connected",
            "no device connected",
            "requires root privileges",
            "connection refused",
            "timed out",
            "timeout"
        ]
        return lines.last(where: { line in
            let lowered = " " + line.lowercased() + " "
            return fatalMarkers.contains(where: { lowered.contains($0) })
        })
    }

    nonisolated private static func scriptModeEndpoint(from line: String) -> (host: String, port: String)? {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, let port = Int(parts[1]), port > 0 else { return nil }
        let host = String(parts[0])
        guard host == "localhost" || host.contains(".") || host.contains(":") else { return nil }
        return (host, String(port))
    }

    nonisolated private static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let r = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        guard let m = r.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard m.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    nonisolated private static func matches(_ text: String, pattern: String) -> [[String]] {
        guard let r = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = text as NSString
        let result = r.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        return result.map { m in
            (1..<m.numberOfRanges).compactMap { idx in
                let rg = m.range(at: idx)
                guard rg.location != NSNotFound else { return nil }
                return ns.substring(with: rg)
            }
        }
    }
}

enum RemoteBrowseOutputParser {
    nonisolated static func identifiers(in raw: String) -> [String] {
        let jsonIdentifiers = identifiersFromJSON(raw)
        if !jsonIdentifiers.isEmpty {
            return jsonIdentifiers
        }

        guard let regex = try? NSRegularExpression(pattern: #"IDENTIFIER:([0-9A-Fa-f\-]+)"#) else {
            return []
        }
        let ns = raw as NSString
        return regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            .compactMap { match -> String? in
                guard match.numberOfRanges > 1 else { return nil }
                let identifier = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                return identifier.isEmpty ? nil : identifier
            }
    }

    nonisolated private static func identifiersFromJSON(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let array = object as? [[String: Any]] {
            return array.compactMap(identifier(from:))
        }

        if let dictionary = object as? [String: Any],
           let array = dictionary["devices"] as? [[String: Any]] {
            return array.compactMap(identifier(from:))
        }

        return []
    }

    nonisolated private static func identifier(from dictionary: [String: Any]) -> String? {
        let rawIdentifier =
            dictionary["identifier"] as? String ??
            dictionary["Identifier"] as? String
        guard let rawIdentifier else { return nil }
        let trimmed = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class DeviceManager: ObservableObject, DeviceControlling, @unchecked Sendable {
    @Published private(set) var connectionState: DeviceConnectionState = .disconnected
    @Published private(set) var deviceName: String = "Not connected"
    @Published private(set) var lastError: String?
    @Published var manualRsdHost: String = "" {
        didSet { UserDefaults.standard.set(manualRsdHost, forKey: Self.manualRsdHostKey) }
    }
    @Published var manualRsdPort: String = "" {
        didSet { UserDefaults.standard.set(manualRsdPort, forKey: Self.manualRsdPortKey) }
    }
    @Published var tunnelUDID: String = "" {
        didSet { UserDefaults.standard.set(tunnelUDID, forKey: Self.tunnelUDIDKey) }
    }

    @Published var isWirelessMode: Bool = false {
        didSet { UserDefaults.standard.set(isWirelessMode, forKey: Self.wirelessModeKey) }
    }
    @Published private(set) var debugLog: [String] = []

    var isConnected: Bool { connectionState.isConnected }
    var isConnecting: Bool { connectionState.isBusy }
    var connectionStage: String { connectionState.statusText }

    private struct Endpoint {
        let host: String
        let port: String
    }

    private struct USBMuxDevice: Decodable {
        let connectionType: String?
        let deviceClass: String?
        let deviceName: String?
        let identifier: String?
        let uniqueDeviceID: String?
        let productType: String?

        enum CodingKeys: String, CodingKey {
            case connectionType = "ConnectionType"
            case deviceClass = "DeviceClass"
            case deviceName = "DeviceName"
            case identifier = "Identifier"
            case uniqueDeviceID = "UniqueDeviceID"
            case productType = "ProductType"
        }
    }

    private let sendQueue = DispatchQueue(label: "paperclip.gps.sender", qos: .utility)
    private let connectionQueue = DispatchQueue(label: "paperclip.connection", qos: .utility)
    private var isConnectionInFlight = false
    private let sendQueueSpecificKey = DispatchSpecificKey<String>()
    private let sendQueueSpecificValue = "paperclip.gps.sender"
    private var inFlight = false
    private var pendingCoordinate: CLLocationCoordinate2D?
    private let dvtStream = DVTLocationStream()

    private var tunnelProcess: Process?
    private var tunnelOutPipe: Pipe?
    private var tunnelErrPipe: Pipe?
    private var rsdEndpoint: Endpoint?
    private var simulateLocationMode: SimulateLocationMode?
    private var autoReconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempt: Int = 0
    private var userInitiatedDisconnect = false
    private var expectedDvtStreamExit = false
    private var sentLocationCount: Int = 0
    private var activeTunnelConnectionType: TunnelConnectionType?
    private let privilegedTunnelFiles = PrivilegedTunnelFiles.makeDefault()
    private let runtimeLogStore = RotatingRuntimeLogStore(logURL: DiagnosticsPaths.logFileURL(named: "device-runtime.log"))
    private let runtimeLogQueue = DispatchQueue(label: "paperclip.runtime.log", qos: .utility)
    private static let manualRsdHostKey = "paperclip.connection.manualRsdHost"
    private static let manualRsdPortKey = "paperclip.connection.manualRsdPort"
    private static let tunnelUDIDKey = "paperclip.connection.tunnelUDID"
    private static let wirelessModeKey = "paperclip.connection.wirelessMode"
    private static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init() {
        sendQueue.setSpecific(key: sendQueueSpecificKey, value: sendQueueSpecificValue)
        let defaults = UserDefaults.standard
        manualRsdHost = defaults.string(forKey: Self.manualRsdHostKey) ?? ""
        manualRsdPort = defaults.string(forKey: Self.manualRsdPortKey) ?? ""
        tunnelUDID = defaults.string(forKey: Self.tunnelUDIDKey) ?? ""
        isWirelessMode = defaults.bool(forKey: Self.wirelessModeKey)
    }

    deinit {
        cancelAutoReconnect()
        stopTunnel()
    }

    func connectDevice() {
        userInitiatedDisconnect = false
        connectDeviceInternal(autoTriggered: false, force: true)
    }

    func connectDeviceAsync() async throws {
        connectDevice()
        let timeout = Date().addingTimeInterval(AppConstants.Timeouts.tunnelReady + AppConstants.Timeouts.mountTimeout)
        while Date() < timeout {
            if isConnected { return }
            if connectionState == .failed {
                throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: lastError ?? "Device connection failed"
                ])
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Device connection timed out"
        ])
    }

    private func connectDeviceInternal(autoTriggered: Bool, force: Bool) {
        guard force || !isConnected else { return }
        if !autoTriggered {
            cancelAutoReconnect()
            appendLog("Starting Apple device connection")
            setConnectionState(.connecting(step: "initializing"), deviceName: "Connecting...", lastError: nil)
        } else {
            setConnectionState(.connecting(step: "reconnecting"), deviceName: "Reconnecting...", lastError: nil)
            appendLog("Running auto reconnect (attempt \(reconnectAttempt))")
        }

        connectionQueue.async {
            if self.isConnectionInFlight {
                self.appendLog("A connection flow is already in progress. Ignoring duplicate request.")
                return
            }
            self.isConnectionInFlight = true
            defer { self.isConnectionInFlight = false }

            do {
                self.activeTunnelConnectionType = self.isWirelessMode ? .wifi : .usb
                let cmd = try self.resolveCLI()
                self.appendLog("CLI: \(cmd.joined(separator: " "))")
                _ = try self.runWithTimeoutLogged(
                    cmd + ["version"],
                    timeout: AppConstants.Timeouts.pymobiledeviceCheck,
                    step: "Check pymobiledevice3"
                )

                if let manual = self.manualEndpointIfValid() {
                    self.setStage("Use manual RSD")
                    self.rsdEndpoint = manual
                    try self.verifyRsdEndpoint(using: cmd, ep: manual)
                } else {
                    let tunnelUDID = try self.preferredConnectionUDID(using: cmd)
                    self.setStage("Prepare connection")
                    do {
                        try self.startTunnelAndResolveEndpoint(using: cmd, udid: tunnelUDID)
                    } catch {
                        let err = error.localizedDescription
                        if err.localizedCaseInsensitiveContains("requires root privileges") {
                            self.appendLog("start-tunnel requires admin privileges. Retrying with a prompt.")
                            try self.startTunnelWithAdminPrompt(using: cmd, udid: tunnelUDID)
                        }
                        else if self.shouldFallbackToAnyDevice(for: err) {
                            self.appendLog("Requested UDID failed. Retrying by auto-selecting the currently connected device.")
                            try self.startTunnelAndResolveEndpoint(using: cmd, udid: nil)
                        } else if try self.shouldFallbackToUSBTunnel(using: cmd, errorMessage: err) {
                            self.appendLog("Wi-Fi tunnel is not supported. Retrying with a USB tunnel.")
                            self.activeTunnelConnectionType = .usb
                            let usbUDID = try self.preferredTunnelUDID(using: cmd)
                            self.setStage("Switch to USB")
                            try self.startTunnelAndResolveEndpoint(using: cmd, udid: usbUDID)
                        } else {
                            throw error
                        }
                    }

                    guard let ep = self.rsdEndpoint else {
                        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "Could not determine the RSD host and port"
                        ])
                    }
                    try self.verifyRsdEndpoint(using: cmd, ep: ep)
                }
                guard let ep = self.rsdEndpoint else {
                    throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "The RSD endpoint disappeared before the connection completed. Please try again."
                    ])
                }
                let deviceLabel = self.connectedDeviceLabel(using: cmd)

                self.setConnectionState(.connected, deviceName: "\(deviceLabel) (RSD: \(ep.host):\(ep.port))", lastError: nil)
#if DEBUG
                print("✅ Tunnel OK: \(DeviceLogRedactor.maskedEndpoint(host: ep.host, port: ep.port))")
#endif
                self.appendLog("Connection ready. Mode: \(self.simulateLocationMode?.rawValue ?? "unknown")")
                self.cancelAutoReconnect()
                self.reconnectAttempt = 0
            } catch {
                self.stopTunnel()
                let lowered = error.localizedDescription.lowercased()
                self.setConnectionState(.failed, deviceName: "Connection failed", lastError: error.localizedDescription)
#if DEBUG
                print("❌ connectDevice error: \(DeviceLogRedactor.sanitizedMessage(error.localizedDescription))")
#endif
                self.appendLog("Connection failed: \(error.localizedDescription)")
                if autoTriggered || lowered.contains("bad file descriptor") {
                    self.scheduleAutoReconnect(reason: error.localizedDescription)
                }
            }
        }
    }

    private func manualEndpointIfValid() -> Endpoint? {
        let h = manualRsdHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = manualRsdPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !p.isEmpty else { return nil }
        guard Int(p) != nil else { return nil }
        return Endpoint(host: h, port: p)
    }

    private func preferredConnectionUDID(using cmd: [String]) throws -> String? {
        if isWirelessMode {
            setStage("Search available devices")
            appendLog("Wi-Fi mode: searching for a device UDID")
            let requested = effectiveTunnelUDID
            if let requested, !requested.isEmpty {
                appendLog("Wi-Fi mode: using the specified UDID \(DeviceLogRedactor.maskedIdentifier(requested))")
                return requested
            }
            appendLog("Wi-Fi mode: trying to reuse a connected USB device UDID")
            if let connectedUDID = try preferredActiveDeviceUDID(using: cmd) {
                appendLog("Wi-Fi mode: using USB device UDID \(DeviceLogRedactor.maskedIdentifier(connectedUDID))")
                return connectedUDID
            }
            appendLog("Wi-Fi mode: no USB device found, falling back to Bonjour browse")
            if let browsedUDID = try browseRemoteDeviceUDID(using: cmd) {
                appendLog("Wi-Fi mode: Bonjour browse found UDID \(DeviceLogRedactor.maskedIdentifier(browsedUDID))")
                return browsedUDID
            }
            appendLog("Wi-Fi mode: no device found from any discovery path, retrying without a UDID")
            return nil
        }
        return try preferredTunnelUDID(using: cmd)
    }

    private func browseRemoteDeviceUDID(using cmd: [String]) throws -> String? {
        let browseCommand = cmd + ["remote", "browse"]
        appendLog("▶ Browsing for Wi-Fi devices via Bonjour")
        appendLog("cmd: \(DeviceLogRedactor.sanitizedCommandString(browseCommand))")

        let raw: String
        do {
            raw = try runWithTimeout(browseCommand, timeout: 8)
            appendLog("✓ Bonjour Wi-Fi browse completed")
        } catch {
            appendLog("✗ Bonjour Wi-Fi browse failed: \(error.localizedDescription)")
            return nil
        }

        let identifiers = RemoteBrowseOutputParser.identifiers(in: raw)
        guard !identifiers.isEmpty else {
            appendLog("Bonjour browse did not find any devices")
            return nil
        }

        appendLog("Bonjour browse found \(identifiers.count) device(s)")
        appendLog("Selecting the first device: \(DeviceLogRedactor.maskedIdentifier(identifiers[0]))")
        return identifiers[0]
    }

    private func preferredActiveDeviceUDID(using cmd: [String]) throws -> String? {
        let devices = try listConnectedDevices(using: cmd)
        guard !devices.isEmpty else { return nil }

        if let requested = effectiveTunnelUDID,
           let matched = devices.first(where: { matchesDevice($0, requestedUDID: requested) }) {
            return matched.identifier ?? matched.uniqueDeviceID
        }

        let preferredDevice =
            devices.first(where: { ($0.connectionType ?? "").uppercased() == "USB" }) ??
            devices.first

        return preferredDevice?.identifier ?? preferredDevice?.uniqueDeviceID
    }

    private func preferredTunnelUDID(using cmd: [String]) throws -> String? {
        let devices = try listConnectedDevices(using: cmd)
        guard !devices.isEmpty else {
            throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No connected iPhone or iPad was detected. Make sure the device is connected over USB, unlocked, and trusted on this Mac, and that Finder or Xcode can see it. If you already know the RSD endpoint, you can also enter the host and port manually in Advanced Connection."
            ])
        }

        appendLog("Detected devices: " + devices.map(deviceDebugLabel(for:)).joined(separator: ", "))

        guard let requested = effectiveTunnelUDID else { return nil }
        if devices.contains(where: { matchesDevice($0, requestedUDID: requested) }) {
            return requested
        }

        appendLog("Requested UDID \(requested) is not in the current device list. Falling back to auto-selection.")
        return nil
    }

    private func verifyRsdEndpoint(using cmd: [String], ep: Endpoint) throws {
        setStage("Verify device services")
        appendLog("RSD endpoint: \(ep.host):\(ep.port)")

        try ensureDeveloperModeEnabledIfSupported(using: cmd, ep: ep)

        _ = try runWithTimeoutLogged(cmd + [
            "mounter", "auto-mount",
            "--rsd", ep.host, ep.port
        ], timeout: AppConstants.Timeouts.mountTimeout, step: "Mount Developer Disk Image")

        _ = try runWithTimeoutLogged(cmd + [
            "remote", "rsd-info",
            "--rsd", ep.host, ep.port
        ], timeout: AppConstants.Timeouts.rsdInfo, step: "Read RSD info")

        simulateLocationMode = try detectSimulateLocationMode(using: cmd, ep: ep)
        appendLog("simulate-location mode: \(simulateLocationMode?.rawValue ?? "unknown")")
    }

    private func detectSimulateLocationMode(using cmd: [String], ep: Endpoint) throws -> SimulateLocationMode {
        setStage("Detect simulate-location mode")
        do {
            _ = try runWithTimeoutLogged(
                cmd + SimulateLocationMode.dvt.clearArgs(host: ep.host, port: ep.port),
                timeout: AppConstants.Timeouts.rsdInfo,
                step: "Try dvt clear"
            )
            return .dvt
        } catch {
            appendLog("dvt simulate-location is unavailable: \(error.localizedDescription)")
        }
        _ = try runWithTimeoutLogged(
            cmd + SimulateLocationMode.legacy.clearArgs(host: ep.host, port: ep.port),
            timeout: AppConstants.Timeouts.rsdInfo,
            step: "Try legacy clear"
        )
        return .legacy
    }

    private func ensureDeveloperModeEnabledIfSupported(using cmd: [String], ep: Endpoint) throws {
        let output: String
        do {
            output = try runWithTimeoutLogged(
                cmd + [
                    "mounter", "query-developer-mode-status",
                    "--rsd", ep.host, ep.port
                ],
                timeout: AppConstants.Timeouts.rsdInfo,
                step: "Check Developer Mode"
            )
        } catch {
            let lowered = error.localizedDescription.lowercased()
            if lowered.contains("message not supported")
                || lowered.contains("unknown command")
                || lowered.contains("unknowncommand") {
                appendLog("Developer Mode status query is not supported. Skipping the check.")
                return
            }
            throw error
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "true" {
            return
        }
        if trimmed == "false" {
            throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Developer Mode is not enabled on the device. On your iPhone or iPad, go to Settings > Privacy & Security > Developer Mode, enable it, restart the device if prompted, and then try again."
            ])
        }

        appendLog("Could not determine Developer Mode status. Skipping the enforced check.")
    }

    private var effectiveTunnelUDID: String? {
        let trimmed = tunnelUDID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var effectiveTunnelConnectionType: TunnelConnectionType {
        activeTunnelConnectionType ?? (isWirelessMode ? .wifi : .usb)
    }

    private var preferredConnectionType: String {
        effectiveTunnelConnectionType.rawValue
    }

    private func shouldFallbackToUSBTunnel(using cmd: [String], errorMessage: String) throws -> Bool {
        guard effectiveTunnelConnectionType == .wifi else { return false }
        let lower = errorMessage.lowercased()
        guard lower.contains("operation not supported by device")
            || lower.contains("no route to host")
            || lower.contains("network is unreachable") else {
            return false
        }
        let devices = try listConnectedDevices(using: cmd)
        return !devices.isEmpty
    }

    private func shouldFallbackToAnyDevice(for errorMessage: String) -> Bool {
        guard effectiveTunnelUDID != nil else { return false }
        let lower = errorMessage.lowercased()
        return lower.contains("device is not connected")
            || lower.contains("no device connected")
            || lower.contains("usbmux")
    }

    private func listConnectedDevices(using cmd: [String]) throws -> [USBMuxDevice] {
        let args = cmd + ["usbmux", "list"]

        do {
            let raw = try runWithTimeoutLogged(
                args,
                timeout: AppConstants.Timeouts.tunnelReady,
                step: "Detect connected devices"
            )
            return decodeUSBMuxDevices(from: raw)
        } catch {
            let lowered = error.localizedDescription.lowercased()
            let isTimeout = lowered.contains("command timed out") && lowered.contains("usbmux list")
            guard isTimeout else { throw error }

            appendLog("usbmux list timed out. Retrying in 1 second.")
            Thread.sleep(forTimeInterval: 1.0)

            do {
                let raw = try runWithTimeoutLogged(
                    args,
                    timeout: AppConstants.Timeouts.tunnelReady,
                    step: "Detect connected devices again"
                )
                return decodeUSBMuxDevices(from: raw)
            } catch {
                throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Timed out while detecting the iPhone or iPad because usbmuxd did not return a device list. Make sure the device is unlocked and trusted on this Mac, reconnect the USB cable, and try again. If it still fails, close Finder, Xcode, Apple Configurator, or any other app that may be using the device, then restart both the Mac and the iPhone."
                ])
            }
        }
    }

    private func decodeUSBMuxDevices(from raw: String) -> [USBMuxDevice] {
        guard let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([USBMuxDevice].self, from: data)) ?? []
    }

    private func matchesDevice(_ device: USBMuxDevice, requestedUDID: String) -> Bool {
        device.identifier == requestedUDID || device.uniqueDeviceID == requestedUDID
    }

    private func deviceDebugLabel(for device: USBMuxDevice) -> String {
        let name = device.deviceName ?? device.productType ?? device.deviceClass ?? "Apple Device"
        let transport = device.connectionType?.uppercased() ?? "UNKNOWN"
        let identifier = device.identifier ?? device.uniqueDeviceID ?? "no-id"
        return "\(name) [\(transport)] \(DeviceLogRedactor.maskedIdentifier(identifier))"
    }

    private func resolveConnectedDeviceLabel(using cmd: [String], preferredUDID: String?) throws -> String {
        let devices = try listConnectedDevices(using: cmd)
        guard !devices.isEmpty else {
            return "Apple Device"
        }

        let preferred = preferredUDID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let picked =
            devices.first(where: {
                guard let preferred else { return false }
                return $0.identifier == preferred || $0.uniqueDeviceID == preferred
            }) ??
            devices.first(where: { ($0.connectionType ?? "").uppercased() == "USB" }) ??
            devices.first

        guard let picked else { return "Apple Device" }
        let type = picked.productType ?? picked.deviceClass ?? "Apple Device"
        if let name = picked.deviceName, !name.isEmpty {
            return "\(name) \(type)"
        }
        return type
    }

    private func connectedDeviceLabel(using cmd: [String]) -> String {
        if effectiveTunnelConnectionType == .wifi {
            if let requested = effectiveTunnelUDID {
                return "Apple Device (Wi‑Fi: \(DeviceLogRedactor.maskedIdentifier(requested)))"
            }
            return "Apple Device (Wi‑Fi)"
        }
        return (try? resolveConnectedDeviceLabel(using: cmd, preferredUDID: effectiveTunnelUDID)) ?? "Apple Device"
    }

    private func startTunnelWithAdminPrompt(using cmd: [String], udid: String?) throws {
        var failures: [String] = []
        let candidates: [String?] = udid == nil ? [nil] : [udid, nil]

        for candidateUDID in candidates {
            if udid != nil && candidateUDID == nil {
                appendLog("Retrying the admin tunnel with the currently connected device instead")
            }
            var shouldMoveToNextCandidate = false
            for transport in TunnelTransport.allCases {
                do {
                    try startTunnelWithAdminPrompt(using: cmd, udid: candidateUDID, transport: transport)
                    return
                } catch {
                    let failure = "\(transport.rawValue): \(error.localizedDescription)"
                    failures.append(failure)
                    appendLog("Admin tunnel failed (\(failure))")
                    stopPrivilegedTunnelProcessIfNeeded()
                    if candidateUDID != nil && shouldFallbackToAnyDevice(for: error.localizedDescription) {
                        shouldMoveToNextCandidate = true
                        break
                    }
                }
            }
            if shouldMoveToNextCandidate {
                continue
            }
        }
        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Admin privileges were requested, but every tunnel protocol failed.\n" + failures.joined(separator: "\n")
        ])
    }

    private func startTunnelWithAdminPrompt(using cmd: [String], udid: String?, transport: TunnelTransport) throws {
        setStage("Request system authorization")
        let full = cmd + startTunnelArguments(transport: transport, udid: udid)
        let scriptURL = try preparePrivilegedTunnelWrapperScript(for: full)
        let shellCmd = privilegedTunnelLaunchCommand(for: scriptURL)

        if runWithNonInteractiveSudo(shellCmd) {
            appendLog("Started admin tunnel with sudo -n")
        } else {
            try runPrivilegedTunnelWithAuthorization(scriptURL: scriptURL)
            appendLog("Started admin tunnel using the system authorization dialog (\(transport.rawValue))")
        }
        appendLog("Admin tunnel started. Waiting for RSD endpoint (\(transport.rawValue))")

        let deadline = Date().addingTimeInterval(AppConstants.Timeouts.tunnelReady)
        while Date() < deadline {
            if let text = try? String(contentsOf: privilegedTunnelFiles.logURL, encoding: .utf8) {
                if let pair = TunnelOutputParser.endpoint(in: text) {
                    rsdEndpoint = Endpoint(host: pair.host, port: pair.port)
                    let ep = rsdEndpoint!
                    appendLog("Admin tunnel RSD: \(ep.host):\(ep.port)")
                    return
                }
                if let failure = TunnelOutputParser.immediateFailure(in: text) {
                    throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: DeviceLogRedactor.sanitizedMessage(failure)
                    ])
                }
            }
            Thread.sleep(forTimeInterval: AppConstants.Timeouts.pollInterval)
        }

        let logText = (try? String(contentsOf: privilegedTunnelFiles.logURL, encoding: .utf8))
            .map(DeviceLogRedactor.sanitizedMessage) ?? ""
        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Admin privileges were requested, but the RSD endpoint was still not received.\n\(logText)"
        ])
    }

    private func startTunnelArguments(transport: TunnelTransport, udid: String?) -> [String] {
        [
            "remote", "start-tunnel",
            "--connection-type", preferredConnectionType,
            "--script-mode",
            "-p", transport.rawValue
        ] + (udid.map { ["--udid", $0] } ?? [])
    }

    private func shellEscape(_ s: String) -> String {
        if s.isEmpty { return "''" }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func ensurePrivilegedTunnelDirectory() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: privilegedTunnelFiles.directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: privilegedTunnelFiles.directoryURL.path
        )
    }

    private func cleanupPrivilegedTunnelArtifacts(removeScript: Bool = false) {
        let urls = [
            privilegedTunnelFiles.logURL,
            privilegedTunnelFiles.pidURL,
            privilegedTunnelFiles.stopURL
        ] + (removeScript ? [privilegedTunnelFiles.scriptURL] : [])

        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func preparePrivilegedTunnelWrapperScript(for command: [String]) throws -> URL {
        ensurePrivilegedTunnelDirectory()
        cleanupPrivilegedTunnelArtifacts(removeScript: false)
        PrivilegedTunnelArtifactPreparer.prepareReadableArtifacts(files: privilegedTunnelFiles)

        let commandLine = command.map(shellEscape).joined(separator: " ")
        let script = """
        #!/bin/sh
        umask 077
        LOG=\(shellEscape(privilegedTunnelFiles.logURL.path))
        PIDFILE=\(shellEscape(privilegedTunnelFiles.pidURL.path))
        STOPFILE=\(shellEscape(privilegedTunnelFiles.stopURL.path))
        rm -f "$STOPFILE"
        : > "$LOG"
        \(commandLine) >> "$LOG" 2>&1 &
        CHILD=$!
        echo "$CHILD" > "$PIDFILE"
        while kill -0 "$CHILD" >/dev/null 2>&1; do
          if [ -f "$STOPFILE" ]; then
            kill "$CHILD" >/dev/null 2>&1 || true
            break
          fi
          sleep 1
        done
        wait "$CHILD" >/dev/null 2>&1 || true
        rm -f "$PIDFILE" "$STOPFILE"
        """

        try script.write(to: privilegedTunnelFiles.scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: privilegedTunnelFiles.scriptURL.path
        )
        return privilegedTunnelFiles.scriptURL
    }

    private func privilegedTunnelLaunchCommand(for scriptURL: URL) -> String {
        "/bin/sh " + shellEscape(scriptURL.path) + " >/dev/null 2>&1 &"
    }

    private func runPrivilegedTunnelWithAuthorization(scriptURL: URL) throws {
        let source = """
        on run argv
            do shell script "/bin/sh " & quoted form of item 1 of argv & " >/dev/null 2>&1 &" with administrator privileges
        end run
        """
        _ = try run(["/usr/bin/osascript", "-e", source, scriptURL.path])
    }

    private func loadPrivilegedTunnelPID() -> Int? {
        guard let raw = try? String(contentsOf: privilegedTunnelFiles.pidURL, encoding: .utf8) else {
            return nil
        }
        guard let pid = PrivilegedTunnelPIDParser.parse(raw) else {
            appendLog("The privileged tunnel PID file is invalid. Falling back to the stop file only.")
            return nil
        }
        return pid
    }

    private func requestPrivilegedTunnelStop() throws {
        ensurePrivilegedTunnelDirectory()
        try Data().write(to: privilegedTunnelFiles.stopURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: privilegedTunnelFiles.stopURL.path
        )
    }

    private func isProcessRunning(pid: Int) -> Bool {
        if kill(pid_t(pid), 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private func stopPrivilegedTunnelProcessIfNeeded() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: privilegedTunnelFiles.pidURL.path)
                || fileManager.fileExists(atPath: privilegedTunnelFiles.scriptURL.path)
                || fileManager.fileExists(atPath: privilegedTunnelFiles.logURL.path) else {
            return
        }

        let pid = loadPrivilegedTunnelPID()
        do {
            try requestPrivilegedTunnelStop()
            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline {
                if !fileManager.fileExists(atPath: privilegedTunnelFiles.pidURL.path) {
                    break
                }
                if let pid, !isProcessRunning(pid: pid) {
                    break
                }
                Thread.sleep(forTimeInterval: AppConstants.Timeouts.pollInterval)
            }
        } catch {
            appendLog("Failed to write the stop file: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        userInitiatedDisconnect = true
        cancelAutoReconnect()
        clearSimulatedLocation()
        stopTunnel()
        setConnectionState(.disconnected, deviceName: "Not connected", lastError: nil)
        appendLog("Device disconnected")
    }

    func disconnectAsync() async {
        disconnect()
        while isConnected || isConnecting {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func sendLocationToDevice(latitude: Double, longitude: Double) {
        guard isConnected else { return }
        let c = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(c) else { return }

        sendQueue.async { [weak self] in
            guard let self else { return }
            self.pendingCoordinate = c
            self.flushLatestCoordinate()
        }
    }

    func sendLocationToDeviceAsync(latitude: Double, longitude: Double) async throws {
        guard isConnected else {
            throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "The device is not connected"
            ])
        }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "The coordinate is invalid"
            ])
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: NSError(domain: "DeviceManager", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "DeviceManager has been released"
                    ]))
                    return
                }

                let wasIdle = !self.inFlight && self.pendingCoordinate == nil
                self.pendingCoordinate = coordinate

                guard wasIdle else {
                    continuation.resume()
                    return
                }

                self.flushLatestCoordinate()
                if self.lastError?.contains("Failed to send location") == true {
                    continuation.resume(throwing: NSError(domain: "DeviceManager", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: self.lastError ?? "Failed to send location"
                    ]))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func startContinuousLocationStream() {
        guard isConnected else { return }
        sendQueue.async { [weak self] in
            guard let self, let ep = self.rsdEndpoint else { return }
            guard self.simulateLocationMode == .dvt else { return }
            do {
                try self.startDvtStreamIfNeeded(host: ep.host, port: ep.port)
            } catch {
                self.appendLog("Failed to start the live DVT location stream: \(error.localizedDescription)")
            }
        }
    }

    func stopContinuousLocationStream() {
        sendQueue.async { [weak self] in
            guard let self else { return }
            self.expectedDvtStreamExit = true
            self.dvtStream.stop()
        }
    }

    func clearSimulatedLocation() {
        guard isConnected else { return }
        sendQueue.async { [weak self] in
            guard let self, let ep = self.rsdEndpoint else { return }
            do {
                let cmd = try self.resolveCLI()
                let mode = self.simulateLocationMode ?? .legacy
                self.dvtStream.clear()
                _ = try self.runWithTimeoutLogged(
                    cmd + mode.clearArgs(host: ep.host, port: ep.port),
                    timeout: AppConstants.Timeouts.rsdInfo,
                    step: "Clear simulated location"
                )
#if DEBUG
                print("🧹 Simulated location cleared")
#endif
            } catch {
#if DEBUG
                print("⚠️ Clear failed: \(DeviceLogRedactor.sanitizedMessage(error.localizedDescription))")
#endif
                self.appendLog("Failed to clear simulated location: \(error.localizedDescription)")
            }
        }
    }

    func clearSimulatedLocationAsync() async throws {
        guard isConnected else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: NSError(domain: "DeviceManager", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "DeviceManager has been released"
                    ]))
                    return
                }
                guard let ep = self.rsdEndpoint else {
                    continuation.resume(throwing: NSError(domain: "DeviceManager", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "RSD is not ready"
                    ]))
                    return
                }
                do {
                    let cmd = try self.resolveCLI()
                    let mode = self.simulateLocationMode ?? .legacy
                    self.dvtStream.clear()
                    _ = try self.runWithTimeoutLogged(
                        cmd + mode.clearArgs(host: ep.host, port: ep.port),
                        timeout: AppConstants.Timeouts.rsdInfo,
                        step: "Clear simulated location"
                    )
                    continuation.resume()
                } catch {
                    self.appendLog("Failed to clear simulated location: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func flushLatestCoordinate() {
        guard !inFlight, let next = pendingCoordinate else { return }
        pendingCoordinate = nil
        inFlight = true
        defer {
            inFlight = false
            if pendingCoordinate != nil { flushLatestCoordinate() }
        }

        guard rsdEndpoint != nil else {
            setConnectionState(.failed, deviceName: "RSD not ready. Reconnect required.", lastError: "RSD is not ready")
            return
        }

        do {
            let lat = String(format: AppConstants.Formatting.coordinatePrecision, next.latitude)
            let lon = String(format: AppConstants.Formatting.coordinatePrecision, next.longitude)
            try sendCoordinate(latitude: next.latitude, longitude: next.longitude)
            sentLocationCount += 1
            if sentLocationCount % 100 == 0 {
                appendLog("Location sent: \(lat), \(lon)")
            }
        } catch {
            let msg = error.localizedDescription
#if DEBUG
            print("❌ Send failed: \(DeviceLogRedactor.sanitizedMessage(msg))")
#endif
            appendLog("Failed to send location: \(msg)")
            DispatchQueue.main.async {
                self.lastError = DeviceLogRedactor.sanitizedMessage("Failed to send location: \(msg)")
            }
            if msg.lowercased().contains("timeout") || msg.lowercased().contains("broken pipe") || msg.lowercased().contains("connection") {
                setConnectionState(.failed, deviceName: "Tunnel interrupted. Reconnect required.", lastError: msg)
                scheduleAutoReconnect(reason: msg)
            }
        }
    }

    private func resolveCLI() throws -> [String] {
        if let resourcesURL = Bundle.main.resourceURL {
            let bundledURL = resourcesURL
                .appendingPathComponent("pymobiledevice3-bundle", isDirectory: true)
                .appendingPathComponent("pymobiledevice3", isDirectory: false)
            let bundledPath = bundledURL.path
            if FileManager.default.isExecutableFile(atPath: bundledPath) {
            appendLog("CLI source: bundled (\(bundledPath))")
            return [bundledPath]
            }
        }
        appendLog("CLI source: bundled missing")
        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Could not find the bundled pymobiledevice3 CLI. Please reinstall the app."
        ])
    }

    private func startTunnelAndResolveEndpoint(using cmd: [String], udid: String?) throws {
        var failures: [String] = []
        for transport in TunnelTransport.allCases {
            do {
                try startTunnelAndResolveEndpoint(using: cmd, udid: udid, transport: transport)
                return
            } catch {
                let failure = "\(transport.rawValue): \(error.localizedDescription)"
                failures.append(failure)
                appendLog("Tunnel failed (\(failure))")
                stopTunnel()
            }
        }
        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "All tunnel protocols failed.\n" + failures.joined(separator: "\n")
        ])
    }

    private func startTunnelAndResolveEndpoint(using cmd: [String], udid: String?, transport: TunnelTransport) throws {
        stopTunnel()
        setStage("Wait for connection")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = cmd + startTunnelArguments(transport: transport, udid: udid)

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        let textBuffer = LockedStringBuffer()
        let appendText: @Sendable (String) -> Void = { chunk in
            textBuffer.append(chunk)
        }
        let snapshotText: () -> String = {
            textBuffer.snapshot()
        }

        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let t = String(data: data, encoding: .utf8) else { return }
            appendText(t)
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let t = String(data: data, encoding: .utf8) else { return }
            appendText("\n" + t)
        }

        try p.run()

        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            if self.rsdEndpoint != nil && !self.userInitiatedDisconnect {
                self.handleUnexpectedConnectionLoss(reason: "Tunnel process exited (code: \(proc.terminationStatus))")
            }
        }

        tunnelProcess = p
        tunnelOutPipe = out
        tunnelErrPipe = err

        let deadline = Date().addingTimeInterval(AppConstants.Timeouts.tunnelReady)
        appendLog("Waiting for tunnel to output the RSD endpoint (\(transport.rawValue))")

        while Date() < deadline {
            let currentText = snapshotText()
            if let pair = TunnelOutputParser.endpoint(in: currentText) {
                let ep = Endpoint(host: pair.host, port: pair.port)
                rsdEndpoint = ep
                appendLog("RSD endpoint found: \(ep.host):\(ep.port)")
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                return
            }

            if let failure = TunnelOutputParser.immediateFailure(in: currentText) {
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: DeviceLogRedactor.sanitizedMessage(failure)
                ])
            }

            if !p.isRunning {
                break
            }

            Thread.sleep(forTimeInterval: 0.15)
        }

        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        let finalText = snapshotText()
        appendLog("Tunnel did not return an RSD endpoint (\(transport.rawValue))")

        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "start-tunnel timed out or did not output an RSD endpoint.\n\(DeviceLogRedactor.sanitizedMessage(finalText))"
        ])
    }

    private func isOnSendQueue() -> Bool {
        DispatchQueue.getSpecific(key: sendQueueSpecificKey) == sendQueueSpecificValue
    }

    private func resetSendState() {
        expectedDvtStreamExit = true
        dvtStream.stop()
        pendingCoordinate = nil
        inFlight = false
    }

    private func stopSendPipelineSynchronously() {
        if isOnSendQueue() {
            resetSendState()
            return
        }
        let group = DispatchGroup()
        group.enter()
        sendQueue.async { [weak self] in
            defer { group.leave() }
            self?.resetSendState()
        }
        _ = group.wait(timeout: .now() + 2.0)
    }

    private func stopTunnel() {
        rsdEndpoint = nil
        simulateLocationMode = nil
        activeTunnelConnectionType = nil
        stopSendPipelineSynchronously()

        tunnelOutPipe?.fileHandleForReading.readabilityHandler = nil
        tunnelErrPipe?.fileHandleForReading.readabilityHandler = nil

        if let p = tunnelProcess {
            p.terminationHandler = nil
        }

        if let p = tunnelProcess, p.isRunning {
            p.terminate()
            Thread.sleep(forTimeInterval: AppConstants.Timeouts.pollInterval)
            if p.isRunning { p.interrupt() }
        }

        tunnelProcess = nil
        tunnelOutPipe = nil
        tunnelErrPipe = nil

        stopPrivilegedTunnelProcessIfNeeded()

    }

    private func handleUnexpectedConnectionLoss(reason: String) {
        guard !userInitiatedDisconnect else { return }
        guard rsdEndpoint != nil || connectionState.isConnected else { return }
        appendLog("Connection interrupted: \(reason)")
        stopTunnel()
        setConnectionState(.failed, deviceName: "Connection interrupted", lastError: reason)
        scheduleAutoReconnect(reason: reason)
    }

    @discardableResult
    private func runWithNonInteractiveSudo(_ shellCmd: String) -> Bool {
        do {
            _ = try run(["/usr/bin/sudo", "-n", "/bin/sh", "-c", shellCmd])
            return true
        } catch {
            appendLog("sudo -n is unavailable: \(error.localizedDescription)")
            return false
        }
    }

    private func scheduleAutoReconnect(reason: String) {
        guard !userInitiatedDisconnect else { return }
        guard autoReconnectWorkItem == nil else { return }

        reconnectAttempt += 1
        let delay = min(AppConstants.DeviceStream.reconnectBackoffCap, pow(2.0, Double(max(0, reconnectAttempt - 1))))
        setConnectionState(.connecting(step: "wait reconnect"), deviceName: "Waiting to reconnect...", lastError: lastError)
        appendLog("Scheduling auto reconnect in \(String(format: "%.0f", delay))s. Reason: \(reason)")

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.autoReconnectWorkItem = nil
            guard !self.userInitiatedDisconnect else { return }
            self.connectDeviceInternal(autoTriggered: true, force: true)
        }
        autoReconnectWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelAutoReconnect() {
        autoReconnectWorkItem?.cancel()
        autoReconnectWorkItem = nil
    }

    private func setStage(_ stage: String) {
        setConnectionState(.connecting(step: stage), lastError: nil)
    }

    private func setConnectionState(
        _ state: DeviceConnectionState,
        deviceName: String? = nil,
        lastError: String? = nil
    ) {
        DispatchQueue.main.async {
            self.connectionState = state
            if let deviceName {
                self.deviceName = deviceName
            }
            self.lastError = lastError.map(DeviceLogRedactor.sanitizedMessage)
        }
    }

    private func appendLog(_ text: String) {
        let stamp = Self.logFormatter.string(from: Date())
        let line = "[\(stamp)] \(DeviceLogRedactor.sanitizedMessage(text))"
        DispatchQueue.main.async {
            self.debugLog.append(line)
            if self.debugLog.count > 120 {
                self.debugLog.removeFirst(self.debugLog.count - 120)
            }
        }
        runtimeLogQueue.async { [runtimeLogStore] in
            runtimeLogStore.appendLine(line)
        }
    }

    private func runWithTimeoutLogged(_ args: [String], timeout: TimeInterval, step: String) throws -> String {
        appendLog("▶ \(step)")
        appendLog("cmd: \(DeviceLogRedactor.sanitizedCommandString(args))")
        do {
            let out = try runWithTimeout(args, timeout: timeout)
            let trimmed = summarizeOutput(out)
            if !trimmed.isEmpty {
                appendLog("out: \(trimmed)")
            }
            appendLog("✓ \(step)")
            return out
        } catch {
            appendLog("✗ \(step): \(error.localizedDescription)")
            throw error
        }
    }

    private func summarizeOutput(_ text: String, maxChars: Int = 260) -> String {
        let cleaned = DeviceLogRedactor.sanitizedMessage(
            text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(3)
            .joined(separator: " | ")
        )
        if cleaned.count <= maxChars { return cleaned }
        return String(cleaned.prefix(maxChars)) + "..."
    }

    private func sendCoordinateByLegacyCommand(latitude: Double, longitude: Double) throws {
        guard let ep = rsdEndpoint else {
            throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "RSD is not ready"
            ])
        }
        let cmd = try resolveCLI()
        let mode = simulateLocationMode ?? .legacy
        _ = try runWithTimeout(
            cmd + mode.setArgs(host: ep.host, port: ep.port, latitude: latitude, longitude: longitude),
            timeout: AppConstants.Timeouts.coordinateSend
        )
    }

    private func sendCoordinate(latitude: Double, longitude: Double) throws {
        guard let ep = rsdEndpoint else {
            throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "RSD is not ready"
            ])
        }

        if simulateLocationMode == .dvt {
            try startDvtStreamIfNeeded(host: ep.host, port: ep.port)
            try dvtStream.send(latitude: latitude, longitude: longitude)
            return
        }

        try sendCoordinateByLegacyCommand(latitude: latitude, longitude: longitude)
    }

    private func startDvtStreamIfNeeded(host: String, port: String) throws {
        if dvtStream.isRunning {
            return
        }

        expectedDvtStreamExit = false

        try dvtStream.start(
            host: host,
            port: port,
            onOutput: { [weak self] text in
                self?.appendLog("dvt-stream: \(self?.summarizeOutput(text, maxChars: 180) ?? text)")
            },
            onError: { [weak self] text in
                self?.appendLog("dvt-stream err: \(self?.summarizeOutput(text, maxChars: 180) ?? text)")
            },
            onExit: { [weak self] status in
                guard let self else { return }
                self.appendLog("dvt-stream exited: \(status)")
                if self.expectedDvtStreamExit {
                    self.expectedDvtStreamExit = false
                    return
                }
                self.handleUnexpectedConnectionLoss(reason: "Location stream exited (code: \(status))")
            }
        )
    }

    private func run(_ args: [String]) throws -> String {
        try runProcess(args, timeout: nil)
    }

    private func runWithTimeout(_ args: [String], timeout: TimeInterval) throws -> String {
        try runProcess(args, timeout: timeout)
    }

    private func runProcess(_ args: [String], timeout: TimeInterval?) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.standardInput = FileHandle.nullDevice

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        let output = LockedProcessOutput()

        @Sendable func append(_ data: Data, toStdErr: Bool) {
            output.append(data, toStdErr: toStdErr)
        }

        out.fileHandleForReading.readabilityHandler = { handle in
            append(handle.availableData, toStdErr: false)
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            append(handle.availableData, toStdErr: true)
        }

        try p.run()

        if let timeout {
            let deadline = Date().addingTimeInterval(timeout)
            while p.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if p.isRunning {
                p.terminate()
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                append(out.fileHandleForReading.readDataToEndOfFile(), toStdErr: false)
                append(err.fileHandleForReading.readDataToEndOfFile(), toStdErr: true)
                let strings = output.strings()
                let details = [strings.stderr, strings.stdout]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty }) ?? "No additional output"
                throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "command timed out: \(DeviceLogRedactor.sanitizedCommandString(args)) | \(DeviceLogRedactor.sanitizedMessage(details))"
                ])
            }
        } else {
            p.waitUntilExit()
        }

        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        append(out.fileHandleForReading.readDataToEndOfFile(), toStdErr: false)
        append(err.fileHandleForReading.readDataToEndOfFile(), toStdErr: true)

        let strings = output.strings()
        let stdoutString = strings.stdout
        let stderrString = strings.stderr

        if p.terminationStatus != 0 {
            let details = [stderrString, stdoutString]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "Command failed"
            throw NSError(domain: "DeviceManager", code: Int(p.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: DeviceLogRedactor.sanitizedMessage(details)
            ])
        }

        return stdoutString
    }
}
