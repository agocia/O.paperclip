import SwiftUI

enum OperationMode: String, CaseIterable, Identifiable {
    case routeAB = "A-B"
    case fixedPoint = "Pin"
    case multiPoint = "Multi-point"

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
            return "Not connected"
        case .connecting(let step):
            return Self.userFacingStepText(step)
        case .connected:
            return "Connected"
        case .failed:
            return "Connection unavailable"
        }
    }

    private static func userFacingStepText(_ step: String) -> String {
        let normalized = step.lowercased()

        if normalized.contains("reconnect") {
            return "Reconnecting"
        }
        if normalized.contains("manual rsd") {
            return "Using manual connection settings"
        }
        if normalized.contains("search")
            || normalized.contains("initial")
            || normalized.contains("check")
            || normalized.contains("detect connected device") {
            return "Looking for your device"
        }
        if normalized.contains("switch to usb") {
            return "Switching to a more stable connection"
        }
        if normalized.contains("build") || normalized.contains("wait") {
            return "Establishing connection"
        }
        if normalized.contains("verify")
            || normalized.contains("mount")
            || normalized.contains("read")
            || normalized.contains("simulate-location") {
            return "Preparing device"
        }

        return "Connecting"
    }
}

