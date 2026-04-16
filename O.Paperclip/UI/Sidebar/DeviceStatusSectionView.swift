import Combine
import SwiftUI

struct DeviceStatusSectionView: View {
    @Bindable var vm: AppViewModel
    let isCompactSidebar: Bool
    @Binding var isWirelessMode: Bool
    @State private var debugLogLines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("裝置狀態").font(.subheadline).fontWeight(.semibold).foregroundColor(ModernTheme.label)

            HStack {
                DeviceConnectionIndicator(state: vm.deviceManager.connectionState)
                Text(vm.deviceManager.deviceName)
                    .font(.subheadline)
                    .foregroundColor((vm.deviceManager.isConnected || vm.deviceManager.isConnecting) ? .primary : .secondary)
                Spacer()
                Button(action: {
                    vm.deviceManager.isConnected ? vm.deviceManager.disconnect() : vm.deviceManager.connectDevice()
                }) {
                    Text(vm.deviceManager.isConnecting ? "連線中…" : (vm.deviceManager.isConnected ? "中斷連線" : "開始連線"))
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
                Text("連線模式")
                    .font(.caption)
                    .foregroundColor(ModernTheme.secondaryLabel)

                Picker("連線模式", selection: $isWirelessMode) {
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
                     ? "確保 iPhone 與 Mac 在同一個 Wi‑Fi 網路，按下開始連線。"
                     : "先插上手機並解鎖，按下開始連線即可。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let notice = vm.deviceManager.connectionNotice, !notice.isEmpty {
                Text(notice)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !debugLogLines.isEmpty && !vm.isActiveSimulationRunning {
                debugLogPanel
            }

        }
        .onAppear {
            if debugLogLines != vm.deviceManager.debugLog {
                debugLogLines = vm.deviceManager.debugLog
            }
        }
        .onReceive(vm.deviceManager.debugLogPublisher.receive(on: RunLoop.main)) { lines in
            debugLogLines = lines
        }
    }

    private var debugLogPanel: some View {
        let recentLines = Array(debugLogLines.suffix(isCompactSidebar ? 5 : 8))

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
