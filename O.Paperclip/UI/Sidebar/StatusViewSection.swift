import SwiftUI
import MapKit

struct StatusViewSection: View {
    @Bindable var vm: AppViewModel
    let routeColors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vm.hasActiveRouteSnapshot {
                activeStatusText
                    .foregroundColor(ModernTheme.info)
            }

            switch vm.appState {
            case .selectingA:
                if vm.operationMode == .multiPoint {
                    Text("Shift + 點擊新增路線點（至少 2 點）").foregroundColor(ModernTheme.accent)
                } else if vm.operationMode == .joystick {
                    Text("Shift + 點擊設定搖桿起點").foregroundColor(ModernTheme.accent)
                } else if vm.operationMode == .fixedPoint {
                    Text("Shift + 點擊設定定位點").foregroundColor(ModernTheme.accent)
                } else if vm.operationMode == .fixedRoute {
                    Text("請到右側欄位匯入或選擇固定路線").foregroundColor(ModernTheme.accent)
                } else {
                    Text("Shift + 點擊設定「起點 A」").foregroundColor(ModernTheme.accent)
                }
            case .confirmingA:
                if vm.operationMode == .joystick {
                    Text("已選擇搖桿起點，請在地圖標記上直接確認/取消").foregroundColor(ModernTheme.success)
                } else if vm.operationMode == .fixedPoint {
                    Text("已選擇定位點，請在地圖標記上直接確認/取消").foregroundColor(ModernTheme.success)
                } else {
                    Text("已選擇起點 A，請在地圖標記上直接確認/取消").foregroundColor(ModernTheme.success)
                }
            case .selectingB:
                Text("Shift + 點擊設定「終點 B」").foregroundColor(ModernTheme.accent)
            case .confirmingB:
                Text("已選擇終點 B，請在地圖標記上直接確認/取消").foregroundColor(ModernTheme.success)
            case .calculatingRoute:
                Text("計算路線中...").foregroundColor(ModernTheme.info)
            case .routeSelection:
                Text(vm.hasActiveRouteSnapshot ? "選擇黃色草稿路線" : "選擇一條路線")
                    .foregroundColor(Color(red: 0.76, green: 0.62, blue: 0.15))
                Picker("選擇路線", selection: $vm.selectedRouteIndex) {
                    ForEach(Array(vm.routes.enumerated()), id: \.offset) { index, route in
                        Text("路線 \(index + 1) (\(String(format: "%.1f", route.distance / 1000)) km)").tag(index)
                    }
                }
                .pickerStyle(.radioGroup)
            case .readyToMove:
                readyStatusText
                    .foregroundColor(vm.hasActiveRouteSnapshot ? .yellow : ModernTheme.info)
            case .moving:
                movingStatusText
                    .foregroundColor(ModernTheme.info)
            }
        }
        .font(.headline)
        .animation(.easeInOut, value: vm.appState)
    }

    private var activeStatusText: Text {
        switch vm.activeOperationMode {
        case .joystick:
            return Text(vm.activeJoystickDirections.isEmpty ? "搖桿已啟用" : "搖桿同步中")
        case .fixedPoint:
            return Text(vm.isActiveSimulationRunning ? "定位中" : "定位已固定")
        case .fixedRoute:
            return Text(vm.isActiveSimulationRunning ? "固定路線同步中" : "固定路線已固定")
        case .routeAB, .multiPoint:
            return Text(vm.isActiveSimulationRunning ? "藍線路線同步中" : "藍線路線已固定")
        }
    }

    private var readyStatusText: Text {
        if vm.hasActiveRouteSnapshot {
            return Text("黃色草稿已完成，可開始新路線")
        }

        switch vm.operationMode {
        case .joystick:
            return Text("搖桿已就緒，開始後可用方向鍵或 WASD 控制")
        case .fixedRoute:
            return Text("固定路線已就緒")
        case .routeAB, .fixedPoint, .multiPoint:
            return Text("準備就緒")
        }
    }

    private var movingStatusText: Text {
        switch vm.activeOperationMode {
        case .joystick:
            return Text(vm.activeJoystickDirections.isEmpty ? "搖桿已啟用，等待輸入" : "搖桿移動中...")
        case .fixedRoute:
            return Text("沿固定路線移動中...")
        case .fixedPoint, .routeAB, .multiPoint:
            return Text("移動中...")
        }
    }
}
