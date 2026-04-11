import SwiftUI

enum OperationMode: String, CaseIterable, Identifiable {
    case routeAB = "A-B"
    case fixedPoint = "定點"
    case multiPoint = "多點"
    case joystick = "搖桿"
    case fixedRoute = "固定路線"

    var id: String { rawValue }
}

enum DeviceConnectionState: Equatable {
    case disconnected
    case connecting(step: String)
    case connected
    case failed

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var isBusy: Bool {
        if case .connecting = self {
            return true
        }
        return false
    }

    var statusText: String {
        switch self {
        case .disconnected:
            return "尚未連線"
        case .connecting(let step):
            return Self.userFacingStepText(step)
        case .connected:
            return "已連線"
        case .failed:
            return "暫時無法連線"
        }
    }

    private static func userFacingStepText(_ step: String) -> String {
        let normalized = step.lowercased()

        if normalized.contains("重連") {
            return "正在重新連線"
        }
        if step.contains("使用手動 RSD") {
            return "正在使用手動連線設定"
        }
        if step.contains("搜尋 Wi‑Fi 裝置") || step.contains("初始化") || step.contains("檢查") || step.contains("偵測連線裝置") {
            return "正在尋找你的裝置"
        }
        if step.contains("改用 USB") {
            return "正在切換為更穩定的連線方式"
        }
        if step.contains("建立") || step.contains("等待") {
            return "正在建立連線"
        }
        if step.contains("驗證") || step.contains("掛載") || step.contains("讀取") || step.contains("simulate-location") {
            return "正在準備裝置"
        }

        return "正在連線"
    }
}

