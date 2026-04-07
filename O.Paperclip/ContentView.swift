import SwiftUI
import MapKit
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    private enum PersistedMapKeys {
        static let centerLat = "map.center.lat"
        static let centerLon = "map.center.lon"
        static let spanLat = "map.span.lat"
        static let spanLon = "map.span.lon"
    }

    @StateObject var diagnostics = AppDiagnostics.shared
    @State var vm: AppViewModel

    @State var cameraPosition: MapCameraPosition
    @State var purePointOverlays: [PurePointOverlay]
    @State var purePointOverlayStates: [String: PurePointOverlayUIState]
    @State var isImportingPurePointKML: Bool = false
    @State var purePointImportError: String?
    @State var pendingImportedOverlays: [PurePointOverlay] = []
    @State var pendingImportedOverlayTitles: [String: String] = [:]
    @State var pendingImportedOverlaySourceURLs: [URL] = []
    @State var pendingPurePointRemoteApprovalURLs: [URL] = []
    @State var approvedPurePointRemoteURLs: Set<URL> = []
    @State var isShowingImportedOverlayNamingSheet: Bool = false
    @State var isShowingPurePointRemoteApprovalSheet: Bool = false
    @State var visibleMapRegion: MKCoordinateRegion
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
            return "為了避免地圖當掉，純點目前只顯示視野內 \(state.points.count) / \(state.viewportMatchingCount) 個。請放大地圖或縮小分類。"
        }
        if state.isViewportFiltered, state.viewportMatchingCount < state.totalMatchingCount {
            return "純點數量較多，地圖目前只渲染視野內的 \(state.viewportMatchingCount) 個點位。"
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
        .sheet(isPresented: $isShowingImportedOverlayNamingSheet) {
            importedOverlayNamingSheet
        }
        .sheet(isPresented: $isShowingPurePointRemoteApprovalSheet) {
            remoteLinkApprovalSheet
        }
        .sheet(isPresented: routeReplacementSheetBinding) {
            routeReplacementSheet
        }
        .onDisappear {
            vm.cleanup()
        }
        .onAppear {
            configureCameraRequestHandler()
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
            detailPane
        }
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
                                            Button("取消") { vm.cancelTempCoordinate() }
                                                .buttonStyle(.bordered)
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
                    .onMapCameraChange(frequency: .onEnd) { context in
                        visibleMapRegion = vm.normalizeMapRegion(context.region)
                    }
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .modifiers(EventModifiers.shift)
                            .onEnded { event in
                                if let coordinate = proxy.convert(event.location, from: .local) {
                                    vm.handleMapTap(at: coordinate)
                                }
                            }
                    )
                    .edgesIgnoringSafeArea(.all)
                    }
                }
            } else {
                Color.clear
            }
        }
    }

}
