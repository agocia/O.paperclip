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

@MainActor
@Observable
final class AppViewModel {
    // MARK: - Dependencies
    let deviceManager: any DeviceControlling
    let locationSearchService: any LocationSearching

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
    var activeIsClosedLoop: Bool = false
    var activeIsEndlessLoop: Bool = false
    var isActiveSimulationRunning: Bool = false
    var shouldResumeActiveAfterReconnect: Bool = false
    var isShowingRouteReplacementConfirmation: Bool = false

    // MARK: - Settings
    var speed: Double = AppConstants.Simulation.defaultSpeed
    var isEndlessLoop: Bool = false
    var isClosedLoop: Bool = false

    // MARK: - Location input
    var placeKeyword: String = ""
    var placeResults: [MKMapItem] = []
    var coordinateInputText: String = ""
    var locationInputError: String?

    // MARK: - Map camera
    var requestCameraPosition: ((MapCameraPosition) -> Void)?

    // MARK: - Private
    @ObservationIgnored private var moveTimer: Timer?
    @ObservationIgnored private var pinnedKeepAliveTimer: Timer?
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    private(set) var lastSentPosition: CLLocationCoordinate2D?
    private(set) var lastSentAt: Date?
    var dependencyVersion: Int = 0

    let maximumSpeed = AppConstants.Simulation.maximumSpeed

    var selectedRoute: MKRoute? {
        routes.indices.contains(selectedRouteIndex) ? routes[selectedRouteIndex] : routes.first
    }

    var pinnedCoordinate: CLLocationCoordinate2D? {
        currentPosition ?? lastSentPosition
    }

    var hasActiveRouteSnapshot: Bool {
        activeRoutePolyline != nil || (activeOperationMode == .fixedPoint && currentPosition != nil)
    }

    var hasDraftPreview: Bool {
        !routes.isEmpty
            || (customRoutePolyline?.pointCount ?? 0) > 1
            || draftRoutePoints.count > 1
    }

    var hasDraftEdits: Bool {
        appState != .selectingA
            || pointA != nil
            || pointB != nil
            || tempCoordinate != nil
            || !waypoints.isEmpty
            || hasDraftPreview
    }

    var hasReadyDraft: Bool {
        guard appState == .readyToMove else { return false }
        switch operationMode {
        case .fixedPoint:
            return pointA != nil
        case .routeAB, .multiPoint:
            return draftRoutePoints.count > 1
        }
    }

    var shouldUseDraftControls: Bool {
        !hasActiveRouteSnapshot || hasDraftEdits
    }

    var shouldShowResetButton: Bool {
        hasActiveRouteSnapshot ? hasDraftEdits : hasDraftEdits
    }

    var resetButtonTitle: String {
        if hasActiveRouteSnapshot {
            return "清除草稿路線"
        }
        return operationMode == .fixedPoint ? "清除定位點" : "清除目前路線"
    }

    var activityNotice: String? {
        if hasActiveRouteSnapshot && hasDraftEdits {
            return "目前藍線持續運作中，正在編輯黃線草稿。"
        }
        if hasActiveRouteSnapshot && !isActiveSimulationRunning {
            return "目前藍線已停止移動，但定位仍固定在裝置上。"
        }
        return nil
    }

    var estimatedTime: String {
        let distance: Double
        if let route = selectedRoute {
            distance = route.distance
        } else if draftTotalRouteDistance > 0 {
            distance = draftTotalRouteDistance
        } else if totalRouteDistance > 0 {
            distance = totalRouteDistance
        } else {
            return "--"
        }
        let timeSeconds = distance / (speed * (1000.0 / 3600.0))
        if timeSeconds.isInfinite || timeSeconds.isNaN { return "--" }
        return "\(Int(timeSeconds) / 60) 分 \(Int(timeSeconds) % 60) 秒"
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
        !shouldUseDraftControls && isActiveSimulationRunning
    }

    private var draftButtonTitle: String {
        if operationMode == .fixedPoint {
            switch appState {
            case .selectingA, .confirmingA: return "選擇定位點"
            case .readyToMove: return "開始定位"
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
        if operationMode == .fixedPoint && (appState == .selectingA || appState == .confirmingA) {
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

    init(deviceManager: any DeviceControlling, locationSearchService: any LocationSearching) {
        self.deviceManager = deviceManager
        self.locationSearchService = locationSearchService

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

    // MARK: - Map interaction

    func handleMapTap(at coordinate: CLLocationCoordinate2D) {
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

        if operationMode == .fixedPoint {
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
        stopSimulation(keepPinned: false)
        activateDraftForActiveSession()
        startSimulation()
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
                startSimulation()
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
        activeOperationMode = operationMode
        activeIsClosedLoop = isClosedLoop
        activeIsEndlessLoop = isEndlessLoop
        shouldResumeActiveAfterReconnect = false

        switch operationMode {
        case .fixedPoint:
            guard let fixed = pointA else { return }
            currentPosition = fixed
            currentRoutePoints = []
            cumulativeRouteDistances = []
            traveledDistance = 0
            totalRouteDistance = 0
            activeRoutePolyline = nil
        case .routeAB, .multiPoint:
            guard draftRoutePoints.count > 1 else { return }
            currentRoutePoints = draftRoutePoints
            cumulativeRouteDistances = draftCumulativeRouteDistances
            traveledDistance = 0
            totalRouteDistance = draftTotalRouteDistance
            currentPosition = draftRoutePoints.first
            activeRoutePolyline = makeDraftPolyline()
        }

        clearDraftWorkflow()
    }

    // MARK: - Coordinate helpers

    func confirmTempCoordinate() {
        guard let temp = tempCoordinate else { return }
        switch appState {
        case .confirmingA:
            pointA = temp
            tempCoordinate = nil
            if operationMode == .fixedPoint {
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
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        request.transportType = .walking
        request.requestsAlternateRoutes = true

        MKDirections(request: request).calculate { response, _ in
            let routesBox = UnsafeSendableBox(response?.routes)
            MainActor.assumeIsolated {
                if let routes = routesBox.value {
                    self.routes = routes
                    self.customRoutePolyline = nil
                    self.selectedRouteIndex = 0
                    self.appState = .routeSelection
                } else {
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

            MKDirections(request: request).calculate { [weak self] response, _ in
                let routeBox = UnsafeSendableBox(response?.routes.first)
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard let route = routeBox.value else {
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
        isActiveSimulationRunning = true
        shouldResumeActiveAfterReconnect = false

        if activeOperationMode == .fixedPoint {
            guard let fixed = currentPosition else {
                isActiveSimulationRunning = false
                return
            }
            startStreamingAndSend(fixed)
            return
        }

        guard currentRoutePoints.count > 1 else {
            isActiveSimulationRunning = false
            return
        }

        if currentPosition == nil, let first = currentRoutePoints.first {
            currentPosition = first
        }
        if let initial = currentPosition ?? currentRoutePoints.first {
            startStreamingAndSend(initial)
        }

        let loopMode: RouteMotionEngine.LoopMode
        if activeOperationMode == .multiPoint && activeIsClosedLoop {
            loopMode = .circular
        } else if activeIsEndlessLoop {
            loopMode = .pingPong
        } else {
            loopMode = .singlePass
        }

        let timerInterval = AppConstants.Simulation.timerInterval
        let timer = Timer(timeInterval: timerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let speedMetersPerSecond = self.speed * (1000.0 / 3600.0)
                self.traveledDistance += speedMetersPerSecond * timerInterval

                guard let targetDistance = RouteMotionEngine.targetDistance(
                    traveledDistance: self.traveledDistance,
                    routeDistance: self.totalRouteDistance,
                    loopMode: loopMode
                ) else {
                    self.stopSimulation(keepPinned: true)
                    self.currentPosition = self.currentRoutePoints.last
                    if let last = self.currentPosition {
                        self.sendCoordinateAsync(last)
                    }
                    return
                }

                if let newPos = RouteMotionEngine.coordinate(
                    at: targetDistance,
                    in: self.currentRoutePoints,
                    distances: self.cumulativeRouteDistances
                ) {
                    self.currentPosition = newPos
                    if self.shouldSendCoordinateUpdate(newPos) {
                        self.sendCoordinateAsync(newPos)
                    }
                    if targetDistance > 0, Int(targetDistance) % 500 == 0 {
                        print("d=\(Int(targetDistance))m lat=\(newPos.latitude) lon=\(newPos.longitude)")
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
        lastSentPosition = nil
        lastSentAt = nil
        if keepPinned, let current = currentPosition {
            startStreamingAndSend(current)
            startPinnedLocationKeepAlive()
        } else {
            stopPinnedLocationKeepAlive()
            deviceManager.stopContinuousLocationStream()
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
        Task {
            try? await deviceManager.clearSimulatedLocationAsync()
        }
    }

    private func sendCoordinateAsync(_ coordinate: CLLocationCoordinate2D, updateLastSent: Bool = true) {
        deviceManager.sendLocationToDevice(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if updateLastSent {
            Task { @MainActor in
                self.lastSentPosition = coordinate
                self.lastSentAt = Date()
            }
        }
    }

    private func startStreamingAndSend(_ coordinate: CLLocationCoordinate2D, updateLastSent: Bool = true) {
        deviceManager.startContinuousLocationStream()
        sendCoordinateAsync(coordinate, updateLastSent: updateLastSent)
    }

    func shouldSendCoordinateUpdate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        if let lastAt = lastSentAt, Date().timeIntervalSince(lastAt) >= AppConstants.Simulation.minimumTimeInterval {
            return true
        }
        guard let last = lastSentPosition else { return true }
        let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
        let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return a.distance(from: b) >= AppConstants.Simulation.minimumDistance
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
            if shouldResumeActiveAfterReconnect {
                shouldResumeActiveAfterReconnect = false
                startSimulation()
            } else if let current = currentPosition {
                startStreamingAndSend(current)
                startPinnedLocationKeepAlive()
            }
            return
        }

        guard hasReadyDraft else { return }
        activateDraftForActiveSession()
        startSimulation()
    }

    func handleDeviceDisconnected() {
        shouldResumeActiveAfterReconnect = isActiveSimulationRunning
        stopSimulation(keepPinned: false)
    }

    private func clearDraftWorkflow() {
        appState = .selectingA
        pointA = nil
        pointB = nil
        tempCoordinate = nil
        waypoints = []
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

    private func clearActiveSnapshot(clearPosition: Bool) {
        activeRoutePolyline = nil
        currentRoutePoints = []
        cumulativeRouteDistances = []
        traveledDistance = 0
        totalRouteDistance = 0
        activeIsClosedLoop = false
        activeIsEndlessLoop = false
        isActiveSimulationRunning = false
        shouldResumeActiveAfterReconnect = false
        if clearPosition {
            currentPosition = nil
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
        moveTimer?.invalidate()
        moveTimer = nil
    }
}
