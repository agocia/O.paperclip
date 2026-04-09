import Foundation

enum ManagedHelperKind: String {
    case tunnel = "tunnel"
    case privilegedTunnel = "privileged-tunnel"
    case dvtStream = "dvt-stream"
}

struct ManagedHelperRecord {
    let helperID: String
    let sessionID: String
    let kind: ManagedHelperKind
    let pid: Int32
    let parentPID: Int32?
    let childPID: Int32?
    let startedAt: String?
    let pidFilePath: String?
    let stopFilePath: String?
    let command: String?
    let recordURL: URL

    var pidFileURL: URL? {
        guard let pidFilePath, !pidFilePath.isEmpty else { return nil }
        return URL(fileURLWithPath: pidFilePath)
    }

    var stopFileURL: URL? {
        guard let stopFilePath, !stopFilePath.isEmpty else { return nil }
        return URL(fileURLWithPath: stopFilePath)
    }

    func serialized() -> String {
        var lines: [String] = [
            "helperID=\(helperID)",
            "sessionID=\(sessionID)",
            "kind=\(kind.rawValue)",
            "pid=\(pid)"
        ]

        if let parentPID {
            lines.append("parentPID=\(parentPID)")
        }
        if let childPID {
            lines.append("childPID=\(childPID)")
        }
        if let startedAt, !startedAt.isEmpty {
            lines.append("startedAt=\(startedAt)")
        }
        if let pidFilePath, !pidFilePath.isEmpty {
            lines.append("pidFilePath=\(pidFilePath)")
        }
        if let stopFilePath, !stopFilePath.isEmpty {
            lines.append("stopFilePath=\(stopFilePath)")
        }
        if let command, !command.isEmpty {
            lines.append("command=\(command)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func load(from url: URL) -> ManagedHelperRecord? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var fields: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            fields[key] = value
        }

        guard
            let helperID = fields["helperID"], !helperID.isEmpty,
            let sessionID = fields["sessionID"], !sessionID.isEmpty,
            let kindRaw = fields["kind"], let kind = ManagedHelperKind(rawValue: kindRaw),
            let pidRaw = fields["pid"], let pid = Int32(pidRaw)
        else {
            return nil
        }

        return ManagedHelperRecord(
            helperID: helperID,
            sessionID: sessionID,
            kind: kind,
            pid: pid,
            parentPID: fields["parentPID"].flatMap(Int32.init),
            childPID: fields["childPID"].flatMap(Int32.init),
            startedAt: fields["startedAt"],
            pidFilePath: fields["pidFilePath"],
            stopFilePath: fields["stopFilePath"],
            command: fields["command"],
            recordURL: url
        )
    }
}

final class HelperProcessRegistry {
    private let directoryURL: URL
    private let lock = NSLock()

    init(directoryURL: URL = DiagnosticsPaths.directoryURL(named: "HelperRegistry")) {
        self.directoryURL = directoryURL
        ensureDirectory()
    }

    func makeHelperID() -> String {
        UUID().uuidString
    }

    func recordURL(for helperID: String) -> URL {
        directoryURL.appendingPathComponent("\(helperID).state")
    }

    @discardableResult
    func register(
        helperID: String = UUID().uuidString,
        sessionID: String,
        kind: ManagedHelperKind,
        pid: Int32,
        parentPID: Int32? = Int32(ProcessInfo.processInfo.processIdentifier),
        childPID: Int32? = nil,
        startedAt: String? = nil,
        pidFileURL: URL? = nil,
        stopFileURL: URL? = nil,
        command: String? = nil
    ) -> String {
        let startedAt = startedAt ?? ISO8601DateFormatter().string(from: Date())
        let record = ManagedHelperRecord(
            helperID: helperID,
            sessionID: sessionID,
            kind: kind,
            pid: pid,
            parentPID: parentPID,
            childPID: childPID,
            startedAt: startedAt,
            pidFilePath: pidFileURL?.path,
            stopFilePath: stopFileURL?.path,
            command: command,
            recordURL: recordURL(for: helperID)
        )
        write(record)
        return helperID
    }

    func prepareRecordFile(helperID: String) -> URL {
        let url = recordURL(for: helperID)
        ensureDirectory()
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        } else {
            try? Data().write(to: url, options: .atomic)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    func unregister(helperID: String) {
        let url = recordURL(for: helperID)
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }

    func records() -> [ManagedHelperRecord] {
        ensureDirectory()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "state" }
            .compactMap(ManagedHelperRecord.load(from:))
    }

    private func write(_ record: ManagedHelperRecord) {
        let data = Data(record.serialized().utf8)
        lock.lock()
        defer { lock.unlock() }
        let url = prepareRecordFile(helperID: record.helperID)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }
}
