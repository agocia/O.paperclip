import CoreLocation
import CryptoKit
import Foundation
import UniformTypeIdentifiers

public struct ImportedGPXRoute: Identifiable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let sourceName: String
    public let points: [CLLocationCoordinate2D]
    public let totalDistance: CLLocationDistance
    public let sourceFilePath: String?
    public let sourceRouteID: String

    nonisolated func renamed(to customTitle: String) -> ImportedGPXRoute {
        let trimmed = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        return ImportedGPXRoute(
            id: id,
            title: trimmed,
            sourceName: sourceName,
            points: points,
            totalDistance: totalDistance,
            sourceFilePath: sourceFilePath,
            sourceRouteID: sourceRouteID
        )
    }

    public static func == (lhs: ImportedGPXRoute, rhs: ImportedGPXRoute) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum GPXImportError: LocalizedError {
    case invalidGPX
    case noRouteFound

    var errorDescription: String? {
        switch self {
        case .invalidGPX:
            return "GPX 內容無法解析。"
        case .noRouteFound:
            return "這份 GPX 沒有可匯入的固定路線。"
        }
    }
}

private struct ImportedGPXRouteSnapshot: Codable {
    let id: String
    let title: String
    let sourceName: String
    let points: [CodableCoordinate]
    let totalDistance: CLLocationDistance
    let sourceRouteID: String
}

private struct CodableCoordinate: Codable {
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

private struct GPXRouteCandidate {
    let sourceRouteID: String
    let name: String?
    let points: [CLLocationCoordinate2D]
}

enum ImportedGPXRouteStore {
    nonisolated private static let storedPathsKey = "imported-gpx-route-paths"
    nonisolated private static let storedTitlesKey = "imported-gpx-route-titles"
    nonisolated private static var snapshotsDirectoryURL: URL {
        DiagnosticsPaths.directoryURL(named: "ImportedGPXRoutes")
    }

    nonisolated static func loadRoutes() -> [ImportedGPXRoute] {
        let titles = loadTitleOverrides()
        let routes = loadPaths().compactMap { path -> ImportedGPXRoute? in
            guard let route = try? routeFromSnapshot(at: URL(fileURLWithPath: path)) else { return nil }
            guard let storedPath = route.sourceFilePath, let title = titles[storedPath] else { return route }
            return route.renamed(to: title)
        }
        let validPaths = routes.compactMap(\.sourceFilePath)
        if validPaths != loadPaths() {
            savePaths(validPaths)
            saveTitleOverrides(titles.filter { validPaths.contains($0.key) })
        }
        return routes
    }

    nonisolated static func previewRoutes(from urls: [URL]) throws -> [ImportedGPXRoute] {
        try urls.flatMap(previewRoutes(from:))
    }

    nonisolated static func persistImportedRoutes(_ routes: [ImportedGPXRoute]) throws -> [ImportedGPXRoute] {
        try routes.map(persistImportedRoute(_:))
    }

    nonisolated static func deleteStoredRoute(_ route: ImportedGPXRoute) {
        guard let path = route.sourceFilePath else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }

    nonisolated static func loadPaths() -> [String] {
        let raw = UserDefaults.standard.array(forKey: storedPathsKey) as? [String] ?? []
        var seen: Set<String> = []
        return raw.filter { seen.insert($0).inserted }
    }

    nonisolated static func savePaths(_ paths: [String]) {
        var seen: Set<String> = []
        let deduped = paths.filter { seen.insert($0).inserted }
        UserDefaults.standard.set(deduped, forKey: storedPathsKey)
    }

    nonisolated static func loadTitleOverrides() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: storedTitlesKey) as? [String: String] ?? [:]
    }

    nonisolated static func saveTitleOverrides(_ titles: [String: String]) {
        UserDefaults.standard.set(titles, forKey: storedTitlesKey)
    }

    private nonisolated static func previewRoutes(from url: URL) throws -> [ImportedGPXRoute] {
        let data = try Data(contentsOf: url)
        return try GPXRouteParser.parse(
            data: data,
            fallbackTitle: url.deletingPathExtension().lastPathComponent,
            sourceName: url.lastPathComponent,
            stableIDPrefix: previewRouteIDPrefix(for: url.path),
            sourceFilePath: url.path
        )
    }

    private nonisolated static func persistImportedRoute(_ route: ImportedGPXRoute) throws -> ImportedGPXRoute {
        guard let sourceFilePath = route.sourceFilePath else {
            throw GPXImportError.invalidGPX
        }

        let sourceURL = URL(fileURLWithPath: sourceFilePath)
        let data = try Data(contentsOf: sourceURL)
        let parsedRoutes = try GPXRouteParser.parse(
            data: data,
            fallbackTitle: sourceURL.deletingPathExtension().lastPathComponent,
            sourceName: sourceURL.lastPathComponent,
            stableIDPrefix: previewRouteIDPrefix(for: sourceURL.path),
            sourceFilePath: sourceURL.path
        )

        guard let matchedRoute = parsedRoutes.first(where: { $0.sourceRouteID == route.sourceRouteID }) else {
            throw GPXImportError.invalidGPX
        }

        let digest = stableContentID(for: matchedRoute.points, sourceRouteID: matchedRoute.sourceRouteID)
        let snapshotURL = snapshotsDirectoryURL.appendingPathComponent("\(digest).json")
        let snapshot = ImportedGPXRouteSnapshot(
            id: "imported-\(digest)",
            title: matchedRoute.title,
            sourceName: matchedRoute.sourceName,
            points: matchedRoute.points.map(CodableCoordinate.init),
            totalDistance: matchedRoute.totalDistance,
            sourceRouteID: matchedRoute.sourceRouteID
        )
        let encoded = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: snapshotsDirectoryURL, withIntermediateDirectories: true)
        try encoded.write(to: snapshotURL, options: .atomic)
        return try routeFromSnapshot(at: snapshotURL).renamed(to: route.title)
    }

    private nonisolated static func routeFromSnapshot(at url: URL) throws -> ImportedGPXRoute {
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(ImportedGPXRouteSnapshot.self, from: data)
        return ImportedGPXRoute(
            id: snapshot.id,
            title: snapshot.title,
            sourceName: snapshot.sourceName,
            points: snapshot.points.map(\.coordinate),
            totalDistance: snapshot.totalDistance,
            sourceFilePath: url.path,
            sourceRouteID: snapshot.sourceRouteID
        )
    }

    private nonisolated static func previewRouteIDPrefix(for path: String) -> String {
        let encoded = Data(path.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return "preview-\(encoded)"
    }

    private nonisolated static func stableContentID(
        for points: [CLLocationCoordinate2D],
        sourceRouteID: String
    ) -> String {
        let pointSignature = points
            .map { "\($0.latitude),\($0.longitude)" }
            .joined(separator: "|")
        let payload = "\(sourceRouteID)::\(pointSignature)"
        return SHA256.hash(data: Data(payload.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}

enum GPXRouteParser {
    nonisolated static func parse(
        data: Data,
        fallbackTitle: String,
        sourceName: String,
        stableIDPrefix: String,
        sourceFilePath: String?
    ) throws -> [ImportedGPXRoute] {
        let delegate = GPXDocumentParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw GPXImportError.invalidGPX
        }

        let fallbackBaseTitle = delegate.documentTitle?.nilIfBlank ?? fallbackTitle
        let candidates = delegate.candidates
            .map { candidate in
                GPXRouteCandidate(
                    sourceRouteID: candidate.sourceRouteID,
                    name: candidate.name?.nilIfBlank,
                    points: normalizePoints(candidate.points)
                )
            }
            .filter { $0.points.count > 1 }

        guard !candidates.isEmpty else {
            throw GPXImportError.noRouteFound
        }

        let hasMultipleCandidates = candidates.count > 1

        return candidates.enumerated().map { index, candidate in
            let title: String
            if let name = candidate.name {
                title = name
            } else if hasMultipleCandidates {
                title = "\(fallbackBaseTitle) 路線 \(index + 1)"
            } else {
                title = fallbackBaseTitle
            }

            let totalDistance = RouteMotionEngine.cumulativeDistances(for: candidate.points).last ?? 0

            return ImportedGPXRoute(
                id: "\(stableIDPrefix)-\(candidate.sourceRouteID)",
                title: title,
                sourceName: sourceName,
                points: candidate.points,
                totalDistance: totalDistance,
                sourceFilePath: sourceFilePath,
                sourceRouteID: candidate.sourceRouteID
            )
        }
    }

    private nonisolated static func normalizePoints(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(points.count)

        for point in points {
            guard CLLocationCoordinate2DIsValid(point),
                  point.latitude.isFinite,
                  point.longitude.isFinite else {
                continue
            }

            if let last = result.last,
               abs(last.latitude - point.latitude) < 0.0000001,
               abs(last.longitude - point.longitude) < 0.0000001 {
                continue
            }

            result.append(point)
        }

        return result
    }
}

private final class GPXDocumentParserDelegate: NSObject, XMLParserDelegate {
    struct CandidateDraft {
        let sourceRouteID: String
        var name: String?
        var points: [CLLocationCoordinate2D]
    }

    private enum ContainerKind {
        case track
        case route
    }

    var documentTitle: String?
    var candidates: [CandidateDraft] = []

    private var currentText = ""
    private var currentTrack: CandidateDraft?
    private var currentRoute: CandidateDraft?
    private var trackIndex = 0
    private var routeIndex = 0
    private var elementStack: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
        elementStack.append(elementName)

        switch elementName {
        case "trk":
            currentTrack = CandidateDraft(sourceRouteID: "trk-\(trackIndex)", name: nil, points: [])
            trackIndex += 1
        case "rte":
            currentRoute = CandidateDraft(sourceRouteID: "rte-\(routeIndex)", name: nil, points: [])
            routeIndex += 1
        case "trkpt":
            guard let coordinate = coordinate(from: attributeDict),
                  currentTrack != nil else { return }
            currentTrack?.points.append(coordinate)
        case "rtept":
            guard let coordinate = coordinate(from: attributeDict),
                  currentRoute != nil else { return }
            currentRoute?.points.append(coordinate)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if elementName == "name", !text.isEmpty {
            if currentRoute != nil {
                currentRoute?.name = text
            } else if currentTrack != nil {
                currentTrack?.name = text
            } else if documentTitle == nil {
                documentTitle = text
            }
        }

        switch elementName {
        case "trk":
            if let currentTrack {
                candidates.append(currentTrack)
            }
            currentTrack = nil
        case "rte":
            if let currentRoute {
                candidates.append(currentRoute)
            }
            currentRoute = nil
        default:
            break
        }

        currentText = ""
        _ = elementStack.popLast()
    }

    private func coordinate(from attributes: [String: String]) -> CLLocationCoordinate2D? {
        guard let latitudeString = attributes["lat"],
              let longitudeString = attributes["lon"],
              let latitude = Double(latitudeString),
              let longitude = Double(longitudeString) else {
            return nil
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension UTType {
    static var gpx: UTType {
        UTType(filenameExtension: "gpx") ?? .xml
    }
}
