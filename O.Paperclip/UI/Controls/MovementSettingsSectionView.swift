import SwiftUI

struct MovementSettingsSectionView: View {
    @Bindable var vm: AppViewModel
    @Binding var speedText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movement Settings").font(.subheadline).fontWeight(.semibold).foregroundColor(ModernTheme.label)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Current speed: \(String(format: "%.1f", vm.speed)) km/h")
                    if !vm.routes.isEmpty || vm.totalRouteDistance > 0 {
                        Text("One-way: \(vm.estimatedTime)")
                            .foregroundColor(ModernTheme.info)
                    }
                }
                .font(.callout)
                Slider(
                    value: $vm.speed,
                    in: AppConstants.Simulation.speedStep...vm.maximumSpeed,
                    step: AppConstants.Simulation.speedStep
                )
                HStack(spacing: 8) {
                    TextField("Speed", text: $speedText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 88)

                    Stepper(
                        "Fine tune 0.1",
                        value: $vm.speed,
                        in: AppConstants.Simulation.speedStep...vm.maximumSpeed,
                        step: AppConstants.Simulation.speedStep
                    )
                    .fixedSize()
                }
            }

            Toggle("Ping-pong loop", isOn: $vm.isEndlessLoop)
                .tint(ModernTheme.accent)
                .disabled(vm.operationMode == .multiPoint && vm.isClosedLoop)

            if vm.operationMode == .multiPoint {
                Text(
                    vm.isClosedLoop
                        ? "Closed loop is enabled, so the route keeps circling and ping-pong loop is turned off automatically."
                        : "Ping-pong loop makes an open route return along the same path from the end point."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            if vm.operationMode == .multiPoint {
                multiPointWaypointControls
                Toggle("Closed loop (connect last point back to P1)", isOn: $vm.isClosedLoop)
                    .tint(ModernTheme.accent)
                    .disabled(vm.appState != .selectingA && vm.appState != .readyToMove)
            }

        }
    }

    private var multiPointWaypointControls: some View {
        HStack {
            Text("Waypoint count: \(vm.waypoints.count)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Remove last point") {
                if !vm.waypoints.isEmpty { vm.waypoints.removeLast() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(vm.waypoints.isEmpty || vm.appState != .selectingA)
        }
    }

}
