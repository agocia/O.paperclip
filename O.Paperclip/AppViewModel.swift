import Combine
import Foundation
import MapKit
import Observation
import SwiftUI

private final class MultiPointRouteAccumulator: @unchecked Sendable {
    var combinedPoints: [CLLocationCoordinate2D] = []
    var totalDistance: Double = 0
}

private final class UnsafeSendableBox<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

private struct SavableItemCandidate {
    let draft: SavedLocationDraft
    let sourceLabel: String
}

struct RouteTimeSummary {
    let label: String
    let distance: CLLocationDistance
    let timeText: String
}

enum RouteEndpointMarkerStyle: String {
    case draftStart
    case draftEnd
    case draftStartEnd
    case activeStart
    case activeEnd
    case activeStartEnd
}

struct RouteEndpointMarker: Identifiable {
    let style: RouteEndpointMarkerStyle
    let title: String
    let coordinate: CLLocationCoordinate2D

    var id: String {
        "\(style.rawValue)-\(coordinate.latitude)-\(coordinate.longitude)"
    }
}

protocol RouteCalculating {
    func calculate(
        request: MKDirections.Request,
        completion: @escaping (MKDirections.Response?, (any Error)?) -> Void
    )
}

struct MKDirectionsRouteCalculator: RouteCalculating {
    func calculate(
        request: MKDirections.Request,
        completion: @escaping (MKDirections.Response?, (any Error)?) -> Void
    ) {
        MKDirections(request: request).calculate(completionHandler: completion)
    }
}

private enum RouteTravelDirection: Int {
    case forward = 1
    case backward = -1

    var multiplier: Double { Double(rawValue) }

    mutating func reverse() {
        self = self == .forward ? .backward : .forward
    }
}

@MainActor
@Observable
final class AppViewModel {
    // MARK: - Dependencies
    let deviceManager: any DeviceControlling
    let locationSearchService: any LocationSearching
    let routeCalculator: any RouteCalculating

    // MARK: - Draft workflow
    var appState: AppState = .selectingA
    var operationMode: OperationMode = .routeAB
    var pendingModeSwitch: OperationMode?

    var pointA: CLLocationCoordinate2D?
    var pointB: CLLocationCoordinate2D?
    var tempCoordinate: CLLocationCoordinate2D?
    var waypoints: [CLLocationCoordinate2D] = []
    var customRoutePolyline: MKPolyline?
    var routes: [MKRoute] = []
    var selectedRouteIndex: Int = 0
    var draftRoutePoints: [CLLocationCoordinate2D] = []
    var draftCumulativeRouteDistances: [Double] = []
    var draftTotalRouteDistance: Double = 0.0

    // MARK: - Active route / simulation
    var activeOperationMode: OperationMode = .routeAB
    var activeRoutePolyline: MKPolyline?
    var currentPosition: CLLocationCoordinate2D?
    var currentRoutePoints: [CLLocationCoordinate2D] = []
    var cumulativeRouteDistances: [Double] = []
    var traveledDistance: Double = 0.0
    var totalRouteDistance: Double = 0.0
    private var routeTravelDirection: RouteTravelDirection = .forward
    var activeIsClosedLoop: Bool = false
    var activeIsEndlessLoop: Bool = false
    var isActiveSimulationRunning: Bool = false
    var isJoystickSessionActive: Bool = false
    var shouldResumeActiveAfterReconnect: Bool = false
    var isShowingRouteReplacementConfirmation: Bool = false
    private(set) var activeJoystickDirections: Set<JoystickDirection> = []

    // MARK: - Settings
    var speed: Double = AppConstants.Simulation.defaultSpeed
    var isEndlessLoop: Bool = false
    var isClosedLoop: Bool = false

    // MARK: - Fixed routes
    var importedGPXRoutes: [ImportedGPXRoute] = ImportedGPXRouteStore.loadRoutes()
    var selectedImportedGPXRouteID: String?
    var pendingImportedGPXRoutes: [ImportedGPXRoute] = []
    var pendingImportedGPXRouteTitles: [String: String] = [:]
    var isShowingImportedGPXRouteNamingSheet: Bool = false
    var gpxImportError: String?

    // MARK: - Saved locations
    var savedLocations: [SavedLocationItem] = SavedLocationStore.loadItems()
    var isShowingSaveLocationSheet: Bool = false
    var pendingSavedLocationTitle: String = ""
    var savedLocationError: String?
    var savedLocationRenamingTarget: SavedLocationItem?
    var pendingSavedLocationPreview: CurrentSavableItemPreview?

    // MARK: - Location input
    var placeKeyword: String = ""
    var placeResults: [MKMapItem] = []
    var coordinateInputText: String = ""
    var locationInputError: String?

    // MARK: - Map camera
    var requestCameraPosition: ((MapCameraPosition) -> Void)?
    var requestCameraCenter: ((CLLocationCoordinate2D) -> Void)?

    // MARK: - Private
    @ObservationIgnored private var moveTimer: Timer?
    @ObservationIgnored private var joystickTimer: Timer?
    @ObservationIgnored private var pinnedKeepAliveTimer: Timer?
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var pendingSavedLocationDraft: SavedLocationDraft?
    @ObservationIgnored private var suppressNextOperationModeReset = false
    private(set) var lastSentPosition: CLLocationCoordinate2D?
    private(set) var lastSentAt: Date?
    var dependencyVersion: Int = 0

    let maximumSpeed = AppConstants.Simulation.maximumSpeed

    var selectedRoute: MKRoute? {
        routes.indices.contains(selectedRouteIndex) ? routes[selectedRouteIndex] : routes.first
    }

    var selectedImportedGPXRoute: ImportedGPXRoute? {
        importedGPXRoutes.first { $0.id == selectedImportedGPXRouteID }
    }

    var pinnedCoordinate: CLLocationCoordinate2D? {
        currentPosition ?? lastSentPosition
    }

    var hasActiveRouteSnapshot: Bool {
        activeRoutePolyline != nil
            || ((activeOperationMode == .fixedPoint || activeOperationMode == .joystick) && currentPosition != nil)
            || (isJoystickSessionActive && currentPosition != nil)
    }

    var hasDraftPreview: Bool {
        !routes.isEmpty
            || (customRoutePolyline?.pointCount ?? 0) > 1
            || draftRoutePoints.count > 1
    }

    var hasDraftEdits: Bool {
        pointA != nil
            || pointB != nil
            || tempCoordinate != nil
            || !waypoints.isEmpty
            || hasDraftPreview
    }

    var hasReadyDraft: Bool {
        guard appState == .readyToMove else { return false }
        switch operationMode {
        case .fixedPoint, .joystick:
            return pointA != nil
        case .routeAB, .multiPoint, .fixedRoute:
            return draftRoutePoints.count > 1
        }
    }

    var shouldUseDraftControls: Bool {
        !hasActiveRouteSnapshot || hasDraftEdits
    }

    var shouldShowResetButton: Bool {
        hasDraftEdits
    }

    var resetButtonTitle: String {
        if hasActiveRouteSnapshot {
            return "清除草稿路線"
        }
        switch operationMode {
        case .fixedPoint:
            return "清除定位點"
        case .joystick:
            return "清除搖桿起點"
        case .fixedRoute:
            return "清除固定路線"
        case .routeAB, .multiPoint:
            return "清除目前路線"
        }
    }

    var activityNotice: String? {
        if hasActiveRouteSnapshot && hasDraftEdits {
            return "目前藍線持續運作中，正在編輯黃線草稿。"
        }
        if activeOperationMode == .joystick && isJoystickSessionActive && !activeJoystickDirections.isEmpty {
            return "搖桿同步中，放開方向鍵後會停在目前位置。"
        }
        if activeOperationMode == .joystick && isJoystickSessionActive {
            return "搖桿已啟用，按方向鍵、WASD 或右下角方向鈕即可移動。"
        }
        if hasActiveRouteSnapshot && !isActiveSimulationRunning {
            return "目前藍線已停止移動，但定位仍固定在裝置上。"
        }
        return nil
    }

    var canSaveCurrentSelection: Bool {
        currentSaveCandidate() != nil
    }

    var currentSavableItemPreview: CurrentSavableItemPreview {
        guard let candidate = currentSaveCandidate() else {
            return .unavailable
        }
        return preview(for: candidate)
    }

    var travelTimeSummary: RouteTimeSummary? {
        let speedMetersPerSecond = speed * (1000.0 / 3600.0)
        guard speedMetersPerSecond > 0 else { return nil }

        if let remainingDistance = activeRemainingRouteDistance {
            return RouteTimeSummary(
                label: "剩餘",
                distance: remainingDistance,
                timeText: Self.formatDuration(remainingDistance / speedMetersPerSecond)
            )
        }

        if let draftDistance = draftEstimatedRouteDistance {
            return RouteTimeSummary(
                label: "單趟",
                distance: draftDistance,
                timeText: Self.formatDuration(draftDistance / speedMetersPerSecond)
            )
        }

        return nil
    }

    var estimatedTime: String {
        travelTimeSummary?.timeText ?? "--"
    }

    var draftRouteEndpointMarkers: [RouteEndpointMarker] {
        guard operationMode == .multiPoint || operationMode == .fixedRoute else { return [] }
        return endpointMarkers(
            for: draftRoutePoints,
            isClosedLoop: isClosedLoop,
            startStyle: .draftStart,
            endStyle: .draftEnd,
            startEndStyle: .draftStartEnd,
            labelPrefix: "草稿"
        )
    }

    var activeRouteEndpointMarkers: [RouteEndpointMarker] {
        guard activeOperationMode == .routeAB || activeOperationMode == .multiPoint || activeOperationMode == .fixedRoute else {
            return []
        }
        return endpointMarkers(
            for: currentRoutePoints,
            isClosedLoop: activeIsClosedLoop,
            startStyle: .activeStart,
            endStyle: .activeEnd,
            startEndStyle: .activeStartEnd,
            labelPrefix: ""
        )
    }

    var buttonTitle: String {
        if !deviceManager.isConnected && (hasReadyDraft || hasActiveRouteSnapshot) {
            return "請先連線裝置"
        }
        if shouldUseDraftControls {
            if hasActiveRouteSnapshot && hasReadyDraft {
                return "開始新路線"
            }
            return draftButtonTitle
        }
        return activeButtonTitle
    }

    var isMainActionDisabled: Bool {
        if shouldUseDraftControls {
            return draftActionDisabled
        }
        return activeActionDisabled
    }

    var isMainActionDestructive: Bool {
        !shouldUseDraftControls && (isActiveSimulationRunning || activeOperationMode == .joystick)
    }

    private var draftButtonTitle: String {
        if operationMode == .fixedPoint {
            switch appState {
            case .selectingA, .confirmingA: return "選擇定位點"
            case .readyToMove: return "開始定位"
            default: break
            }
        }
        if operationMode == .joystick {
            switch appState {
            case .selectingA, .confirmingA: return "選擇起點"
            case .readyToMove: return hasActiveRouteSnapshot ? "開始新路線" : "開始搖桿"
            default: break
            }
        }
        if operationMode == .fixedRoute {
            switch appState {
            case .selectingA: return "匯入或選擇路線"
            case .readyToMove: return hasActiveRouteSnapshot ? "開始新路線" : "開始同步移動"
            default: break
            }
        }
        if operationMode == .multiPoint && appState == .selectingA {
            return waypoints.count >= 2 ? "完成選點並計算路線" : "請先選至少 2 點"
        }
        switch appState {
        case .selectingA, .selectingB: return "等待選擇..."
        case .confirmingA: return "確認起點 A"
        case .confirmingB: return "確認終點 B"
        case .calculatingRoute: return "計算中..."
        case .routeSelection: return "確認使用此路線"
        case .readyToMove: return hasActiveRouteSnapshot ? "開始新路線" : "開始同步移動"
        case .moving: return "停止移動"
        }
    }

    private var activeButtonTitle: String {
        if activeOperationMode == .fixedPoint {
            return isActiveSimulationRunning ? "停止定位(回歸裝置定位）" : "開始定位"
        }
        if activeOperationMode == .joystick {
            return "結束搖桿"
        }
        return isActiveSimulationRunning ? "停止移動" : "開始同步移動"
    }

    private var draftActionDisabled: Bool {
        if appState == .calculatingRoute {
            return true
        }
        if appState == .selectingB {
            return true
        }
        if operationMode == .multiPoint && appState == .selectingA {
            return waypoints.count < 2
        }
        if (operationMode == .fixedPoint || operationMode == .joystick)
            && (appState == .selectingA || appState == .confirmingA) {
            return pointA == nil && tempCoordinate == nil
        }
        if appState == .selectingA {
            return true
        }
        if appState == .readyToMove {
            return !deviceManager.isConnected
        }
        return false
    }

    private var activeActionDisabled: Bool {
        !deviceManager.isConnected || !hasActiveRouteSnapshot
    }

    init(
        deviceManager: any DeviceControlling,
        locationSearchService: any LocationSearching,
        routeCalculator: any RouteCalculating = MKDirectionsRouteCalculator()
    ) {
        self.deviceManager = deviceManager
        self.locationSearchService = locationSearchService
        self.routeCalculator = routeCalculator

        deviceManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.dependencyVersion += 1
            }
            .store(in: &cancellables)

        locationSearchService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.dependencyVersion += 1
            }
            .store(in: &cancellables)
    }

    var draftEstimatedRouteDistance: CLLocationDistance? {
        let distance: Double
        if let route = selectedRoute {
            distance = route.distance
        } else if draftTotalRouteDistance > 0 {
            distance = draftTotalRouteDistance
        } else {
            return nil
        }
        return distance > 0 ? distance : nil
    }

    var activeRemainingRouteDistance: CLLocationDistance? {
        guard hasActiveRouteSnapshot,
              activeOperationMode != .fixedPoint,
              activeOperationMode != .joystick,
              currentRoutePoints.count > 1,
              totalRouteDistance > 0 else {
            return nil
        }

        let currentDistance = clampedRouteDistance(traveledDistance)

        if activeOperationMode == .multiPoint && activeIsClosedLoop {
            let remaining = totalRouteDistance - currentDistance
            return remaining <= 0 ? totalRouteDistance : remaining
        }

        if routeTravelDirection == .backward {
            return currentDistance
        }

        return max(totalRouteDistance - currentDistance, 0)
    }

    func consumeProgrammaticModeResetSuppression() -> Bool {
        let shouldSuppress = suppressNextOperationModeReset
        suppressNextOperationModeReset = false
        return shouldSuppress
    }

    func setOperationModeProgrammatically(_ mode: OperationMode) {
        guard operationMode != mode else { return }
        suppressNextOperationModeReset = true
        operationMode = mode
    }

    // MARK: - Map interaction

    func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        if hasActiveRouteSnapshot && !hasDraftEdits && operationMode != .fixedRoute {
            appState = .selectingA
        }
        if operationMode == .fixedRoute {
            return
        }
        if operationMode == .multiPoint {
            guard appState == .selectingA else { return }
            waypoints.append(coordinate)
            return
        }
        if appState == .selectingA || appState == .confirmingA {
            tempCoordinate = coordinate
            appState = .confirmingA
        } else if appState == .selectingB || appState == .confirmingB {
            tempCoordinate = coordinate
            appState = .confirmingB
        }
    }

    func insertPoint(_ coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            locationInputError = "座標格式錯誤"
            return
        }
        locationInputError = nil
        placeResults = []
        locationSearchService.clearSuggestions()
        if hasActiveRouteSnapshot && !hasDraftEdits && operationMode != .fixedRoute {
            appState = .selectingA
        }
        requestCameraPosition?(.region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: AppConstants.Map.defaultSpanDelta,
                    longitudeDelta: AppConstants.Map.defaultSpanDelta
                )
            )
        ))

        if operationMode == .multiPoint {
            if appState == .selectingA { waypoints.append(coordinate) }
            return
        }

        if operationMode == .fixedRoute {
            return
        }

        if operationMode == .fixedPoint || operationMode == .joystick {
            pointA = coordinate
            tempCoordinate = nil
            appState = .readyToMove
            return
        }

        if pointA == nil || appState == .selectingA || appState == .confirmingA {
            pointA = coordinate
            tempCoordinate = nil
            appState = .selectingB
        } else {
            pointB = coordinate
            tempCoordinate = nil
            appState = .calculatingRoute
            calculateRoutes()
        }
    }

    func insertCoordinateFromInput() {
        let raw = coordinateInputText
            .replacingOccurrences(of: "，", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            locationInputError = "格式錯誤，請輸入「緯度,經度」"
            return
        }
        let lat = Double(String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines))
        let lon = Double(String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines))
        guard let lat, let lon else {
            locationInputError = "請輸入有效數字座標"
            return
        }
        insertPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    func searchPlaces(currentRegion: MKCoordinateRegion?) {
        let q = placeKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            placeResults = []
            locationSearchService.clearSuggestions()
            return
        }
        Task {
            do {
                let results = try await locationSearchService.search(for: q, region: currentRegion)
                placeResults = results
                locationInputError = results.isEmpty ? "找不到符合的地點" : nil
            } catch {
                placeResults = []
                locationInputError = "搜尋失敗，請重試"
            }
        }
    }

    func searchPlaces(using completion: MKLocalSearchCompletion, currentRegion: MKCoordinateRegion?) {
        placeKeyword = completion.title
        locationSearchService.clearSuggestions()
        Task {
            do {
                let results = try await locationSearchService.search(for: completion, region: currentRegion)
                placeResults = results
                locationInputError = results.isEmpty ? "找不到符合的地點" : nil
            } catch {
                placeResults = []
                locationInputError = "搜尋失敗，請重試"
            }
        }
    }

    // MARK: - GPX routes

    func prepareImportedGPXRoutes(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        resetImportedGPXRouteSession()

        do {
            pendingImportedGPXRoutes = try ImportedGPXRouteStore.previewRoutes(from: urls)
            pendingImportedGPXRouteTitles = [String: String](
                uniqueKeysWithValues: pendingImportedGPXRoutes.map { ($0.id, $0.title) }
            )
            isShowingImportedGPXRouteNamingSheet = true
            gpxImportError = nil
        } catch let error as GPXImportError {
            gpxImportError = error.localizedDescription
        } catch {
            gpxImportError = error.localizedDescription
        }
    }

    func finalizeImportedGPXRoutes() {
        do {
            let renamedRoutes = pendingImportedGPXRoutes.map { route in
                route.renamed(to: pendingImportedGPXRouteTitles[route.id] ?? route.title)
            }
            let persistedRoutes = try ImportedGPXRouteStore.persistImportedRoutes(renamedRoutes)
            commitImportedGPXRoutes(persistedRoutes)
            gpxImportError = nil
            resetImportedGPXRouteSession()
        } catch let error as GPXImportError {
            gpxImportError = error.localizedDescription
        } catch {
            gpxImportError = error.localizedDescription
        }
    }

    func cancelImportedGPXRoutes() {
        resetImportedGPXRouteSession()
    }

    func useImportedGPXRoute(_ route: ImportedGPXRoute) {
        let normalized = normalizeRoutePoints(route.points)
        guard normalized.count > 1 else {
            locationInputError = "固定路線資料異常，請重新匯入。"
            return
        }

        pointA = nil
        pointB = nil
        tempCoordinate = nil
        waypoints = []
        routes = []
        selectedRouteIndex = 0
        customRoutePolyline = nil
        selectedImportedGPXRouteID = route.id
        draftRoutePoints = normalized
        draftCumulativeRouteDistances = RouteMotionEngine.cumulativeDistances(for: normalized)
        draftTotalRouteDistance = route.totalDistance > 0
            ? route.totalDistance
            : (draftCumulativeRouteDistances.last ?? 0)
        var coords = normalized
        customRoutePolyline = MKPolyline(coordinates: &coords, count: coords.count)
        locationInputError = nil
        appState = .readyToMove
    }

    func removeImportedGPXRoute(_ route: ImportedGPXRoute) {
        ImportedGPXRouteStore.deleteStoredRoute(route)
        importedGPXRoutes.removeAll { $0.id == route.id }

        if selectedImportedGPXRouteID == route.id {
            selectedImportedGPXRouteID = nil
            clearDraftGeometry()
            if !hasActiveRouteSnapshot {
                appState = .selectingA
            }
        }

        persistImportedGPXRouteSettings()
    }

    func persistImportedGPXRouteSettings() {
        let paths = importedGPXRoutes.compactMap(\.sourceFilePath)
        let titles = importedGPXRoutes.reduce(into: [String: String]()) { partialResult, route in
            guard let path = route.sourceFilePath else { return }
            partialResult[path] = route.title
        }
        ImportedGPXRouteStore.savePaths(paths)
        ImportedGPXRouteStore.saveTitleOverrides(titles)
    }

    func resetImportedGPXRouteSession() {
        pendingImportedGPXRoutes = []
        pendingImportedGPXRouteTitles = [:]
        isShowingImportedGPXRouteNamingSheet = false
    }

    private func commitImportedGPXRoutes(_ routes: [ImportedGPXRoute]) {
        var routesByPath: [String: ImportedGPXRoute] = Dictionary(
            uniqueKeysWithValues: importedGPXRoutes.compactMap { route in
                guard let path = route.sourceFilePath else { return nil }
                return (path, route)
            }
        )

        for route in routes {
            if let path = route.sourceFilePath {
                routesByPath[path] = route
            }
        }

        importedGPXRoutes = routesByPath.values.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        persistImportedGPXRouteSettings()
    }

    // MARK: - Saved locations

    func prepareSaveCurrentSelection() {
        guard let candidate = currentSaveCandidate() else {
            savedLocationError = "目前沒有可儲存的位置或路線。"
            return
        }
        pendingSavedLocationDraft = candidate.draft
        pendingSavedLocationPreview = preview(for: candidate)
        pendingSavedLocationTitle = candidate.draft.title
        savedLocationError = nil
        isShowingSaveLocationSheet = true
    }

    func confirmSaveCurrentSelection() {
        guard let draft = pendingSavedLocationDraft else {
            savedLocationError = "目前沒有可儲存的位置或路線。"
            return
        }

        let title = pendingSavedLocationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            savedLocationError = "請先輸入名稱。"
            return
        }

        do {
            let saved = try SavedLocationStore.persist(
                SavedLocationDraft(
                    title: title,
                    kind: draft.kind,
                    coordinates: draft.coordinates,
                    totalDistance: draft.totalDistance,
                    createdAt: draft.createdAt,
                    sourceMode: draft.sourceMode
                )
            )
            savedLocations.removeAll { $0.id == saved.id }
            savedLocations.insert(saved, at: 0)
            pendingSavedLocationDraft = nil
            pendingSavedLocationPreview = nil
            pendingSavedLocationTitle = ""
            savedLocationError = nil
            isShowingSaveLocationSheet = false
        } catch {
            savedLocationError = error.localizedDescription
        }
    }

    func cancelSaveCurrentSelection() {
        pendingSavedLocationDraft = nil
        pendingSavedLocationPreview = nil
        pendingSavedLocationTitle = ""
        savedLocationError = nil
        isShowingSaveLocationSheet = false
    }

    func beginRenamingSavedLocation(_ item: SavedLocationItem) {
        savedLocationRenamingTarget = item
        pendingSavedLocationTitle = item.title
        savedLocationError = nil
    }

    func confirmRenameSavedLocation() {
        guard let item = savedLocationRenamingTarget else { return }
        let title = pendingSavedLocationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            savedLocationError = "請先輸入名稱。"
            return
        }

        do {
            let renamed = try SavedLocationStore.rename(item, to: title)
            if let index = savedLocations.firstIndex(where: { $0.id == renamed.id }) {
                savedLocations[index] = renamed
            }
            savedLocationRenamingTarget = nil
            pendingSavedLocationTitle = ""
            savedLocationError = nil
        } catch {
            savedLocationError = error.localizedDescription
        }
    }

    func cancelRenameSavedLocation() {
        savedLocationRenamingTarget = nil
        pendingSavedLocationTitle = ""
        savedLocationError = nil
    }

    func removeSavedLocation(_ item: SavedLocationItem) {
        SavedLocationStore.deleteStoredItem(item)
        savedLocations.removeAll { $0.id == item.id }
        if savedLocationRenamingTarget?.id == item.id {
            savedLocationRenamingTarget = nil
            pendingSavedLocationTitle = ""
        }
    }

    func applySavedLocation(_ item: SavedLocationItem) {
        savedLocationError = nil

        switch item.kind {
        case .point:
            applySavedPoint(item)
        case .route:
            applySavedRoute(item, mode: targetOperationMode(for: item))
        case .loop:
            applySavedRoute(item, mode: .multiPoint)
        }
    }

    private func applySavedPoint(_ item: SavedLocationItem) {
        guard let coordinate = item.coordinates.first else {
            savedLocationError = "這筆收藏的點位資料異常。"
            return
        }

        setOperationModeProgrammatically(.fixedPoint)
        resetDraftStateForSavedLocation()
        pointA = coordinate
        isClosedLoop = false
        isEndlessLoop = false
        appState = .readyToMove
    }

    private func applySavedRoute(_ item: SavedLocationItem, mode: OperationMode) {
        let normalized = normalizeRoutePoints(item.coordinates)
        guard normalized.count > 1 else {
            savedLocationError = "這筆收藏的路線資料異常。"
            return
        }

        setOperationModeProgrammatically(mode)
        resetDraftStateForSavedLocation()

        draftRoutePoints = normalized
        draftCumulativeRouteDistances = RouteMotionEngine.cumulativeDistances(for: normalized)
        draftTotalRouteDistance = item.totalDistance > 0 ? item.totalDistance : (draftCumulativeRouteDistances.last ?? 0)
        var coords = normalized
        customRoutePolyline = MKPolyline(coordinates: &coords, count: coords.count)

        switch mode {
        case .routeAB:
            pointA = normalized.first
            pointB = normalized.last
            isClosedLoop = false
        case .multiPoint, .fixedRoute:
            pointA = nil
            pointB = nil
            isClosedLoop = item.kind == .loop
        case .fixedPoint, .joystick:
            pointA = nil
            pointB = nil
            isClosedLoop = false
        }

        isEndlessLoop = false
        appState = .readyToMove
    }

    private func targetOperationMode(for item: SavedLocationItem) -> OperationMode {
        switch item.kind {
        case .point:
            return .fixedPoint
        case .route:
            if item.sourceMode == OperationMode.routeAB.rawValue {
                return .routeAB
            }
            return .multiPoint
        case .loop:
            return .multiPoint
        }
    }

    private func resetDraftStateForSavedLocation() {
        pointA = nil
        pointB = nil
        tempCoordinate = nil
        waypoints = []
        routes = []
        selectedRouteIndex = 0
        selectedImportedGPXRouteID = nil
        customRoutePolyline = nil
        draftRoutePoints = []
        draftCumulativeRouteDistances = []
        draftTotalRouteDistance = 0
        locationInputError = nil
    }

    private func currentSaveCandidate() -> SavableItemCandidate? {
        if hasActiveRouteSnapshot {
            guard let draft = makeSavedLocationDraft(
                modeLabel: activeOperationMode.rawValue,
                coordinateSource: activeCoordinatesForSaving(),
                totalDistance: totalRouteDistance,
                isClosedLoop: activeIsClosedLoop
            ) else {
                return nil
            }
            return SavableItemCandidate(
                draft: draft,
                sourceLabel: "活動中的內容"
            )
        }
        if hasReadyDraft {
            guard let draft = makeSavedLocationDraft(
                modeLabel: operationMode.rawValue,
                coordinateSource: draftCoordinatesForSaving(),
                totalDistance: draftTotalRouteDistance,
                isClosedLoop: isClosedLoop
            ) else {
                return nil
            }
            return SavableItemCandidate(
                draft: draft,
                sourceLabel: "已完成草稿"
            )
        }
        return nil
    }

    private func preview(for candidate: SavableItemCandidate) -> CurrentSavableItemPreview {
        CurrentSavableItemPreview(
            kind: candidate.draft.kind,
            sourceLabel: candidate.sourceLabel,
            suggestedTitle: candidate.draft.title,
            summaryText: saveSummaryText(
                kind: candidate.draft.kind,
                coordinates: candidate.draft.coordinates,
                totalDistance: candidate.draft.totalDistance
            ),
            coordinates: candidate.draft.coordinates,
            isAvailable: true
        )
    }

    private func makeSavedLocationDraft(
        modeLabel: String,
        coordinateSource: [CLLocationCoordinate2D],
        totalDistance: Double,
        isClosedLoop: Bool
    ) -> SavedLocationDraft? {
        let createdAt = Date()
        let coordinates = normalizeRoutePoints(coordinateSource)
        guard let first = coordinates.first else { return nil }
        let formsLoop: Bool
        if let last = coordinates.last {
            formsLoop = abs(first.latitude - last.latitude) < 0.0000001
                && abs(first.longitude - last.longitude) < 0.0000001
        } else {
            formsLoop = false
        }

        let kind: SavedLocationKind
        if coordinates.count == 1 {
            kind = .point
        } else if isClosedLoop || formsLoop {
            kind = .loop
        } else {
            kind = .route
        }

        let title = suggestedSavedLocationTitle(
            kind: kind,
            coordinate: first,
            createdAt: createdAt
        )
        return SavedLocationDraft(
            title: title,
            kind: kind,
            coordinates: coordinates,
            totalDistance: totalDistance,
            createdAt: createdAt,
            sourceMode: modeLabel
        )
    }

    private func activeCoordinatesForSaving() -> [CLLocationCoordinate2D] {
        if activeOperationMode == .fixedPoint || activeOperationMode == .joystick {
            return currentPosition.map { [$0] } ?? []
        }
        return currentRoutePoints
    }

    private func draftCoordinatesForSaving() -> [CLLocationCoordinate2D] {
        if operationMode == .fixedPoint || operationMode == .joystick {
            return pointA.map { [$0] } ?? []
        }
        return draftRoutePoints
    }

    private func suggestedSavedLocationTitle(
        kind: SavedLocationKind,
        coordinate: CLLocationCoordinate2D,
        createdAt: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "MM/dd HH:mm"
        let prefix: String
        switch kind {
        case .point:
            prefix = "定點"
        case .route:
            prefix = "線路"
        case .loop:
            prefix = "迴路"
        }
        return "\(prefix) \(formatter.string(from: createdAt)) (\(String(format: "%.3f", coordinate.latitude)), \(String(format: "%.3f", coordinate.longitude)))"
    }

    private func saveSummaryText(
        kind: SavedLocationKind,
        coordinates: [CLLocationCoordinate2D],
        totalDistance: CLLocationDistance
    ) -> String {
        switch kind {
        case .point:
            guard let coordinate = coordinates.first else { return "1 個點位" }
            return String(
                format: "座標 %.5f, %.5f",
                coordinate.latitude,
                coordinate.longitude
            )
        case .route, .loop:
            return "\(coordinates.count) 點，\(String(format: "%.2f", totalDistance / 1000)) km"
        }
    }

    // MARK: - Main action

    func handleMainAction() {
        if shouldUseDraftControls {
            handleDraftMainAction()
            return
        }
        handleActiveMainAction()
    }

    func confirmRouteReplacement() {
        isShowingRouteReplacementConfirmation = false
        guard deviceManager.isConnected else { return }
        prepareForRouteReplacement()
        activateDraftForActiveSession()
        if activeOperationMode == .joystick {
            beginJoystickSession()
        } else {
            startSimulation()
        }
    }

    func cancelRouteReplacement() {
        isShowingRouteReplacementConfirmation = false
    }

    func resetAll() {
        if hasActiveRouteSnapshot {
            clearDraftWorkflow()
            return
        }
        clearDraftWorkflow()
        stopSimulation(keepPinned: false)
        clearSimulatedLocationAsync()
        clearActiveSnapshot(clearPosition: true)
    }

    private func handleDraftMainAction() {
        if operationMode == .multiPoint && appState == .selectingA {
            calculateMultiPointRoute()
            return
        }

        switch appState {
        case .confirmingA, .confirmingB:
            confirmTempCoordinate()
        case .routeSelection:
            extractRoutePoints()
        case .readyToMove:
            guard deviceManager.isConnected else { return }
            if hasActiveRouteSnapshot {
                isShowingRouteReplacementConfirmation = true
            } else {
                activateDraftForActiveSession()
                if activeOperationMode == .joystick {
                    beginJoystickSession()
                } else {
                    startSimulation()
                }
            }
        case .moving:
            break
        default:
            break
        }
    }

    private func handleActiveMainAction() {
        guard hasActiveRouteSnapshot else { return }
        guard deviceManager.isConnected else { return }

        if activeOperationMode == .joystick {
            endJoystickSession()
            return
        }

        if activeOperationMode == .fixedPoint {
            if isActiveSimulationRunning {
                stopSimulation(keepPinned: false)
                clearSimulatedLocationAsync()
                clearActiveSnapshot(clearPosition: true)
            } else {
                startSimulation()
            }
            return
        }

        if isActiveSimulationRunning {
            stopSimulation(keepPinned: true)
        } else {
            startSimulation()
        }
    }

    private func activateDraftForActiveSession() {
        stopJoystickMovement()
        activeOperationMode = operationMode
        activeIsClosedLoop = isClosedLoop
        activeIsEndlessLoop = isEndlessLoop
        shouldResumeActiveAfterReconnect = false

        switch operationMode {
        case .fixedPoint, .joystick:
            guard let fixed = pointA else { return }
            currentPosition = fixed
            currentRoutePoints = []
            cumulativeRouteDistances = []
            traveledDistance = 0
            totalRouteDistance = 0
            routeTravelDirection = .forward
            activeRoutePolyline = nil
            isJoystickSessionActive = operationMode == .joystick
        case .routeAB, .multiPoint, .fixedRoute:
            guard draftRoutePoints.count > 1 else { return }
            currentRoutePoints = draftRoutePoints
            cumulativeRouteDistances = draftCumulativeRouteDistances
            traveledDistance = 0
            totalRouteDistance = draftTotalRouteDistance
            routeTravelDirection = .forward
            currentPosition = draftRoutePoints.first
            activeRoutePolyline = makeDraftPolyline()
            isJoystickSessionActive = false
        }

        clearDraftWorkflow()
        appState = .readyToMove
    }

    // MARK: - Coordinate helpers

    func confirmTempCoordinate() {
        guard let temp = tempCoordinate else { return }
        switch appState {
        case .confirmingA:
            pointA = temp
            tempCoordinate = nil
            if operationMode == .fixedPoint || operationMode == .joystick {
                appState = .readyToMove
            } else {
                appState = .selectingB
            }
        case .confirmingB:
            pointB = temp
            tempCoordinate = nil
            appState = .calculatingRoute
            calculateRoutes()
        default:
            break
        }
    }

    func cancelTempCoordinate() {
        tempCoordinate = nil
        switch appState {
        case .confirmingA: appState = .selectingA
        case .confirmingB: appState = .selectingB
        default: break
        }
    }

    // MARK: - Route calculation

    func calculateRoutes() {
        guard operationMode == .routeAB, let a = pointA, let b = pointB else { return }
        clearDraftGeometry()
        locationInputError = nil
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        request.transportType = .walking
        request.requestsAlternateRoutes = true

        routeCalculator.calculate(request: request) { response, error in
            let routesBox = UnsafeSendableBox(response?.routes)
            let errorBox = UnsafeSendableBox(error)
            MainActor.assumeIsolated {
                if let routes = routesBox.value {
                    self.routes = routes
                    self.customRoutePolyline = nil
                    self.selectedRouteIndex = 0
                    self.locationInputError = nil
                    self.appState = .routeSelection
                } else {
                    self.clearDraftGeometry()
                    self.locationInputError = self.routeABFailureMessage(for: errorBox.value)
                    self.appState = .selectingB
                }
            }
        }
    }

    func extractRoutePoints() {
        guard operationMode == .routeAB, let route = selectedRoute else { return }
        let pointCount = route.polyline.pointCount
        guard pointCount > 1 else {
            clearDraftGeometry()
            appState = .routeSelection
            locationInputError = "取得的路線點不足，請改選其他路線"
            return
        }
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        draftRoutePoints = normalizeRoutePoints(coords)
        guard draftRoutePoints.count > 1 else {
            clearDraftGeometry()
            appState = .routeSelection
            locationInputError = "路線資料異常，請改選其他路線"
            return
        }
        draftCumulativeRouteDistances = RouteMotionEngine.cumulativeDistances(for: draftRoutePoints)
        draftTotalRouteDistance = route.distance
        appState = .readyToMove
    }

    func calculateMultiPointRoute() {
        guard operationMode == .multiPoint, waypoints.count >= 2 else { return }
        appState = .calculatingRoute
        routes = []
        selectedRouteIndex = 0
        clearDraftGeometry()
        locationInputError = nil

        let routeWaypoints: [CLLocationCoordinate2D]
        if isClosedLoop, let first = waypoints.first {
            routeWaypoints = waypoints + [first]
        } else {
            routeWaypoints = waypoints
        }

        let accumulator = MultiPointRouteAccumulator()

        func buildSegment(_ index: Int) {
            if index >= routeWaypoints.count - 1 {
                let normalized = self.normalizeRoutePoints(accumulator.combinedPoints)
                guard normalized.count > 1 else {
                    self.clearDraftGeometry()
                    self.locationInputError = "多點路線無效，請重新選點"
                    self.appState = .selectingA
                    return
                }
                self.draftRoutePoints = normalized
                self.draftCumulativeRouteDistances = RouteMotionEngine.cumulativeDistances(for: normalized)
                self.draftTotalRouteDistance = accumulator.totalDistance
                var coords = normalized
                self.customRoutePolyline = MKPolyline(coordinates: &coords, count: coords.count)
                self.appState = .readyToMove
                return
            }

            let request = MKDirections.Request()
            let from = routeWaypoints[index]
            let to = routeWaypoints[index + 1]
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
            request.transportType = .walking
            request.requestsAlternateRoutes = false

            self.routeCalculator.calculate(request: request) { [weak self] response, error in
                let routeBox = UnsafeSendableBox(response?.routes.first)
                let errorBox = UnsafeSendableBox(error)
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard let route = routeBox.value else {
                        self.clearDraftGeometry()
                        self.locationInputError = self.multiPointFailureMessage(
                            segmentIndex: index,
                            error: errorBox.value
                        )
                        self.appState = .selectingA
                        return
                    }
                    accumulator.totalDistance += route.distance
                    let pointCount = route.polyline.pointCount
                    guard pointCount > 1 else {
                        self.locationInputError = "某一段路線點不足，請調整選點"
                        self.appState = .selectingA
                        return
                    }
                    var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
                    route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
                    let valid = self.normalizeRoutePoints(coords)
                    guard valid.count > 1 else {
                        self.locationInputError = "某一段路線資料異常，請調整選點"
                        self.appState = .selectingA
                        return
                    }
                    if index == 0 {
                        accumulator.combinedPoints.append(contentsOf: valid)
                    } else {
                        accumulator.combinedPoints.append(contentsOf: valid.dropFirst())
                    }
                    buildSegment(index + 1)
                }
            }
        }

        buildSegment(0)
    }

    // MARK: - Simulation

    func startSimulation() {
        stopPinnedLocationKeepAlive()
        stopJoystickMovement()
        isActiveSimulationRunning = true
        shouldResumeActiveAfterReconnect = false
        appState = .moving
        resetSendTracking()

        if activeOperationMode == .fixedPoint {
            guard let fixed = currentPosition else {
                isActiveSimulationRunning = false
                appState = .readyToMove
                return
            }
            startStreamingAndSend(fixed)
            return
        }

        guard currentRoutePoints.count > 1 else {
            isActiveSimulationRunning = false
            appState = .readyToMove
            return
        }

        if currentPosition == nil, let first = currentRoutePoints.first {
            currentPosition = first
        }
        traveledDistance = clampedRouteDistance(traveledDistance)
        normalizeRouteDirectionForCurrentState()
        if let initial = currentPosition ?? currentRoutePoints.first {
            startStreamingAndSend(initial)
        }

        let timerInterval = AppConstants.Simulation.timerInterval
        let timer = Timer(timeInterval: timerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let speedMetersPerSecond = self.speed * (1000.0 / 3600.0)
                let distanceDelta = speedMetersPerSecond * timerInterval
                let progress = self.advanceRouteProgress(by: distanceDelta)

                if progress.shouldStop {
                    self.stopSimulation(keepPinned: true)
                    if let terminalPosition = self.positionForCurrentEndpoint() {
                        self.currentPosition = terminalPosition
                        self.sendCoordinateAsync(terminalPosition)
                    }
                    return
                }

                if let newPos = RouteMotionEngine.coordinate(
                    at: progress.targetDistance,
                    in: self.currentRoutePoints,
                    distances: self.cumulativeRouteDistances
                ) {
                    self.currentPosition = newPos
                    if self.shouldSendCoordinateUpdate(newPos) {
                        self.sendCoordinateAsync(newPos)
                    }
                }
            }
        }
        moveTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopSimulation(keepPinned: Bool = true) {
        moveTimer?.invalidate()
        moveTimer = nil
        isActiveSimulationRunning = false
        resetSendTracking()
        if keepPinned, let current = currentPosition {
            startStreamingAndSend(current)
            startPinnedLocationKeepAlive()
        } else {
            stopPinnedLocationKeepAlive()
            deviceManager.stopContinuousLocationStream()
        }
        if hasActiveRouteSnapshot {
            appState = .readyToMove
        } else if !hasDraftEdits {
            appState = .selectingA
        }
    }

    private func advanceRouteProgress(by distanceDelta: Double) -> (targetDistance: Double, shouldStop: Bool) {
        guard totalRouteDistance > 0 else {
            traveledDistance = 0
            return (0, true)
        }

        if activeOperationMode == .multiPoint && activeIsClosedLoop {
            var nextDistance = traveledDistance + distanceDelta
            nextDistance.formTruncatingRemainder(dividingBy: totalRouteDistance)
            if nextDistance < 0 {
                nextDistance += totalRouteDistance
            }
            traveledDistance = nextDistance
            routeTravelDirection = .forward
            return (nextDistance, false)
        }

        var nextDistance = traveledDistance + (distanceDelta * routeTravelDirection.multiplier)
        if activeIsEndlessLoop {
            while nextDistance > totalRouteDistance || nextDistance < 0 {
                if nextDistance > totalRouteDistance {
                    nextDistance = totalRouteDistance - (nextDistance - totalRouteDistance)
                    routeTravelDirection = .backward
                } else if nextDistance < 0 {
                    nextDistance = -nextDistance
                    routeTravelDirection = .forward
                }
            }
            traveledDistance = clampedRouteDistance(nextDistance)
            return (traveledDistance, false)
        }

        if routeTravelDirection == .forward, nextDistance >= totalRouteDistance {
            traveledDistance = totalRouteDistance
            routeTravelDirection = .forward
            return (totalRouteDistance, true)
        }

        if routeTravelDirection == .backward, nextDistance <= 0 {
            traveledDistance = 0
            routeTravelDirection = .backward
            return (0, true)
        }

        traveledDistance = clampedRouteDistance(nextDistance)
        return (traveledDistance, false)
    }

    private func normalizeRouteDirectionForCurrentState() {
        guard totalRouteDistance > 0 else {
            routeTravelDirection = .forward
            return
        }
        if activeOperationMode == .multiPoint && activeIsClosedLoop {
            routeTravelDirection = .forward
            return
        }
        if activeIsEndlessLoop {
            if traveledDistance >= totalRouteDistance {
                routeTravelDirection = .backward
            } else if traveledDistance <= 0 {
                routeTravelDirection = .forward
            }
        } else {
            traveledDistance = clampedRouteDistance(traveledDistance)
        }
    }

    private func clampedRouteDistance(_ distance: Double) -> Double {
        min(max(distance, 0), totalRouteDistance)
    }

    private func positionForCurrentEndpoint() -> CLLocationCoordinate2D? {
        if routeTravelDirection == .backward {
            return currentRoutePoints.first
        }
        return currentRoutePoints.last
    }

    func handleEndlessLoopSettingChange(_ isEnabled: Bool) {
        if isEnabled, isClosedLoop {
            isEndlessLoop = false
        }
        guard hasActiveRouteSnapshot, !hasDraftEdits, activeOperationMode != .fixedPoint, activeOperationMode != .joystick else {
            return
        }
        activeIsEndlessLoop = isEnabled && !activeIsClosedLoop
    }

    func handleClosedLoopSettingChange(_ isEnabled: Bool) {
        if isEnabled {
            isEndlessLoop = false
        }
        guard hasActiveRouteSnapshot, !hasDraftEdits, activeOperationMode == .multiPoint else {
            return
        }
        activeIsClosedLoop = isEnabled
        if isEnabled {
            activeIsEndlessLoop = false
            routeTravelDirection = .forward
        }
    }

    func beginJoystickSession() {
        guard activeOperationMode == .joystick, let current = currentPosition else { return }

        isJoystickSessionActive = true
        shouldResumeActiveAfterReconnect = false
        activeJoystickDirections.removeAll()
        stopJoystickMovement()
        resetSendTracking()
        startStreamingAndSend(current)
        startPinnedLocationKeepAlive()
        requestCameraCenter?(current)
        appState = .readyToMove
    }

    func endJoystickSession() {
        stopJoystickMovement()
        stopPinnedLocationKeepAlive()
        deviceManager.stopContinuousLocationStream()
        clearSimulatedLocationAsync()
        clearActiveSnapshot(clearPosition: true)
        if !hasDraftEdits {
            appState = .selectingA
        }
    }

    func updateJoystickDirection(_ direction: JoystickDirection, isPressed: Bool) {
        guard isJoystickSessionActive, activeOperationMode == .joystick, currentPosition != nil else { return }

        if isPressed {
            let inserted = activeJoystickDirections.insert(direction).inserted
            if inserted || joystickTimer == nil {
                startJoystickMovementIfNeeded()
            }
            return
        }

        activeJoystickDirections.remove(direction)
        if activeJoystickDirections.isEmpty {
            stopJoystickMovement()
            if let current = currentPosition {
                startStreamingAndSend(current, updateLastSent: false)
                startPinnedLocationKeepAlive()
            }
            appState = .readyToMove
        }
    }

    func stepJoystickMovement(elapsedTime: TimeInterval) {
        guard activeOperationMode == .joystick,
              isJoystickSessionActive,
              !activeJoystickDirections.isEmpty,
              let current = currentPosition else { return }

        let speedMetersPerSecond = speed * (1000.0 / 3600.0)
        let distanceMeters = speedMetersPerSecond * elapsedTime
        let newPosition = JoystickMotionEngine.coordinate(
            from: current,
            directions: activeJoystickDirections,
            distanceMeters: distanceMeters
        )

        currentPosition = newPosition
        requestCameraCenter?(newPosition)

        if shouldSendJoystickCoordinateUpdate(newPosition) {
            sendCoordinateAsync(newPosition)
        }
    }

    func startPinnedLocationKeepAlive() {
        pinnedKeepAliveTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isActiveSimulationRunning, let current = self.currentPosition else { return }
                self.startStreamingAndSend(current, updateLastSent: false)
            }
        }
        pinnedKeepAliveTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopPinnedLocationKeepAlive() {
        pinnedKeepAliveTimer?.invalidate()
        pinnedKeepAliveTimer = nil
    }

    func restorePinnedLocationIfNeeded(_ coordinate: CLLocationCoordinate2D?) {
        guard !isActiveSimulationRunning, let coordinate else { return }
        currentPosition = coordinate
        startStreamingAndSend(coordinate)
        startPinnedLocationKeepAlive()
    }

    private func clearSimulatedLocationAsync() {
        deviceManager.clearSimulatedLocation()
    }

    private func startJoystickMovementIfNeeded() {
        guard joystickTimer == nil, !activeJoystickDirections.isEmpty else {
            appState = .moving
            return
        }

        stopPinnedLocationKeepAlive()
        appState = .moving
        let timerInterval = AppConstants.Simulation.joystickTimerInterval
        let timer = Timer(timeInterval: timerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stepJoystickMovement(elapsedTime: timerInterval)
            }
        }
        joystickTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopJoystickMovement() {
        joystickTimer?.invalidate()
        joystickTimer = nil
        activeJoystickDirections.removeAll()
    }

    private func resetSendTracking() {
        lastSentPosition = nil
        lastSentAt = nil
    }

    private func sendCoordinateAsync(_ coordinate: CLLocationCoordinate2D, updateLastSent: Bool = true) {
        deviceManager.sendLocationToDevice(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if updateLastSent {
            lastSentPosition = coordinate
            lastSentAt = Date()
        }
    }

    private func startStreamingAndSend(_ coordinate: CLLocationCoordinate2D, updateLastSent: Bool = true) {
        deviceManager.startContinuousLocationStream()
        sendCoordinateAsync(coordinate, updateLastSent: updateLastSent)
    }

    func shouldSendCoordinateUpdate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        shouldSendCoordinateUpdate(
            coordinate,
            minimumDistance: AppConstants.Simulation.minimumDistance,
            minimumTimeInterval: AppConstants.Simulation.minimumTimeInterval
        )
    }

    func shouldSendJoystickCoordinateUpdate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        shouldSendCoordinateUpdate(
            coordinate,
            minimumDistance: AppConstants.Simulation.joystickMinimumDistance,
            minimumTimeInterval: AppConstants.Simulation.joystickMinimumTimeInterval
        )
    }

    private func shouldSendCoordinateUpdate(
        _ coordinate: CLLocationCoordinate2D,
        minimumDistance: CLLocationDistance,
        minimumTimeInterval: TimeInterval
    ) -> Bool {
        if let lastAt = lastSentAt, Date().timeIntervalSince(lastAt) >= minimumTimeInterval {
            return true
        }
        guard let last = lastSentPosition else { return true }
        let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
        let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return a.distance(from: b) >= minimumDistance
    }

    // MARK: - Draft / active state

    func switchModePreservingPinnedLocation() {
        clearDraftWorkflow()
    }

    func applyPendingModeSwitchIfNeeded() {
        guard let pending = pendingModeSwitch else { return }
        pendingModeSwitch = nil
        operationMode = pending
        clearDraftWorkflow()
    }

    func resetWorkflowForMode() {
        clearDraftWorkflow()
    }

    func startIfReadyAndConnected() {
        guard deviceManager.isConnected else { return }

        if hasActiveRouteSnapshot {
            if activeOperationMode == .joystick {
                isJoystickSessionActive = currentPosition != nil
                stopJoystickMovement()
                if let current = currentPosition {
                    startStreamingAndSend(current)
                    startPinnedLocationKeepAlive()
                    requestCameraCenter?(current)
                }
                appState = .readyToMove
                return
            }

            if shouldResumeActiveAfterReconnect {
                shouldResumeActiveAfterReconnect = false
                startSimulation()
            } else if let current = currentPosition {
                startStreamingAndSend(current)
                startPinnedLocationKeepAlive()
                appState = .readyToMove
            }
            return
        }

        guard hasReadyDraft else { return }
        activateDraftForActiveSession()
        if activeOperationMode == .joystick {
            beginJoystickSession()
        } else {
            startSimulation()
        }
    }

    func handleDeviceDisconnected() {
        shouldResumeActiveAfterReconnect = isActiveSimulationRunning && activeOperationMode != .joystick
        if activeOperationMode == .joystick {
            stopJoystickMovement()
            activeJoystickDirections.removeAll()
        }
        stopSimulation(keepPinned: false)
        if hasActiveRouteSnapshot {
            appState = .readyToMove
        }
    }

    private func clearDraftWorkflow() {
        appState = hasActiveRouteSnapshot ? .readyToMove : .selectingA
        pointA = nil
        pointB = nil
        tempCoordinate = nil
        waypoints = []
        selectedImportedGPXRouteID = nil
        clearDraftGeometry()
        locationInputError = nil
    }

    private func clearDraftGeometry() {
        routes = []
        selectedRouteIndex = 0
        customRoutePolyline = nil
        draftRoutePoints = []
        draftCumulativeRouteDistances = []
        draftTotalRouteDistance = 0
    }

    private func routeABFailureMessage(for error: (any Error)?) -> String {
        if error != nil {
            return "A 到 B 路線計算失敗，請調整起點或終點後再試。"
        }
        return "找不到 A 到 B 的可用步行路線，請調整起點或終點後再試。"
    }

    private func multiPointFailureMessage(segmentIndex: Int, error: (any Error)?) -> String {
        if error != nil {
            return "第 \(segmentIndex + 1) 段路線計算失敗，請調整選點後再試。"
        }
        return "第 \(segmentIndex + 1) 段找不到可用步行路線，請調整選點後再試。"
    }

    private func clearActiveSnapshot(clearPosition: Bool) {
        activeRoutePolyline = nil
        currentRoutePoints = []
        cumulativeRouteDistances = []
        traveledDistance = 0
        totalRouteDistance = 0
        routeTravelDirection = .forward
        activeIsClosedLoop = false
        activeIsEndlessLoop = false
        isActiveSimulationRunning = false
        isJoystickSessionActive = false
        shouldResumeActiveAfterReconnect = false
        stopJoystickMovement()
        resetSendTracking()
        if clearPosition {
            currentPosition = nil
        }
        if !hasDraftEdits {
            appState = .selectingA
        }
    }

    private func makeDraftPolyline() -> MKPolyline? {
        if let route = selectedRoute {
            return route.polyline
        }
        if let custom = customRoutePolyline, custom.pointCount > 1 {
            return custom
        }
        guard draftRoutePoints.count > 1 else { return nil }
        var coords = draftRoutePoints
        return MKPolyline(coordinates: &coords, count: coords.count)
    }

    private func prepareForRouteReplacement() {
        moveTimer?.invalidate()
        moveTimer = nil
        stopJoystickMovement()
        stopPinnedLocationKeepAlive()
        isActiveSimulationRunning = false
        isJoystickSessionActive = false
        shouldResumeActiveAfterReconnect = false
        resetSendTracking()
    }

    // MARK: - Scene phase

    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            if !isActiveSimulationRunning, currentPosition != nil {
                startPinnedLocationKeepAlive()
            }
        case .inactive, .background:
            if !isActiveSimulationRunning {
                stopPinnedLocationKeepAlive()
            }
        @unknown default:
            break
        }
    }

    private func endpointMarkers(
        for coordinates: [CLLocationCoordinate2D],
        isClosedLoop: Bool,
        startStyle: RouteEndpointMarkerStyle,
        endStyle: RouteEndpointMarkerStyle,
        startEndStyle: RouteEndpointMarkerStyle,
        labelPrefix: String
    ) -> [RouteEndpointMarker] {
        let normalized = normalizeRoutePoints(coordinates)
        guard let start = normalized.first else { return [] }

        let startTitle = labelPrefix.isEmpty ? "起點" : "\(labelPrefix)起點"
        let endTitle = labelPrefix.isEmpty ? "終點" : "\(labelPrefix)終點"
        let mergedTitle = labelPrefix.isEmpty ? "起點／終點" : "\(labelPrefix)起點／終點"

        if isClosedLoop {
            return [
                RouteEndpointMarker(
                    style: startEndStyle,
                    title: mergedTitle,
                    coordinate: start
                )
            ]
        }

        guard let end = normalized.last else {
            return [
                RouteEndpointMarker(
                    style: startStyle,
                    title: startTitle,
                    coordinate: start
                )
            ]
        }

        return [
            RouteEndpointMarker(style: startStyle, title: startTitle, coordinate: start),
            RouteEndpointMarker(style: endStyle, title: endTitle, coordinate: end)
        ]
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, !seconds.isNaN else { return "--" }

        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours) 小時 \(minutes) 分"
        }
        return "\(minutes) 分 \(remainingSeconds) 秒"
    }

    // MARK: - Map helpers

    func persistMapRegion(from position: MapCameraPosition) {
        guard let region = position.region else { return }
        let normalized = normalizeMapRegion(region)
        let defaults = UserDefaults.standard
        defaults.set(normalized.center.latitude, forKey: "map.center.lat")
        defaults.set(normalized.center.longitude, forKey: "map.center.lon")
        defaults.set(normalized.span.latitudeDelta, forKey: "map.span.lat")
        defaults.set(normalized.span.longitudeDelta, forKey: "map.span.lon")
    }

    func normalizeRoutePoints(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(points.count)
        for point in points {
            guard CLLocationCoordinate2DIsValid(point),
                  point.latitude.isFinite,
                  point.longitude.isFinite else { continue }
            if let last = result.last {
                let nearDuplicate = abs(last.latitude - point.latitude) < 0.0000001
                    && abs(last.longitude - point.longitude) < 0.0000001
                if nearDuplicate { continue }
            }
            result.append(point)
        }
        return result
    }

    func normalizeMapRegion(_ region: MKCoordinateRegion) -> MKCoordinateRegion {
        let defaultCenter = CLLocationCoordinate2D(
            latitude: AppConstants.Map.defaultLatitude,
            longitude: AppConstants.Map.defaultLongitude
        )
        let center: CLLocationCoordinate2D = {
            let c = region.center
            guard CLLocationCoordinate2DIsValid(c), c.latitude.isFinite, c.longitude.isFinite else {
                return defaultCenter
            }
            return c
        }()
        let minSpan = AppConstants.Map.minimumSpanDelta
        let maxSpan = AppConstants.Map.maximumSpanDelta
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: min(max(region.span.latitudeDelta, minSpan), maxSpan),
                longitudeDelta: min(max(region.span.longitudeDelta, minSpan), maxSpan)
            )
        )
    }

    func mapRegion(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let valid = coordinates.filter {
            CLLocationCoordinate2DIsValid($0) && $0.latitude.isFinite && $0.longitude.isFinite
        }
        guard let first = valid.first else {
            return normalizeMapRegion(MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: AppConstants.Map.defaultLatitude,
                    longitude: AppConstants.Map.defaultLongitude
                ),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in valid.dropFirst() {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        return normalizeMapRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.25, AppConstants.Map.defaultSpanDelta),
                longitudeDelta: max((maxLon - minLon) * 1.25, AppConstants.Map.defaultSpanDelta)
            )
        ))
    }

    // MARK: - Search result helpers

    func coordinate(for item: MKMapItem) -> CLLocationCoordinate2D? {
        guard let coordinate = item.paperclipCoordinate else { return nil }
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return coordinate
    }

    func searchResultSubtitle(for item: MKMapItem) -> String {
        item.paperclipAddressSummary
    }

    func searchResultDistanceText(for item: MKMapItem, cameraRegion: MKCoordinateRegion?) -> String? {
        guard let center = cameraRegion?.center else { return nil }
        guard let location = item.paperclipLocation else { return nil }
        let reference = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let distance = reference.distance(from: location)
        guard distance.isFinite else { return nil }
        return String(format: "%.1fkm", distance / 1000)
    }

    func adjustSpeed(by delta: Double) {
        let stepScale = 1.0 / AppConstants.Simulation.speedStep
        let nextSpeed = (speed + delta) * stepScale
        speed = min(max(nextSpeed.rounded() / stepScale, AppConstants.Simulation.speedStep), maximumSpeed)
    }

    // MARK: - Cleanup

    func cleanup() {
        stopPinnedLocationKeepAlive()
        stopJoystickMovement()
        moveTimer?.invalidate()
        moveTimer = nil
        joystickTimer?.invalidate()
        joystickTimer = nil
    }
}
