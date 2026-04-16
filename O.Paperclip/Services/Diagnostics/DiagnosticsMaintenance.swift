import CryptoKit
import Foundation

enum DiagnosticsLogLimits {
    static let defaultMaxBytes: UInt64 = 256 * 1024
    static let compactMaxBytes: UInt64 = 64 * 1024
}

final class RotatingRuntimeLogStore: @unchecked Sendable {
    let logURL: URL
    let backupURL: URL
    let maxBytes: UInt64
    private let fileManager: FileManager

    init(logURL: URL, maxBytes: UInt64 = DiagnosticsLogLimits.defaultMaxBytes, fileManager: FileManager = .default) {
        self.logURL = logURL
        self.backupURL = logURL.deletingLastPathComponent().appendingPathComponent(logURL.lastPathComponent + ".1")
        self.maxBytes = maxBytes
        self.fileManager = fileManager
    }

    func prepareForAppend(resetIfOversized: Bool = false) {
        let directoryURL = logURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if resetIfOversized {
            rotateIfNeeded(incomingBytes: 0)
        }

        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: Data())
        }
    }

    func reset() {
        prepareForAppend()
        try? Data().write(to: logURL, options: .atomic)
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

    func rotateIfNeeded(incomingBytes: UInt64) {
        let currentSize = (try? fileManager.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber)?.uint64Value ?? 0
        guard currentSize + incomingBytes > maxBytes else { return }

        try? fileManager.removeItem(at: backupURL)
        if fileManager.fileExists(atPath: logURL.path) {
            try? fileManager.moveItem(at: logURL, to: backupURL)
        }
    }
}

private struct LegacyDiagnosticsMigrationRecord: Codable {
    let version: Int
    let migratedAt: Date
    let migratedRoots: [String]
}

enum LegacyAppSupportMigrator {
    private static let migrationVersion = 1
    private static let trackedDirectoryNames = [
        "SavedLocations",
        "ImportedGPXRoutes",
        "ImportedPurePointOverlays",
    ]
    private static let storedPathKeys = [
        "saved-location-paths",
        "imported-gpx-route-paths",
        "pure-point-imported-kml-paths",
    ]
    private static let storedTitleKeys = [
        "imported-gpx-route-titles",
        "pure-point-imported-kml-titles",
    ]
    private static let legacyRootNames = [
        "O.Paperclip",
        "O-Paperclip",
    ]

    static func migrateIfNeeded() {
        let targetRoot = DiagnosticsPaths.appSupportDirectoryURL
        let baseDirectory = targetRoot.deletingLastPathComponent()
        let legacyRoots = legacyRootNames
            .map { baseDirectory.appendingPathComponent($0, isDirectory: true) }
            .filter { $0.path != targetRoot.path && FileManager.default.fileExists(atPath: $0.path) }

        migrateIfNeeded(targetRoot: targetRoot, legacyRoots: legacyRoots)
    }

    static func migrateIfNeeded(
        targetRoot: URL,
        legacyRoots: [URL],
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        let markerURL = targetRoot.appendingPathComponent("maintenance-migration-v\(migrationVersion).json")
        if fileManager.fileExists(atPath: markerURL.path) {
            return
        }

        try? fileManager.createDirectory(at: targetRoot, withIntermediateDirectories: true)

        var migratedRoots: [String] = []
        var rewrittenPaths: [String: String] = [:]

        for legacyRoot in legacyRoots {
            if migrateUserFiles(from: legacyRoot, to: targetRoot, rewrittenPaths: &rewrittenPaths) {
                migratedRoots.append(legacyRoot.lastPathComponent)
            }
            cleanupRegenerableArtifacts(in: legacyRoot)
        }

        rewriteStoredPaths(using: rewrittenPaths, defaults: defaults)
        writeMarker(at: markerURL, migratedRoots: migratedRoots)
    }

    private static func migrateUserFiles(
        from legacyRoot: URL,
        to targetRoot: URL,
        rewrittenPaths: inout [String: String]
    ) -> Bool {
        let fileManager = FileManager.default
        var didMigrateAnyFile = false

        for directoryName in trackedDirectoryNames {
            let sourceDirectory = legacyRoot.appendingPathComponent(directoryName, isDirectory: true)
            guard let urls = try? fileManager.contentsOfDirectory(
                at: sourceDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ), !urls.isEmpty else {
                continue
            }

            let targetDirectory = targetRoot.appendingPathComponent(directoryName, isDirectory: true)
            try? fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

            for sourceURL in urls {
                guard (try? sourceURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    continue
                }

                let destinationURL = safeDestinationURL(for: sourceURL, in: targetDirectory)
                registerPathRewrite(from: sourceURL, to: destinationURL, rewrittenPaths: &rewrittenPaths)

                if !fileManager.fileExists(atPath: destinationURL.path) {
                    try? fileManager.copyItem(at: sourceURL, to: destinationURL)
                    didMigrateAnyFile = true
                    continue
                }

                if !fileContentsMatch(sourceURL, destinationURL) {
                    let uniqueURL = uniqueDestinationURL(for: sourceURL, in: targetDirectory)
                    registerPathRewrite(from: sourceURL, to: uniqueURL, rewrittenPaths: &rewrittenPaths)
                    if !fileManager.fileExists(atPath: uniqueURL.path) {
                        try? fileManager.copyItem(at: sourceURL, to: uniqueURL)
                        didMigrateAnyFile = true
                    }
                }
            }
        }

        return didMigrateAnyFile
    }

    private static func cleanupRegenerableArtifacts(in legacyRoot: URL) {
        let fileManager = FileManager.default
        for name in ["Logs", "PrivilegedTunnel"] {
            try? fileManager.removeItem(at: legacyRoot.appendingPathComponent(name, isDirectory: true))
        }
        try? fileManager.removeItem(at: legacyRoot.appendingPathComponent(".DS_Store"))
    }

    private static func rewriteStoredPaths(using mapping: [String: String], defaults: UserDefaults) {
        guard !mapping.isEmpty else { return }
        for key in storedPathKeys {
            let raw = defaults.array(forKey: key) as? [String] ?? []
            let rewritten = deduplicated(raw.map { rewrittenPath(for: $0, using: mapping) })
            defaults.set(rewritten, forKey: key)
        }

        for key in storedTitleKeys {
            let raw = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
            var rewritten: [String: String] = [:]
            for (path, title) in raw {
                rewritten[rewrittenPath(for: path, using: mapping)] = title
            }
            defaults.set(rewritten, forKey: key)
        }
    }

    private static func writeMarker(at url: URL, migratedRoots: [String]) {
        let record = LegacyDiagnosticsMigrationRecord(
            version: migrationVersion,
            migratedAt: Date(),
            migratedRoots: migratedRoots
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func safeDestinationURL(for sourceURL: URL, in directory: URL) -> URL {
        let candidate = directory.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
        if !FileManager.default.fileExists(atPath: candidate.path) || fileContentsMatch(sourceURL, candidate) {
            return candidate
        }
        return uniqueDestinationURL(for: sourceURL, in: directory)
    }

    private static func uniqueDestinationURL(for sourceURL: URL, in directory: URL) -> URL {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let digest = shortDigest(for: sourceURL.path)
        let filename = ext.isEmpty ? "\(base)-migrated-\(digest)" : "\(base)-migrated-\(digest).\(ext)"
        return directory.appendingPathComponent(filename, isDirectory: false)
    }

    private static func fileContentsMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsData = try? Data(contentsOf: lhs), let rhsData = try? Data(contentsOf: rhs) else {
            return false
        }
        return lhsData == rhsData
    }

    private static func shortDigest(for value: String) -> String {
        let data = Data(value.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    private static func registerPathRewrite(
        from sourceURL: URL,
        to destinationURL: URL,
        rewrittenPaths: inout [String: String]
    ) {
        guard sourceURL.path != destinationURL.path else { return }

        for alias in pathAliases(for: sourceURL) {
            rewrittenPaths[alias] = destinationURL.path
        }
    }

    private static func rewrittenPath(for path: String, using mapping: [String: String]) -> String {
        for alias in pathAliases(for: URL(fileURLWithPath: path)) {
            if let rewritten = mapping[alias] {
                return rewritten
            }
        }
        return path
    }

    private static func pathAliases(for url: URL) -> [String] {
        var aliases: [String] = []
        for candidate in [url.path, url.standardizedFileURL.path, url.resolvingSymlinksInPath().path] {
            if !candidate.isEmpty, !aliases.contains(candidate) {
                aliases.append(candidate)
            }
        }
        return aliases
    }

    private static func deduplicated(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
    }
}
