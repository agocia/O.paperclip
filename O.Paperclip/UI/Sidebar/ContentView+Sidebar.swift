import SwiftUI
import MapKit

extension ContentView {
    @ViewBuilder
    func purePointOverlaySection(_ overlay: PurePointOverlay, isCompactSidebar: Bool) -> some View {
        PurePointOverlaySection(
            overlay: overlay,
            isCompactSidebar: isCompactSidebar,
            state: bindingForOverlayState(overlay),
            visiblePoints: visiblePoints(for: overlay),
            pointCountByCategory: pointCountByCategory(for: overlay),
            isImported: !overlay.isBuiltIn,
            onToggleEnabled: { newValue in
                var s = overlayState(for: overlay)
                s.isEnabled = newValue
                purePointOverlayStates[overlay.id] = s
            },
            onToggleFilterExpanded: { newValue in
                var s = overlayState(for: overlay)
                s.isFilterExpanded = newValue
                purePointOverlayStates[overlay.id] = s
            },
            onToggleCategory: { categoryID in
                toggleCategory(categoryID, in: overlay)
            },
            onSelectAllCategories: { selectAllCategories(in: overlay) },
            onClearAllCategories: { clearAllCategories(in: overlay) },
            onFocus: { focusPurePoints(in: overlay) },
            onRemoveImported: { removeImportedOverlay(overlay) }
        )
    }

    @ViewBuilder
    var locationInputSection: some View {
        LocationInputSectionView(vm: vm, currentRegion: cameraPosition.region)
    }

    var wirelessModeBinding: Binding<Bool> {
        Binding(
            get: { vm.deviceManager.isWirelessMode },
            set: { newValue in
                let manager = vm.deviceManager
                guard manager.isWirelessMode != newValue else { return }
                guard !manager.isConnecting else { return }

                if manager.isConnected {
                    Task {
                        await manager.disconnectAsync()
                        DispatchQueue.main.async {
                            manager.isWirelessMode = newValue
                            manager.connectDevice()
                        }
                    }
                } else {
                    manager.isWirelessMode = newValue
                }
            }
        )
    }

    var operationModePicker: some View {
        Picker("模式", selection: $vm.operationMode) {
            ForEach(OperationMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .background(ModernTheme.panelRaised.cornerRadius(8))
    }

    func deviceStatusSection(isCompactSidebar: Bool) -> some View {
        DeviceStatusSectionView(
            vm: vm,
            isCompactSidebar: isCompactSidebar,
            isWirelessMode: wirelessModeBinding
        )
    }

    @ViewBuilder
    var pinnedCoordinateSection: some View {
        if let pinned = vm.pinnedCoordinate {
            Text(
                String(
                    format: "目前座標（維持在最後信息送出位置）：%.6f, %.6f",
                    pinned.latitude,
                    pinned.longitude
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        if let notice = vm.activityNotice {
            Text(notice)
                .font(.caption)
                .foregroundColor(.yellow)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    func sidebarPane(isCompactSidebar: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            ModernTheme.background
                .ignoresSafeArea()

            SidebarView {
                VStack(spacing: 0) {
                    ScrollView {
                        sidebarSections(isCompactSidebar: isCompactSidebar)
                    }
                    .scrollIndicators(.automatic)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    sidebarFooter(isCompactSidebar: isCompactSidebar)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    func handleDeviceConnectionChange(isConnected: Bool) {
        guard isConnected else {
            vm.handleDeviceDisconnected()
            return
        }

        vm.startIfReadyAndConnected()

        guard let current = vm.currentPosition else { return }
        vm.deviceManager.startContinuousLocationStream()
        Task {
            try? await vm.deviceManager.sendLocationToDeviceAsync(latitude: current.latitude, longitude: current.longitude)
        }
    }

    func handleOperationModeChange() {
        vm.switchModePreservingPinnedLocation()
    }

    func handleCameraPositionChange(_ newValue: MapCameraPosition) {
        if let region = newValue.region {
            let normalized = vm.normalizeMapRegion(region)
            visibleMapRegion = normalized
            vm.persistMapRegion(from: .region(normalized))
        } else {
            vm.persistMapRegion(from: newValue)
        }
    }

    func handlePlaceKeywordChange(_ newValue: String) {
        vm.locationSearchService.updateQuery(newValue, region: cameraPosition.region)
    }

    func clampSpeedIfNeeded(_ newValue: Double) {
        let clamped = min(max(newValue, AppConstants.Simulation.speedStep), vm.maximumSpeed)
        if abs(clamped - newValue) > 0.0001 {
            vm.speed = clamped
        }
    }

    func handleClosedLoopChange(_ isEnabled: Bool) {
        if isEnabled {
            vm.isEndlessLoop = false
        }
    }

    func handleScenePhaseUpdate(_ newPhase: ScenePhase) {
        diagnostics.noteScenePhase(newPhase)
        vm.handleScenePhaseChange(newPhase)
    }

    func handlePurePointImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            beginImportedPurePointOverlaySession(with: urls)
        case .failure(let error):
            resetPurePointImportSession()
            purePointImportError = error.localizedDescription
        }
    }

    func configureCameraRequestHandler() {
        vm.requestCameraPosition = { [weak vm] position in
            guard vm != nil else { return }
            cameraPosition = position
        }
    }

    func sidebarSections(isCompactSidebar: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompactSidebar ? 12 : 20) {
            operationModePicker
            deviceStatusSection(isCompactSidebar: isCompactSidebar)
            pinnedCoordinateSection
            StatusViewSection(vm: vm, routeColors: routeColors)
            locationInputSection
            purePointControlsSection(isCompactSidebar: isCompactSidebar)
            Divider()
            movementSettingsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isCompactSidebar ? 10 : 16)
        .padding(.top, isCompactSidebar ? 8 : 14)
        .padding(.bottom, isCompactSidebar ? 10 : 18)
    }

    @ViewBuilder
    func sidebarFooter(isCompactSidebar: Bool) -> some View {
        SidebarFooterView(
            vm: vm,
            isCompactSidebar: isCompactSidebar
        )
    }

    @ViewBuilder
    func purePointControlsSection(isCompactSidebar: Bool) -> some View {
        PurePointControlsSectionView(
            overlayCount: purePointOverlays.count,
            importError: purePointImportError,
            renderNotice: purePointRenderNotice,
            hasVisiblePoints: !visiblePurePoints.isEmpty,
            onImport: {
                resetPurePointImportSession()
                purePointImportError = nil
                isImportingPurePointKML = true
            },
            onFocusAll: focusAllPurePoints
        ) {
            ForEach(purePointOverlays) { overlay in
                purePointOverlaySection(overlay, isCompactSidebar: isCompactSidebar)
            }
        }
    }

    var speedTextBinding: Binding<String> {
        Binding(
            get: { String(format: "%.1f", vm.speed) },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let parsed = Double(trimmed) else { return }
                vm.speed = min(max(parsed, AppConstants.Simulation.speedStep), vm.maximumSpeed)
            }
        )
    }

    @ViewBuilder
    var movementSettingsSection: some View {
        MovementSettingsSectionView(
            vm: vm,
            speedText: speedTextBinding
        )
    }

    var routeReplacementSheetBinding: Binding<Bool> {
        Binding(
            get: { vm.isShowingRouteReplacementConfirmation },
            set: { newValue in
                vm.isShowingRouteReplacementConfirmation = newValue
            }
        )
    }

    var routeReplacementSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("開始新路線")
                .font(.title3)
                .fontWeight(.semibold)

            Text("將以新路線取代目前藍線路線，但不會中斷裝置連線。")
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Spacer()
                Button("取消") {
                    vm.cancelRouteReplacement()
                }
                .buttonStyle(.bordered)

                Button("確認開始") {
                    vm.confirmRouteReplacement()
                }
                .buttonStyle(.borderedProminent)
                .tint(ModernTheme.accent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
