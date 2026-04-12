import SwiftUI
import MapKit
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isMapKeyboardFocused: Bool

    private enum PersistedMapKeys {
        static let centerLat = "map.center.lat"
        static let centerLon = "map.center.lon"
        static let spanLat = "map.span.lat"
        static let spanLon = "map.span.lon"
        static let isRightSidebarVisible = "sidebar.right.visible"
        static let savedLocationSortMode = "saved-location.sort-mode"
    }

    @StateObject var diagnostics = AppDiagnostics.shared
    @State var vm: AppViewModel

    @State var cameraPosition: MapCameraPosition
    @State var purePointOverlays: [PurePointOverlay]
    @State var purePointOverlayStates: [String: PurePointOverlayUIState]
    @State var isImportingPurePointKML: Bool = false
    @State var isImportingGPXRoute: Bool = false
    @State var purePointImportError: String?
    @State var pendingImportedOverlays: [PurePointOverlay] = []
    @State var pendingImportedOverlayTitles: [String: String] = [:]
    @State var pendingImportedOverlaySourceURLs: [URL] = []
    @State var pendingPurePointRemoteApprovalURLs: [URL] = []
    @State var approvedPurePointRemoteURLs: Set<URL> = []
    @State var isShowingImportedOverlayNamingSheet: Bool = false
    @State var isShowingPurePointRemoteApprovalSheet: Bool = false
    @State var visibleMapRegion: MKCoordinateRegion
    @State var isRightSidebarVisible: Bool
    @State var savedLocationSortMode: SavedLocationSortMode
    let routeColors: [Color] = [.yellow, .orange, .mint, .pink]
    private let purePointViewportActivationCount = AppConstants.PurePoint.viewportActivationCount
    private let purePointRenderedLimit = AppConstants.PurePoint.renderedLimit
    private let purePointViewportPadding = AppConstants.PurePoint.viewportPadding
    private let purePointWideSpanThreshold = AppConstants.PurePoint.wideSpanThreshold

    init() {
        let defaults = UserDefaults.standard
        let lat = defaults.object(forKey: PersistedMapKeys.centerLat) as? Double ?? AppConstants.Map.defaultLatitude
        let lon = defaults.object(forKey: PersistedMapKeys.centerLon) as? Double ?? AppConstants.Map.defaultLongitude
        let spanLat = defaults.object(forKey: PersistedMapKeys.spanLat) as? Double ?? 0.05
        let spanLon = defaults.object(forKey: PersistedMapKeys.spanLon) as? Double ?? 0.05
        let centerCandidate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let center: CLLocationCoordinate2D
        if CLLocationCoordinate2DIsValid(centerCandidate),
           centerCandidate.latitude.isFinite,
           centerCandidate.longitude.isFinite {
            center = centerCandidate
        } else {
            center = CLLocationCoordinate2D(
                latitude: AppConstants.Map.defaultLatitude,
                longitude: AppConstants.Map.defaultLongitude
            )
        }
        let minSpan = AppConstants.Map.minimumSpanDelta
        let maxSpan = AppConstants.Map.maximumSpanDelta
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: min(max(spanLat, minSpan), maxSpan),
                longitudeDelta: min(max(spanLon, minSpan), maxSpan)
            )
        )
        _cameraPosition = State(initialValue: .region(region))
        _visibleMapRegion = State(initialValue: region)
        _isRightSidebarVisible = State(initialValue: defaults.object(forKey: PersistedMapKeys.isRightSidebarVisible) as? Bool ?? true)
        let sortRaw = defaults.string(forKey: PersistedMapKeys.savedLocationSortMode) ?? SavedLocationSortMode.createdAt.rawValue
        _savedLocationSortMode = State(initialValue: SavedLocationSortMode(rawValue: sortRaw) ?? .createdAt)
        let initialOverlays = PurePointOverlayRepository.initialOverlays()
        _purePointOverlays = State(initialValue: initialOverlays)
        _purePointOverlayStates = State(initialValue: Self.makeOverlayStates(for: initialOverlays))
        let deviceManager = DeviceManager()
        let locationSearchService = LocationSearchService()
        _vm = State(initialValue: AppViewModel(deviceManager: deviceManager, locationSearchService: locationSearchService))
    }

    var visiblePurePoints: [VisiblePurePoint] {
        purePointOverlays.flatMap { overlay in
            let lookup = categoryLookup(for: overlay)
            return visiblePoints(for: overlay).map { point in
                VisiblePurePoint(overlay: overlay, point: point, category: lookup[point.categoryID])
            }
        }
    }

    private var purePointRenderState: PurePointRenderState {
        PurePointRenderEngine.renderState(
            for: visiblePurePoints,
            region: vm.normalizeMapRegion(visibleMapRegion),
            padding: purePointViewportPadding,
            limit: purePointRenderedLimit,
            activationCount: purePointViewportActivationCount,
            wideSpanThreshold: purePointWideSpanThreshold
        )
    }

    private var renderedPurePoints: [VisiblePurePoint] {
        purePointRenderState.points
    }

    var purePointRenderNotice: String? {
        let state = purePointRenderState
        guard state.totalMatchingCount > 0 else { return nil }

        if state.isDensityLimited {
            return "為了避免地圖當掉，KML 目前只顯示視野內 \(state.points.count) / \(state.viewportMatchingCount) 個。請放大地圖或縮小分類。"
        }
        if state.isViewportFiltered, state.viewportMatchingCount < state.totalMatchingCount {
            return "KML 點位較多，地圖目前只渲染視野內的 \(state.viewportMatchingCount) 個點位。"
        }
        return nil
    }

    var body: some View {
        let _ = vm.dependencyVersion
        contentRoot
        .onChange(of: vm.deviceManager.isConnected) { _, isConnected in
            handleDeviceConnectionChange(isConnected: isConnected)
        }
        .onChange(of: vm.operationMode) { _, _ in
            handleOperationModeChange()
            requestMapKeyboardFocusIfNeeded()
        }
        .onChange(of: cameraPosition) { _, newValue in
            handleCameraPositionChange(newValue)
        }
        .onChange(of: vm.placeKeyword) { _, newValue in
            handlePlaceKeywordChange(newValue)
        }
        .onChange(of: vm.speed) { _, newValue in
            clampSpeedIfNeeded(newValue)
        }
        .onChange(of: vm.isClosedLoop) { _, isEnabled in
            handleClosedLoopChange(isEnabled)
        }
        .onChange(of: vm.isEndlessLoop) { _, isEnabled in
            handleEndlessLoopChange(isEnabled)
        }
        .onChange(of: isRightSidebarVisible) { _, isVisible in
            UserDefaults.standard.set(isVisible, forKey: PersistedMapKeys.isRightSidebarVisible)
        }
        .onChange(of: savedLocationSortMode) { _, mode in
            UserDefaults.standard.set(mode.rawValue, forKey: PersistedMapKeys.savedLocationSortMode)
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseUpdate(newPhase)
        }
        .fileImporter(
            isPresented: $isImportingPurePointKML,
            allowedContentTypes: [.kml],
            allowsMultipleSelection: true
        ) { result in
            handlePurePointImport(result)
        }
        .fileImporter(
            isPresented: $isImportingGPXRoute,
            allowedContentTypes: [.gpx],
            allowsMultipleSelection: true
        ) { result in
            handleGPXRouteImport(result)
        }
        .sheet(isPresented: $isShowingImportedOverlayNamingSheet) {
            importedOverlayNamingSheet
        }
        .sheet(isPresented: $isShowingPurePointRemoteApprovalSheet) {
            remoteLinkApprovalSheet
        }
        .sheet(
            isPresented: Binding(
                get: { vm.isShowingImportedGPXRouteNamingSheet },
                set: { vm.isShowingImportedGPXRouteNamingSheet = $0 }
            )
        ) {
            importedGPXRouteNamingSheet
        }
        .sheet(isPresented: routeReplacementSheetBinding) {
            routeReplacementSheet
        }
        .sheet(
            isPresented: Binding(
                get: { vm.isShowingSaveLocationSheet },
                set: { newValue in
                    if newValue {
                        vm.isShowingSaveLocationSheet = true
                    } else {
                        vm.cancelSaveCurrentSelection()
                    }
                }
            )
        ) {
            saveCurrentLocationSheet
        }
        .sheet(
            item: Binding(
                get: { vm.savedLocationRenamingTarget },
                set: { newValue in
                    if let newValue {
                        vm.savedLocationRenamingTarget = newValue
                    } else {
                        vm.cancelRenameSavedLocation()
                    }
                }
            )
        ) { item in
            renameSavedLocationSheet(item)
        }
        .onDisappear {
            vm.cleanup()
        }
        .onAppear {
            configureCameraRequestHandler()
            requestMapKeyboardFocusIfNeeded()
        }
    }

    private var contentRoot: some View {
        ZStack {
            windowBackground
            splitViewContent
        }
    }

    private var windowBackground: some View {
        ModernTheme.background
            .ignoresSafeArea()
    }

    private var splitViewContent: some View {
        HStack(spacing: 0) {
            sidebarPane(isCompactSidebar: true)
                .frame(width: 320)
            Divider()
            ZStack(alignment: .trailing) {
                detailPane
                if !isRightSidebarVisible {
                    collapsedRightSidebarHandle
                }
            }
            if isRightSidebarVisible {
                Divider()
                rightSidebarPane
                    .frame(width: 360)
            }
        }
    }

    private var collapsedRightSidebarHandle: some View {
        Button(action: { isRightSidebarVisible = true }) {
            Image(systemName: "sidebar.right")
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
                .background(ModernTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: ModernTheme.shadow, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 12)
    }

    private var detailPane: some View {
        GeometryReader { geometry in
            if geometry.size.width > 20, geometry.size.height > 20 {
                MapReader { proxy in
                    MapContentView(cameraPosition: $cameraPosition) {
                    Map(position: $cameraPosition) {
                        ForEach(renderedPurePoints) { entry in
                            Annotation(entry.point.name, coordinate: entry.point.coordinate, anchor: .center) {
                                Circle()
                                            .fill(PurePointRenderEngine.safeMapColor(for: entry.category))
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            }
                        }

                        if vm.operationMode == .multiPoint {
                            ForEach(Array(vm.waypoints.enumerated()), id: \.offset) { idx, point in
                                Marker("P\(idx + 1)", coordinate: point).tint(.yellow)
                            }
                        } else {
                            if let a = vm.pointA {
                                Marker(vm.operationMode == .fixedPoint ? "草稿定點" : "草稿起點 A", coordinate: a).tint(.yellow)
                            }
                            if let b = vm.pointB { Marker("草稿終點 B", coordinate: b).tint(.orange) }
                            if let temp = vm.tempCoordinate {
                                Annotation("確認位置", coordinate: temp, anchor: .bottom) {
                                    VStack(spacing: 6) {
                                        HStack(spacing: 6) {
                                            Button("確認") { vm.confirmTempCoordinate() }
                                                .buttonStyle(.borderedProminent)
                                                .tint(Color(red: 0.85, green: 0.55, blue: 0.35))
                                            Button(action: { vm.cancelTempCoordinate() }) {
                                                Text("取消")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(Color(red: 0.29, green: 0.24, blue: 0.20))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(
                                                        Capsule()
                                                            .fill(Color.white.opacity(0.96))
                                                    )
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(Color.black.opacity(0.14), lineWidth: 1)
                                                    )
                                            }
                                                .buttonStyle(.plain)
                                        }
                                        .controlSize(.small)
                                        .padding(.horizontal, 6)
                                        .padding(.top, 2)
                                        Circle()
                                            .fill(Color.yellow)
                                            .frame(width: 14, height: 14)
                                            .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
                                    }
                                    .padding(8)
                                    .background(Color(red: 0.98, green: 0.97, blue: 0.95))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .shadow(radius: 2)
                                }
                            }
                        }

                        if let active = vm.activeRoutePolyline, active.pointCount > 1 {
                            MapPolyline(active)
                                .stroke(Color(red: 0.08, green: 0.24, blue: 0.62), lineWidth: 5)
                        }

                        if !vm.routes.isEmpty {
                            if vm.appState == .routeSelection {
                                ForEach(Array(vm.routes.enumerated()), id: \.offset) { index, route in
                                    MapPolyline(route.polyline)
                                        .stroke(
                                            index == vm.selectedRouteIndex ? routeColors[index % routeColors.count] : .gray.opacity(0.3),
                                            lineWidth: index == vm.selectedRouteIndex ? 6 : 3
                                        )
                                }
                            } else if let route = vm.selectedRoute {
                                MapPolyline(route.polyline).stroke(Color.yellow, lineWidth: 5)
                            }
                        } else if let custom = vm.customRoutePolyline, custom.pointCount > 1 {
                            MapPolyline(custom).stroke(Color.yellow, lineWidth: 5)
                        }

                        if let current = vm.currentPosition {
                            Annotation("目前位置", coordinate: current) {
                                Circle()
                                    .fill(Color(red: 0.08, green: 0.24, blue: 0.62))
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                                    .shadow(radius: 4)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .environment(\.locale, Locale(identifier: "zh_TW"))
                    .focusable(vm.operationMode == .joystick)
                    .focused($isMapKeyboardFocused)
                    .onKeyPress(phases: [.down, .repeat, .up]) { press in
                        handleMapKeyPress(press)
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        visibleMapRegion = vm.normalizeMapRegion(context.region)
                    }
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { _ in
                                requestMapKeyboardFocusIfNeeded()
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .modifiers(EventModifiers.shift)
                            .onEnded { event in
                                requestMapKeyboardFocusIfNeeded()
                                if let coordinate = proxy.convert(event.location, from: .local) {
                                    vm.handleMapTap(at: coordinate)
                                }
                            }
                    )
                    .overlay(alignment: .topLeading) {
                        if shouldShowJoystickFocusHint {
                            joystickFocusHint
                                .padding(16)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if shouldShowJoystickControlPad {
                            JoystickControlPadView(
                                activeDirections: vm.activeJoystickDirections,
                                onDirectionPress: handleJoystickDirectionChange(_:isPressed:)
                            )
                            .padding(20)
                        }
                    }
                    .edgesIgnoringSafeArea(.all)
                    }
                }
            } else {
                Color.clear
            }
        }
    }

    private var shouldShowJoystickControlPad: Bool {
        vm.operationMode == .joystick
            && vm.activeOperationMode == .joystick
            && vm.isJoystickSessionActive
    }

    private var shouldShowJoystickFocusHint: Bool {
        shouldShowJoystickControlPad && !isMapKeyboardFocused
    }

    private var joystickFocusHint: some View {
        Text("點一下地圖以啟用方向鍵")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.68))
            .clipShape(Capsule())
    }

    private var importedGPXRouteNamingSheet: some View {
        ImportedGPXRouteNamingSheet(
            routes: vm.pendingImportedGPXRoutes,
            titles: Binding(
                get: { vm.pendingImportedGPXRouteTitles },
                set: { vm.pendingImportedGPXRouteTitles = $0 }
            ),
            onCancel: vm.cancelImportedGPXRoutes,
            onImport: vm.finalizeImportedGPXRoutes
        )
    }

    private func requestMapKeyboardFocusIfNeeded() {
        guard vm.operationMode == .joystick else { return }
        DispatchQueue.main.async {
            isMapKeyboardFocused = true
        }
    }

    private func handleJoystickDirectionChange(_ direction: JoystickDirection, isPressed: Bool) {
        requestMapKeyboardFocusIfNeeded()
        vm.updateJoystickDirection(direction, isPressed: isPressed)
    }

    private func handleMapKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard shouldShowJoystickControlPad, let direction = joystickDirection(for: press) else {
            return .ignored
        }

        if press.phase == .down || press.phase == .repeat {
            vm.updateJoystickDirection(direction, isPressed: true)
        } else if press.phase == .up {
            vm.updateJoystickDirection(direction, isPressed: false)
        } else {
            return .ignored
        }

        return .handled
    }

    private func joystickDirection(for press: KeyPress) -> JoystickDirection? {
        switch press.key {
        case .upArrow:
            return .up
        case .downArrow:
            return .down
        case .leftArrow:
            return .left
        case .rightArrow:
            return .right
        default:
            break
        }

        switch press.characters.lowercased() {
        case "w":
            return .up
        case "s":
            return .down
        case "a":
            return .left
        case "d":
            return .right
        default:
            return nil
        }
    }

}
