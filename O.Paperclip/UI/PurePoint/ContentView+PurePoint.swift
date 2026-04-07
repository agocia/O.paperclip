import SwiftUI
import MapKit

extension ContentView {
    static func makeOverlayStates(for overlays: [PurePointOverlay]) -> [String: PurePointOverlayUIState] {
        Dictionary(uniqueKeysWithValues: overlays.map { overlay in
            let isEnabled = !overlay.isBuiltIn
            return (overlay.id, PurePointOverlayUIState(overlay: overlay, isEnabled: isEnabled))
        })
    }

    func overlayState(for overlay: PurePointOverlay) -> PurePointOverlayUIState {
        purePointOverlayStates[overlay.id] ?? PurePointOverlayUIState(overlay: overlay, isEnabled: !overlay.isBuiltIn)
    }

    func categoryLookup(for overlay: PurePointOverlay) -> [String: ShuangbeiPurePointCategory] {
        Dictionary(uniqueKeysWithValues: overlay.categories.map { ($0.id, $0) })
    }

    func pointCountByCategory(for overlay: PurePointOverlay) -> [String: Int] {
        Dictionary(grouping: overlay.points, by: \.categoryID).mapValues(\.count)
    }

    func visiblePoints(for overlay: PurePointOverlay) -> [ShuangbeiPurePoint] {
        let state = overlayState(for: overlay)
        guard state.isEnabled else { return [] }
        return overlay.points.filter {
            state.selectedCategoryIDs.contains($0.categoryID)
                && CLLocationCoordinate2DIsValid($0.coordinate)
                && $0.latitude.isFinite
                && $0.longitude.isFinite
        }
    }

    func bindingForOverlayEnabled(_ overlay: PurePointOverlay) -> Binding<Bool> {
        Binding(
            get: { overlayState(for: overlay).isEnabled },
            set: { newValue in
                var state = overlayState(for: overlay)
                state.isEnabled = newValue
                if state.selectedCategoryIDs.isEmpty {
                    state.selectedCategoryIDs = Set(overlay.categories.map(\.id))
                }
                state.isFilterExpanded = newValue ? true : state.isFilterExpanded
                purePointOverlayStates[overlay.id] = state
            }
        )
    }

    func bindingForOverlayState(_ overlay: PurePointOverlay) -> Binding<PurePointOverlayUIState> {
        Binding(
            get: { overlayState(for: overlay) },
            set: { newValue in
                purePointOverlayStates[overlay.id] = newValue
            }
        )
    }

    func bindingForOverlayFilterExpanded(_ overlay: PurePointOverlay) -> Binding<Bool> {
        Binding(
            get: { overlayState(for: overlay).isFilterExpanded },
            set: { newValue in
                var state = overlayState(for: overlay)
                state.isFilterExpanded = newValue
                purePointOverlayStates[overlay.id] = state
            }
        )
    }

    func toggleCategory(_ categoryID: String, in overlay: PurePointOverlay) {
        var state = overlayState(for: overlay)
        if state.selectedCategoryIDs.contains(categoryID) {
            state.selectedCategoryIDs.remove(categoryID)
        } else {
            state.selectedCategoryIDs.insert(categoryID)
        }
        purePointOverlayStates[overlay.id] = state
    }

    func selectAllCategories(in overlay: PurePointOverlay) {
        var state = overlayState(for: overlay)
        state.selectedCategoryIDs = Set(overlay.categories.map(\.id))
        purePointOverlayStates[overlay.id] = state
    }

    func clearAllCategories(in overlay: PurePointOverlay) {
        var state = overlayState(for: overlay)
        state.selectedCategoryIDs.removeAll()
        purePointOverlayStates[overlay.id] = state
    }

    func focusPurePoints(in overlay: PurePointOverlay) {
        let coordinates = visiblePoints(for: overlay).map(\.coordinate)
        guard !coordinates.isEmpty else { return }
        cameraPosition = .region(vm.mapRegion(fitting: coordinates))
    }

    func focusAllPurePoints() {
        let coordinates = visiblePurePoints.map(\.point.coordinate)
        guard !coordinates.isEmpty else { return }
        cameraPosition = .region(vm.mapRegion(fitting: coordinates))
    }

    func syncOverlayStates() {
        var nextStates: [String: PurePointOverlayUIState] = [:]
        for overlay in purePointOverlays {
            let fallback = PurePointOverlayUIState(overlay: overlay, isEnabled: !overlay.isBuiltIn)
            let existing = purePointOverlayStates[overlay.id] ?? fallback
            let validCategoryIDs = Set(overlay.categories.map(\.id))
            let selected = existing.selectedCategoryIDs.intersection(validCategoryIDs)
            nextStates[overlay.id] = PurePointOverlayUIState(
                isEnabled: existing.isEnabled,
                isFilterExpanded: existing.isFilterExpanded,
                selectedCategoryIDs: selected.isEmpty ? validCategoryIDs : selected
            )
        }
        purePointOverlayStates = nextStates
    }

    func persistImportedOverlaySettings() {
        let paths = purePointOverlays
            .filter { !$0.isBuiltIn }
            .compactMap(\.sourceFilePath)
        let titles = purePointOverlays.reduce(into: [String: String]()) { partialResult, overlay in
            guard !overlay.isBuiltIn, let path = overlay.sourceFilePath else { return }
            partialResult[path] = overlay.title
        }
        ImportedPurePointOverlayStore.savePaths(paths)
        ImportedPurePointOverlayStore.saveTitleOverrides(titles)
    }

    func beginImportedPurePointOverlaySession(with urls: [URL]) {
        guard !urls.isEmpty else { return }
        resetPurePointImportSession()
        purePointImportError = nil
        pendingImportedOverlaySourceURLs = urls
        prepareImportedPurePointOverlays(from: urls)
    }

    func prepareImportedPurePointOverlays(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        do {
            let overlays = try ImportedPurePointOverlayStore.previewOverlays(
                from: urls,
                approvedRemoteURLs: approvedPurePointRemoteURLs
            )
            purePointImportError = nil
            pendingPurePointRemoteApprovalURLs = []
            isShowingPurePointRemoteApprovalSheet = false
            pendingImportedOverlays = overlays
            pendingImportedOverlayTitles = Dictionary(
                uniqueKeysWithValues: overlays.map { ($0.id, $0.title) }
            )
            isShowingImportedOverlayNamingSheet = true
        } catch let error as PurePointImportError {
            switch error {
            case .remoteLinkRequiresApproval(let remoteURLs):
                purePointImportError = nil
                pendingPurePointRemoteApprovalURLs = remoteURLs
                isShowingImportedOverlayNamingSheet = false
                isShowingPurePointRemoteApprovalSheet = true
            default:
                resetPurePointImportSession()
                purePointImportError = error.localizedDescription
            }
        } catch {
            resetPurePointImportSession()
            purePointImportError = error.localizedDescription
        }
    }

    func finalizeImportedPurePointOverlays() {
        do {
            let renamedOverlays = pendingImportedOverlays.map { overlay in
                overlay.renamed(to: pendingImportedOverlayTitles[overlay.id] ?? overlay.title)
            }
            let persistedOverlays = try ImportedPurePointOverlayStore.persistImportedOverlays(
                renamedOverlays,
                approvedRemoteURLs: approvedPurePointRemoteURLs
            )
            commitImportedPurePointOverlays(persistedOverlays)
            purePointImportError = nil
            resetPurePointImportSession()
        } catch let error as PurePointImportError {
            switch error {
            case .remoteLinkRequiresApproval(let remoteURLs):
                purePointImportError = nil
                pendingPurePointRemoteApprovalURLs = remoteURLs
                isShowingImportedOverlayNamingSheet = false
                isShowingPurePointRemoteApprovalSheet = true
            default:
                purePointImportError = error.localizedDescription
            }
        } catch {
            purePointImportError = error.localizedDescription
        }
    }

    func cancelImportedPurePointOverlays() {
        resetPurePointImportSession()
    }

    func approvePendingPurePointRemoteLinks() {
        let approved = pendingPurePointRemoteApprovalURLs.map(PurePointKMLResolver.normalizedRemoteURL)
        approvedPurePointRemoteURLs.formUnion(approved)
        pendingPurePointRemoteApprovalURLs = []
        isShowingPurePointRemoteApprovalSheet = false
        prepareImportedPurePointOverlays(from: pendingImportedOverlaySourceURLs)
    }

    func cancelPendingPurePointRemoteLinks() {
        resetPurePointImportSession()
    }

    func resetPurePointImportSession() {
        pendingImportedOverlays = []
        pendingImportedOverlayTitles = [:]
        pendingImportedOverlaySourceURLs = []
        pendingPurePointRemoteApprovalURLs = []
        approvedPurePointRemoteURLs = []
        isShowingImportedOverlayNamingSheet = false
        isShowingPurePointRemoteApprovalSheet = false
    }

    func commitImportedPurePointOverlays(_ overlays: [PurePointOverlay]) {
        var overlaysByPath: [String: PurePointOverlay] = Dictionary(
            uniqueKeysWithValues: purePointOverlays
                .filter { !$0.isBuiltIn }
                .compactMap { overlay in
                    guard let path = overlay.sourceFilePath else { return nil }
                    return (path, overlay)
                }
        )
        for overlay in overlays {
            if let path = overlay.sourceFilePath {
                overlaysByPath[path] = overlay
            }
        }
        purePointOverlays = overlaysByPath.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        syncOverlayStates()
        persistImportedOverlaySettings()
    }

    func removeImportedOverlay(_ overlay: PurePointOverlay) {
        ImportedPurePointOverlayStore.deleteStoredOverlay(overlay)
        purePointOverlays.removeAll { $0.id == overlay.id }
        purePointOverlayStates.removeValue(forKey: overlay.id)
        persistImportedOverlaySettings()
    }

    @ViewBuilder
    var importedOverlayNamingSheet: some View {
        ImportedOverlayNamingSheet(
            overlays: pendingImportedOverlays,
            titles: $pendingImportedOverlayTitles,
            onCancel: cancelImportedPurePointOverlays,
            onImport: finalizeImportedPurePointOverlays
        )
    }

    @ViewBuilder
    var remoteLinkApprovalSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Remote KML Approval Required")
                .font(.title3)
                .fontWeight(.semibold)

            Text("This import batch contains a NetworkLink. The URLs below will only be downloaded after you approve them, and that approval only applies to the current import flow.")
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(pendingPurePointRemoteApprovalURLs, id: \.absoluteString) { url in
                        Text(url.absoluteString)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 260)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") {
                    cancelPendingPurePointRemoteLinks()
                }
                .buttonStyle(.bordered)

                Button("Download") {
                    approvePendingPurePointRemoteLinks()
                }
                .buttonStyle(.borderedProminent)
                .tint(ModernTheme.accent)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
