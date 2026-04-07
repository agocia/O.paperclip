import SwiftUI
import MapKit

struct StatusViewSection: View {
    @Bindable var vm: AppViewModel
    let routeColors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vm.hasActiveRouteSnapshot {
                Text(vm.isActiveSimulationRunning ? "Blue route is syncing" : "Blue route is pinned")
                    .foregroundColor(ModernTheme.info)
            }

            switch vm.appState {
            case .selectingA:
                if vm.operationMode == .multiPoint {
                    Text("Shift-click to add route points (at least 2)").foregroundColor(ModernTheme.accent)
                } else if vm.operationMode == .fixedPoint {
                    Text("Shift-click to set the pinned location").foregroundColor(ModernTheme.accent)
                } else {
                    Text("Shift-click to set \"Start A\"").foregroundColor(ModernTheme.accent)
                }
            case .confirmingA:
                if vm.operationMode == .fixedPoint {
                    Text("Pinned location selected. Confirm or cancel directly on the map marker.").foregroundColor(ModernTheme.success)
                } else {
                    Text("Start A selected. Confirm or cancel directly on the map marker.").foregroundColor(ModernTheme.success)
                }
            case .selectingB:
                Text("Shift-click to set \"End B\"").foregroundColor(ModernTheme.accent)
            case .confirmingB:
                Text("End B selected. Confirm or cancel directly on the map marker.").foregroundColor(ModernTheme.success)
            case .calculatingRoute:
                Text("Calculating route...").foregroundColor(ModernTheme.info)
            case .routeSelection:
                Text(vm.hasActiveRouteSnapshot ? "Choose the yellow draft route" : "Choose a route")
                    .foregroundColor(Color(red: 0.76, green: 0.62, blue: 0.15))
                Picker("Choose route", selection: $vm.selectedRouteIndex) {
                    ForEach(Array(vm.routes.enumerated()), id: \.offset) { index, route in
                        Text("Route \(index + 1) (\(String(format: "%.1f", route.distance / 1000)) km)").tag(index)
                    }
                }
                .pickerStyle(.radioGroup)
            case .readyToMove:
                Text(vm.hasActiveRouteSnapshot ? "Yellow draft is ready. You can start a new route." : "Ready")
                    .foregroundColor(vm.hasActiveRouteSnapshot ? .yellow : ModernTheme.info)
            case .moving:
                Text("Moving...").foregroundColor(ModernTheme.info)
            }
        }
        .font(.headline)
        .animation(.easeInOut, value: vm.appState)
    }
}
