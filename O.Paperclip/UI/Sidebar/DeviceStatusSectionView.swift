import SwiftUI

struct DeviceStatusSectionView: View {
    @Bindable var vm: AppViewModel
    let isCompactSidebar: Bool
    @Binding var isWirelessMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device Status").font(.subheadline).fontWeight(.semibold).foregroundColor(ModernTheme.label)

            HStack {
                DeviceConnectionIndicator(state: vm.deviceManager.connectionState)
                Text(vm.deviceManager.deviceName)
                    .font(.subheadline)
                    .foregroundColor((vm.deviceManager.isConnected || vm.deviceManager.isConnecting) ? .primary : .secondary)
                Spacer()
                Button(action: {
                    vm.deviceManager.isConnected ? vm.deviceManager.disconnect() : vm.deviceManager.connectDevice()
                }) {
                    Text(vm.deviceManager.isConnecting ? "Connecting..." : (vm.deviceManager.isConnected ? "Disconnect" : "Connect"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vm.deviceManager.isConnecting)
            }
            .padding(10)
            .background(ModernTheme.panelRaised)
            .cornerRadius(10)
            .shadow(color: ModernTheme.shadow, radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text("Connection Mode")
                    .font(.caption)
                    .foregroundColor(ModernTheme.secondaryLabel)

                Picker("Connection Mode", selection: $isWirelessMode) {
                    Label("USB", systemImage: "cable.connector")
                        .tag(false)
                    Label("Wi‑Fi", systemImage: "wifi")
                        .tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(vm.deviceManager.isConnecting)
            }
            .padding(10)
            .background(ModernTheme.panelRaised)
            .cornerRadius(10)
            .shadow(color: ModernTheme.shadow, radius: 8, y: 3)

            if let err = vm.deviceManager.lastError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(3)
            } else if !vm.deviceManager.isConnected {
                Text(isWirelessMode
                     ? "Make sure your iPhone and Mac are on the same Wi-Fi network, then press Connect."
                     : "Plug in and unlock your iPhone, then press Connect.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !vm.deviceManager.debugLog.isEmpty && !vm.isActiveSimulationRunning {
                debugLogPanel
            }

        }
    }

    private var debugLogPanel: some View {
        let recentLines = Array(vm.deviceManager.debugLog.suffix(isCompactSidebar ? 5 : 8))

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(recentLines.indices), id: \.self) { index in
                    Text(recentLines[index])
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: isCompactSidebar ? 64 : 90)
        .padding(6)
        .background(ModernTheme.inset)
        .cornerRadius(6)
    }

}
