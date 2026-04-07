import Foundation
import MapKit
import UniformTypeIdentifiers
import CryptoKit

typealias PurePointRemoteDataFetcher = (URL) throws -> Data

public struct PurePointOverlay: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let sourceName: String
    public let categories: [ShuangbeiPurePointCategory]
    public let points: [ShuangbeiPurePoint]
    public let isBuiltIn: Bool
    public let sourceFilePath: String?

    nonisolated func renamed(to customTitle: String) -> PurePointOverlay {
        let trimmed = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        return PurePointOverlay(
            id: id,
            title: trimmed,
            sourceName: sourceName,
            categories: categories,
            points: points,
            isBuiltIn: isBuiltIn,
            sourceFilePath: sourceFilePath
        )
    }
}

enum PurePointOverlayRepository {
    nonisolated static func initialOverlays() -> [PurePointOverlay] {
        ImportedPurePointOverlayStore.loadOverlays()
    }
}

enum ImportedPurePointOverlayStore {
    nonisolated private static let storedPathsKey = "pure-point-imported-kml-paths"
    nonisolated private static let storedTitlesKey = "pure-point-imported-kml-titles"
    nonisolated private static var snapshotsDirectoryURL: URL {
        DiagnosticsPaths.directoryURL(named: "ImportedPurePointOverlays")
    }

    nonisolated static func loadOverlays() -> [PurePointOverlay] {
        let titles = loadTitleOverrides()
        let overlays = loadPaths().compactMap { path -> PurePointOverlay? in
            guard let overlay = try? overlayFromSnapshot(at: URL(fileURLWithPath: path)) else { return nil }
            guard let storedPath = overlay.sourceFilePath, let title = titles[storedPath] else { return overlay }
            return overlay.renamed(to: title)
        }
        let validPaths = overlays.compactMap(\.sourceFilePath)
        if validPaths != loadPaths() {
            savePaths(validPaths)
            saveTitleOverrides(titles.filter { validPaths.contains($0.key) })
        }
        return overlays
    }

    nonisolated static func previewOverlays(
        from urls: [URL],
        approvedRemoteURLs: Set<URL> = [],
        remoteFetcher: PurePointRemoteDataFetcher? = nil
    ) throws -> [PurePointOverlay] {
        var overlays: [PurePointOverlay] = []
        var approvalURLs: [URL] = []

        for url in urls {
            do {
                overlays.append(
                    try previewOverlay(
                        from: url,
                        approvedRemoteURLs: approvedRemoteURLs,
                        remoteFetcher: remoteFetcher
                    )
                )
            } catch let error as PurePointImportError {
                if case .remoteLinkRequiresApproval(let urls) = error {
                    approvalURLs.append(contentsOf: urls)
                    continue
                }
                throw error
            }
        }

        if !approvalURLs.isEmpty {
            throw PurePointImportError.remoteLinkRequiresApproval(deduplicatedRemoteURLs(approvalURLs))
        }
        return overlays
    }

    nonisolated static func persistImportedOverlays(
        _ overlays: [PurePointOverlay],
        approvedRemoteURLs: Set<URL> = [],
        remoteFetcher: PurePointRemoteDataFetcher? = nil
    ) throws -> [PurePointOverlay] {
        var persisted: [PurePointOverlay] = []
        var approvalURLs: [URL] = []

        for overlay in overlays {
            guard let sourceFilePath = overlay.sourceFilePath else {
                throw PurePointImportError.invalidKML
            }

            do {
                persisted.append(
                    try persistImportedOverlay(
                        from: URL(fileURLWithPath: sourceFilePath),
                        preferredTitle: overlay.title,
                        approvedRemoteURLs: approvedRemoteURLs,
                        remoteFetcher: remoteFetcher
                    )
                )
            } catch let error as PurePointImportError {
                if case .remoteLinkRequiresApproval(let urls) = error {
                    approvalURLs.append(contentsOf: urls)
                    continue
                }
                throw error
            }
        }

        if !approvalURLs.isEmpty {
            throw PurePointImportError.remoteLinkRequiresApproval(deduplicatedRemoteURLs(approvalURLs))
        }
        return persisted
    }

    nonisolated static func deleteStoredOverlay(_ overlay: PurePointOverlay) {
        guard let path = overlay.sourceFilePath else { return }
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

    private nonisolated static func previewOverlay(
        from url: URL,
        approvedRemoteURLs: Set<URL>,
        remoteFetcher: PurePointRemoteDataFetcher?
    ) throws -> PurePointOverlay {
        let resolvedData = try resolvedKMLData(
            from: url,
            approvedRemoteURLs: approvedRemoteURLs,
            remoteFetcher: remoteFetcher
        )
        return try PurePointKMLParser.parse(
            data: resolvedData,
            fallbackTitle: url.deletingPathExtension().lastPathComponent,
            sourceName: url.lastPathComponent,
            stableID: previewOverlayID(for: url.path),
            sourceFilePath: url.path
        )
    }

    private nonisolated static func persistImportedOverlay(
        from sourceURL: URL,
        preferredTitle: String,
        approvedRemoteURLs: Set<URL>,
        remoteFetcher: PurePointRemoteDataFetcher?
    ) throws -> PurePointOverlay {
        let resolvedData = try resolvedKMLData(
            from: sourceURL,
            approvedRemoteURLs: approvedRemoteURLs,
            remoteFetcher: remoteFetcher
        )
        let digest = stableContentID(for: resolvedData)
        let snapshotURL = snapshotURL(for: digest)
        try FileManager.default.createDirectory(at: snapshotsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try resolvedData.write(to: snapshotURL, options: .atomic)
        return try PurePointKMLParser.parse(
            data: resolvedData,
            fallbackTitle: sourceURL.deletingPathExtension().lastPathComponent,
            sourceName: sourceURL.lastPathComponent,
            stableID: "imported-\(digest)",
            sourceFilePath: snapshotURL.path
        )
        .renamed(to: preferredTitle)
    }

    private nonisolated static func overlayFromSnapshot(at url: URL) throws -> PurePointOverlay {
        let sourceData = try Data(contentsOf: url)
        return try PurePointKMLParser.parse(
            data: sourceData,
            fallbackTitle: url.deletingPathExtension().lastPathComponent,
            sourceName: url.lastPathComponent,
            stableID: previewOverlayID(for: url.path),
            sourceFilePath: url.path
        )
    }

    private nonisolated static func resolvedKMLData(
        from url: URL,
        approvedRemoteURLs: Set<URL>,
        remoteFetcher: PurePointRemoteDataFetcher?
    ) throws -> Data {
        let sourceData = try Data(contentsOf: url)
        return try PurePointKMLResolver.resolveKMLData(
            from: sourceData,
            baseURL: url,
            approvedRemoteURLs: approvedRemoteURLs,
            remoteFetcher: remoteFetcher
        )
    }

    private nonisolated static func previewOverlayID(for path: String) -> String {
        let encoded = Data(path.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return "preview-\(encoded)"
    }

    private nonisolated static func stableContentID(for data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func snapshotURL(for digest: String) -> URL {
        snapshotsDirectoryURL.appendingPathComponent("\(digest).kml")
    }

    private nonisolated static func deduplicatedRemoteURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        var result: [URL] = []
        for url in urls {
            let normalized = PurePointKMLResolver.normalizedRemoteURL(url)
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return result
    }
}

enum PurePointKMLResolver {
    nonisolated static func resolveKMLData(
        from data: Data,
        baseURL: URL?,
        approvedRemoteURLs: Set<URL> = [],
        remoteFetcher: PurePointRemoteDataFetcher? = nil
    ) throws -> Data {
        var currentData = data
        var currentBaseURL = baseURL
        let approvedURLs = Set(approvedRemoteURLs.map(normalizedRemoteURL))
        let fetchRemoteData = remoteFetcher ?? { try Data(contentsOf: $0) }

        for _ in 0..<3 {
            if containsPlacemark(in: currentData) {
                return currentData
            }

            guard let href = firstNetworkLinkHref(in: currentData) else {
                return currentData
            }

            let resolvedURL: URL
            if let absoluteURL = URL(string: href), absoluteURL.scheme != nil {
                resolvedURL = absoluteURL.absoluteURL
            } else if let currentBaseURL,
                      let relativeURL = URL(string: href, relativeTo: currentBaseURL)?.absoluteURL {
                resolvedURL = relativeURL
            } else {
                throw PurePointImportError.unsupportedRemoteScheme(href)
            }

            let normalizedURL = normalizedRemoteURL(resolvedURL)
            guard let scheme = normalizedURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                throw PurePointImportError.unsupportedRemoteScheme(normalizedURL.absoluteString)
            }
            guard approvedURLs.contains(normalizedURL) else {
                throw PurePointImportError.remoteLinkRequiresApproval([normalizedURL])
            }

            currentData = try fetchRemoteData(normalizedURL)
            currentBaseURL = normalizedURL
        }

        return currentData
    }

    nonisolated static func normalizedRemoteURL(_ url: URL) -> URL {
        let absoluteURL = url.absoluteURL
        guard var components = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: false) else {
            return absoluteURL
        }
        components.fragment = nil
        return components.url ?? absoluteURL
    }

    private nonisolated static func containsPlacemark(in data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            return false
        }
        return text.contains("<Placemark")
    }

    private nonisolated static func firstNetworkLinkHref(in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            return nil
        }
        guard let regex = try? NSRegularExpression(
            pattern: #"<href>\s*(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?\s*</href>"#,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let hrefRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let href = text[hrefRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return href.isEmpty ? nil : href
    }
}

enum PurePointImportError: LocalizedError {
    case invalidKML
    case noPointPlacemarkFound
    case unsupportedRemoteScheme(String)
    case remoteLinkRequiresApproval([URL])

    var errorDescription: String? {
        switch self {
        case .invalidKML:
            return "KML 內容無法解析。"
        case .noPointPlacemarkFound:
            return "這份 KML 沒有可匯入的點位。"
        case .unsupportedRemoteScheme(let href):
            return "只支援 http/https 的遠端 KML 連結，無法使用：\(href)"
        case .remoteLinkRequiresApproval(let urls):
            let urlList = urls.map(\.absoluteString).joined(separator: "\n")
            return "這份 KML 需要先確認是否抓取遠端內容：\n\(urlList)"
        }
    }
}

enum PurePointKMLParser {
    private static let categoryAliases: [(canonical: String, aliases: [String])] = [
        ("美術館", ["美術館"]),
        ("遊樂園", ["主題樂園", "遊樂園", "動物園"]),
        ("電影院", ["電影院"]),
        ("塔可餅", ["塔可餅"]),
        ("韓國泡菜", ["韓國泡菜"]),
        ("法國麵包", ["法國麵包"]),
        ("咖啡杯", ["咖啡杯"]),
        ("漢堡", ["漢堡"]),
        ("壽司", ["壽司"]),
        ("海灘", ["海灘", "貝殼"]),
        ("山丘", ["山丘"]),
        ("水邊", ["水邊"]),
        ("橋樑", ["橋樑"]),
        ("義式餐廳", ["義式餐廳", "披薩"]),
        ("拉麵", ["拉麵"]),
        ("餐廳", ["餐廳", "廚師"]),
        ("飛機", ["飛機"]),
        ("公車", ["公車"]),
        ("電車", ["電車"]),
        ("飯店", ["飯店備品", "飯店"]),
        ("森林", ["森林"]),
        ("幸運草", ["幸運草", "公園"]),
        ("甜點", ["甜點"]),
        ("洗衣店", ["洗衣店"]),
        ("咖哩", ["咖哩"]),
        ("五金行", ["五金行", "工具"]),
        ("化妝品", ["化妝品"]),
        ("牙刷", ["牙刷"]),
        ("美容院", ["美容院", "剪刀"]),
        ("服飾店", ["服飾店", "服裝店"]),
        ("便利商店", ["便利商店", "便利店"]),
        ("超市", ["超市"]),
        ("郵局", ["郵局"]),
        ("圖書館", ["圖書館", "迷你書"]),
        ("電池", ["電池", "仙女燈"]),
        ("體育館", ["體育館"]),
        ("學校", ["學校", "大學", "學院"])
    ]

    private static let fallbackPalette = [
        "FFEA00", "0288D1", "DB4436", "F57C00", "673AB7",
        "009688", "E91E63", "7CB342", "5C6BC0", "8D6E63"
    ]

    nonisolated static func parse(
        data: Data,
        fallbackTitle: String,
        sourceName: String,
        stableID: String,
        sourceFilePath: String?
    ) throws -> PurePointOverlay {
        let delegate = KMLDocumentParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw PurePointImportError.invalidKML
        }

        var categoriesByID: [String: ShuangbeiPurePointCategory] = [:]
        var categoryOrder: [String] = []
        var points: [ShuangbeiPurePoint] = []

        for (index, placemark) in delegate.placemarks.enumerated() {
            guard let coordinate = parseCoordinate(from: placemark.coordinates) else { continue }

            let categoryID = resolveCategoryID(from: placemark.name)
            let displayName = categoryID
            let colorHex = delegate.colorHex(forStyleURL: placemark.styleURL)
                ?? fallbackColorHex(for: categoryID)

            if categoriesByID[categoryID] == nil {
                categoriesByID[categoryID] = ShuangbeiPurePointCategory(
                    id: categoryID,
                    displayName: displayName,
                    colorHex: colorHex,
                    groupName: placemark.folderPath.joined(separator: " / ")
                )
                categoryOrder.append(categoryID)
            }

            points.append(
                ShuangbeiPurePoint(
                    id: "\(stableID)-\(index)",
                    name: placemark.name,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    categoryID: categoryID,
                    groupName: placemark.folderPath.joined(separator: " / "),
                    note: placemark.description?.nilIfBlank
                )
            )
        }

        guard !points.isEmpty else {
            throw PurePointImportError.noPointPlacemarkFound
        }

        let categories = categoryOrder.compactMap { categoriesByID[$0] }
        let title = delegate.documentTitle?.nilIfBlank ?? fallbackTitle

        return PurePointOverlay(
            id: stableID,
            title: title,
            sourceName: sourceName,
            categories: categories,
            points: points,
            isBuiltIn: false,
            sourceFilePath: sourceFilePath
        )
    }

    private nonisolated static func parseCoordinate(from raw: String?) -> CLLocationCoordinate2D? {
        guard let raw else { return nil }
        let firstCoordinate = raw
            .split(whereSeparator: \ .isWhitespace)
            .first?
            .split(separator: ",")
            .map(String.init) ?? []

        guard firstCoordinate.count >= 2,
              let longitude = Double(firstCoordinate[0]),
              let latitude = Double(firstCoordinate[1]) else {
            return nil
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private nonisolated static func resolveCategoryID(from placemarkName: String) -> String {
        let normalizedName = placemarkName.trimmingCharacters(in: .whitespacesAndNewlines)

        for alias in categoryAliases {
            if alias.aliases.contains(where: { normalizedName.localizedCaseInsensitiveContains($0) }) {
                return alias.canonical
            }
        }

        let token = normalizedName
            .split(whereSeparator: { $0.isWhitespace || "（(｜|/".contains($0) })
            .first
            .map(String.init) ?? ""
        let cleanedToken = token.trimmingCharacters(in: .punctuationCharacters)

        return cleanedToken.isEmpty ? "未分類" : cleanedToken
    }

    private nonisolated static func fallbackColorHex(for categoryID: String) -> String {
        let scalarTotal = categoryID.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return fallbackPalette[scalarTotal % fallbackPalette.count]
    }
}

private final class KMLDocumentParserDelegate: NSObject, XMLParserDelegate {
    struct PlacemarkDraft {
        var name: String = ""
        var description: String?
        var coordinates: String?
        var styleURL: String?
        var folderPath: [String] = []
    }

    private struct ContainerFrame {
        enum Kind {
            case document
            case folder
        }

        let kind: Kind
        var name: String?
    }

    private struct StyleDraft {
        let id: String
        var colorHex: String?
    }

    private struct StyleMapDraft {
        let id: String
        var pairs: [String: String] = [:]
    }

    private struct StyleMapPairDraft {
        var key: String?
        var styleURL: String?
    }

    private(set) var documentTitle: String?
    private(set) var placemarks: [PlacemarkDraft] = []

    private var elementStack: [String] = []
    private var textBuffer: String = ""
    private var containers: [ContainerFrame] = []
    private var currentPlacemark: PlacemarkDraft?
    private var currentStyle: StyleDraft?
    private var currentStyleMap: StyleMapDraft?
    private var currentStyleMapPair: StyleMapPairDraft?
    private var isInsidePoint = false

    private var styleColorsByID: [String: String] = [:]
    private var styleMapPairsByID: [String: [String: String]] = [:]

    func colorHex(forStyleURL styleURL: String?) -> String? {
        guard var styleKey = styleURL?.trimmingCharacters(in: .whitespacesAndNewlines), !styleKey.isEmpty else {
            return nil
        }
        styleKey = styleKey.replacingOccurrences(of: "#", with: "")

        if let mapped = styleColorsByID[styleKey] {
            return mapped
        }

        if let pair = styleMapPairsByID[styleKey] {
            if let normal = pair["normal"]?.replacingOccurrences(of: "#", with: ""),
               let color = styleColorsByID[normal] {
                return color
            }
            if let highlight = pair["highlight"]?.replacingOccurrences(of: "#", with: ""),
               let color = styleColorsByID[highlight] {
                return color
            }
        }

        return nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        textBuffer = ""
        elementStack.append(elementName)

        switch elementName {
        case "Document":
            containers.append(ContainerFrame(kind: .document, name: nil))
        case "Folder":
            containers.append(ContainerFrame(kind: .folder, name: nil))
        case "Placemark":
            currentPlacemark = PlacemarkDraft(
                folderPath: containers.filter { $0.kind == .folder }.compactMap(\.name)
            )
        case "Point":
            isInsidePoint = true
        case "Style":
            if let id = attributeDict["id"] {
                currentStyle = StyleDraft(id: id, colorHex: nil)
            }
        case "StyleMap":
            if let id = attributeDict["id"] {
                currentStyleMap = StyleMapDraft(id: id)
            }
        case "Pair":
            currentStyleMapPair = StyleMapPairDraft()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmedText = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let parentElement = elementStack.dropLast().last

        switch elementName {
        case "name":
            if parentElement == "Placemark" {
                currentPlacemark?.name = trimmedText
            } else if parentElement == "Document" || parentElement == "Folder" {
                if !trimmedText.isEmpty, var container = containers.popLast() {
                    container.name = trimmedText
                    if container.kind == .document, documentTitle == nil {
                        documentTitle = trimmedText
                    }
                    containers.append(container)
                }
            }
        case "description":
            if parentElement == "Placemark" {
                currentPlacemark?.description = trimmedText
            }
        case "styleUrl":
            if parentElement == "Placemark" {
                currentPlacemark?.styleURL = trimmedText
            } else if parentElement == "Pair" {
                currentStyleMapPair?.styleURL = trimmedText
            }
        case "coordinates":
            if isInsidePoint {
                currentPlacemark?.coordinates = trimmedText
            }
        case "color":
            if parentElement == "IconStyle" {
                currentStyle?.colorHex = kmlColorToHex(trimmedText)
            }
        case "key":
            if parentElement == "Pair" {
                currentStyleMapPair?.key = trimmedText
            }
        case "Pair":
            if let pair = currentStyleMapPair,
               let key = pair.key?.nilIfBlank,
               let styleURL = pair.styleURL?.nilIfBlank {
                currentStyleMap?.pairs[key] = styleURL
            }
            currentStyleMapPair = nil
        case "Style":
            if let currentStyle, let colorHex = currentStyle.colorHex {
                styleColorsByID[currentStyle.id] = colorHex
            }
            self.currentStyle = nil
        case "StyleMap":
            if let currentStyleMap {
                styleMapPairsByID[currentStyleMap.id] = currentStyleMap.pairs
            }
            self.currentStyleMap = nil
        case "Placemark":
            if let placemark = currentPlacemark,
               !placemark.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                placemarks.append(placemark)
            }
            currentPlacemark = nil
        case "Point":
            isInsidePoint = false
        case "Folder", "Document":
            _ = containers.popLast()
        default:
            break
        }

        _ = elementStack.popLast()
        textBuffer = ""
    }

    private func kmlColorToHex(_ raw: String) -> String? {
        let sanitized = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard sanitized.count == 8 else { return nil }
        let blueStart = sanitized.index(sanitized.startIndex, offsetBy: 2)
        let greenStart = sanitized.index(sanitized.startIndex, offsetBy: 4)
        let redStart = sanitized.index(sanitized.startIndex, offsetBy: 6)
        let blue = String(sanitized[blueStart..<greenStart])
        let green = String(sanitized[greenStart..<redStart])
        let red = String(sanitized[redStart..<sanitized.endIndex])
        return "\(red)\(green)\(blue)".uppercased()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension UTType {
    static var kml: UTType {
        UTType(filenameExtension: "kml") ?? .xml
    }
}
