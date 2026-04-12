import CoreLocation
import CryptoKit
import Foundation

enum SavedLocationKind: String, Codable, CaseIterable, Identifiable {
    case point
    case route
    case loop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .point: return "定點"
        case .route: return "線路"
        case .loop: return "迴路"
        }
    }

    var sortOrder: Int {
        switch self {
        case .point: return 0
        case .route: return 1
        case .loop: return 2
        }
    }
}

enum SavedLocationSortMode: String, CaseIterable, Identifiable {
    case createdAt
    case region
    case kind

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .createdAt: return "建立時間"
        case .region: return "地理位置"
        case .kind: return "類型"
        }
    }
}

enum SavedLocationRegionGroup: String, Codable, CaseIterable, Identifiable {
    case taiwan
    case eastAsia
    case southeastAsia
    case southAsia
    case middleEast
    case europe
    case africa
    case northAmerica
    case southAmerica
    case oceania
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .taiwan: return "台灣"
        case .eastAsia: return "東亞"
        case .southeastAsia: return "東南亞"
        case .southAsia: return "南亞"
        case .middleEast: return "中東"
        case .europe: return "歐洲"
        case .africa: return "非洲"
        case .northAmerica: return "北美"
        case .southAmerica: return "南美"
        case .oceania: return "大洋洲"
        case .other: return "其他"
        }
    }

    var sortOrder: Int {
        switch self {
        case .taiwan: return 0
        case .eastAsia: return 1
        case .southeastAsia: return 2
        case .southAsia: return 3
        case .middleEast: return 4
        case .europe: return 5
        case .africa: return 6
        case .northAmerica: return 7
        case .southAmerica: return 8
        case .oceania: return 9
        case .other: return 10
        }
    }
}

struct SavedLocationItem: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let kind: SavedLocationKind
    let coordinates: [CLLocationCoordinate2D]
    let totalDistance: CLLocationDistance
    let createdAt: Date
    let regionGroup: SavedLocationRegionGroup
    let sourceMode: String
    let sourceFilePath: String

    var representativeCoordinate: CLLocationCoordinate2D? {
        coordinates.first
    }

    var summaryText: String {
        switch kind {
        case .point:
            return "1 個點位"
        case .route, .loop:
            let kilometers = totalDistance / 1000
            return "\(coordinates.count) 點，\(String(format: "%.2f", kilometers)) km"
        }
    }

    func renamed(to title: String) -> SavedLocationItem {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        return SavedLocationItem(
            id: id,
            title: trimmed,
            kind: kind,
            coordinates: coordinates,
            totalDistance: totalDistance,
            createdAt: createdAt,
            regionGroup: regionGroup,
            sourceMode: sourceMode,
            sourceFilePath: sourceFilePath
        )
    }

    static func == (lhs: SavedLocationItem, rhs: SavedLocationItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct SavedLocationDraft {
    let title: String
    let kind: SavedLocationKind
    let coordinates: [CLLocationCoordinate2D]
    let totalDistance: CLLocationDistance
    let createdAt: Date
    let sourceMode: String
}

private struct SavedLocationSnapshot: Codable {
    let id: String
    let title: String
    let kind: SavedLocationKind
    let coordinates: [SavedCoordinate]
    let totalDistance: CLLocationDistance
    let createdAt: Date
    let regionGroup: SavedLocationRegionGroup
    let sourceMode: String
}

private struct SavedCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum SavedLocationStore {
    nonisolated private static let storedPathsKey = "saved-location-paths"
    nonisolated private static var snapshotsDirectoryURL: URL {
        DiagnosticsPaths.directoryURL(named: "SavedLocations")
    }

    nonisolated static func loadItems() -> [SavedLocationItem] {
        let items = loadPaths().compactMap { path -> SavedLocationItem? in
            try? itemFromSnapshot(at: URL(fileURLWithPath: path))
        }
        let validPaths = items.map(\.sourceFilePath)
        if validPaths != loadPaths() {
            savePaths(validPaths)
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    nonisolated static func persist(_ draft: SavedLocationDraft) throws -> SavedLocationItem {
        let normalized = normalizeCoordinates(draft.coordinates)
        guard !normalized.isEmpty else {
            throw NSError(domain: "SavedLocationStore", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "目前沒有可儲存的位置或路線。"
            ])
        }

        let id = stableID(for: normalized, createdAt: draft.createdAt, kind: draft.kind)
        let snapshotURL = snapshotsDirectoryURL.appendingPathComponent("\(id).json")
        let snapshot = SavedLocationSnapshot(
            id: id,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: draft.kind,
            coordinates: normalized.map(SavedCoordinate.init),
            totalDistance: draft.totalDistance,
            createdAt: draft.createdAt,
            regionGroup: classifyRegion(for: normalized.first),
            sourceMode: draft.sourceMode
        )
        let encoded = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: snapshotsDirectoryURL, withIntermediateDirectories: true)
        try encoded.write(to: snapshotURL, options: .atomic)

        var paths = loadPaths()
        paths.removeAll { $0 == snapshotURL.path }
        paths.insert(snapshotURL.path, at: 0)
        savePaths(paths)

        return try itemFromSnapshot(at: snapshotURL)
    }

    nonisolated static func rename(_ item: SavedLocationItem, to title: String) throws -> SavedLocationItem {
        let updated = item.renamed(to: title)
        try writeSnapshot(for: updated)
        return updated
    }

    nonisolated static func deleteStoredItem(_ item: SavedLocationItem) {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: item.sourceFilePath))
        savePaths(loadPaths().filter { $0 != item.sourceFilePath })
    }

    private nonisolated static func writeSnapshot(for item: SavedLocationItem) throws {
        let snapshot = SavedLocationSnapshot(
            id: item.id,
            title: item.title,
            kind: item.kind,
            coordinates: item.coordinates.map(SavedCoordinate.init),
            totalDistance: item.totalDistance,
            createdAt: item.createdAt,
            regionGroup: item.regionGroup,
            sourceMode: item.sourceMode
        )
        let encoded = try JSONEncoder().encode(snapshot)
        let url = URL(fileURLWithPath: item.sourceFilePath)
        try FileManager.default.createDirectory(at: snapshotsDirectoryURL, withIntermediateDirectories: true)
        try encoded.write(to: url, options: .atomic)
    }

    private nonisolated static func itemFromSnapshot(at url: URL) throws -> SavedLocationItem {
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(SavedLocationSnapshot.self, from: data)
        return SavedLocationItem(
            id: snapshot.id,
            title: snapshot.title,
            kind: snapshot.kind,
            coordinates: snapshot.coordinates.map(\.coordinate),
            totalDistance: snapshot.totalDistance,
            createdAt: snapshot.createdAt,
            regionGroup: snapshot.regionGroup,
            sourceMode: snapshot.sourceMode,
            sourceFilePath: url.path
        )
    }

    private nonisolated static func loadPaths() -> [String] {
        let raw = UserDefaults.standard.array(forKey: storedPathsKey) as? [String] ?? []
        var seen: Set<String> = []
        return raw.filter { seen.insert($0).inserted }
    }

    private nonisolated static func savePaths(_ paths: [String]) {
        var seen: Set<String> = []
        UserDefaults.standard.set(paths.filter { seen.insert($0).inserted }, forKey: storedPathsKey)
    }

    private nonisolated static func stableID(
        for coordinates: [CLLocationCoordinate2D],
        createdAt: Date,
        kind: SavedLocationKind
    ) -> String {
        let signature = coordinates
            .map { "\($0.latitude),\($0.longitude)" }
            .joined(separator: "|")
        let payload = "\(kind.rawValue)::\(createdAt.timeIntervalSince1970)::\(signature)"
        let digest = SHA256.hash(data: Data(payload.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        return "saved-\(digest)"
    }

    private nonisolated static func normalizeCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(coordinates.count)
        for coordinate in coordinates {
            guard CLLocationCoordinate2DIsValid(coordinate),
                  coordinate.latitude.isFinite,
                  coordinate.longitude.isFinite else {
                continue
            }
            if let last = result.last,
               abs(last.latitude - coordinate.latitude) < 0.0000001,
               abs(last.longitude - coordinate.longitude) < 0.0000001 {
                continue
            }
            result.append(coordinate)
        }
        return result
    }

    private nonisolated static func classifyRegion(for coordinate: CLLocationCoordinate2D?) -> SavedLocationRegionGroup {
        guard let coordinate,
              CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite else {
            return .other
        }

        let lat = coordinate.latitude
        let lon = coordinate.longitude

        if (21.5...25.5).contains(lat), (119.0...122.5).contains(lon) {
            return .taiwan
        }
        if (-11.0...28.0).contains(lat), (95.0...141.0).contains(lon) {
            return .southeastAsia
        }
        if (20.0...48.0).contains(lat), (122.5...150.0).contains(lon) {
            return .eastAsia
        }
        if (5.0...37.5).contains(lat), (68.0...92.0).contains(lon) {
            return .southAsia
        }
        if (12.0...42.0).contains(lat), (34.0...64.0).contains(lon) {
            return .middleEast
        }
        if (35.0...72.0).contains(lat), (-10.0...60.0).contains(lon) {
            return .europe
        }
        if (-35.0...37.0).contains(lat), (-20.0...55.0).contains(lon) {
            return .africa
        }
        if (7.0...84.0).contains(lat), (-170.0 ... -52.0).contains(lon) {
            return .northAmerica
        }
        if (-56.0...13.0).contains(lat), (-82.0 ... -34.0).contains(lon) {
            return .southAmerica
        }
        if (-50.0...5.0).contains(lat), (110.0...180.0).contains(lon) {
            return .oceania
        }
        return .other
    }
}
