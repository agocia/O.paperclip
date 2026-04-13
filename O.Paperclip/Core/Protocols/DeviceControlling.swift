import Foundation
import MapKit
import Combine

protocol DeviceControlling: AnyObject {
    var connectionState: DeviceConnectionState { get }
    var logEntries: [String] { get }
    var lastSentCoordinate: CLLocationCoordinate2D? { get }
    var connectionNotice: String? { get }

    var debugLog: [String] { get }
    var isConnected: Bool { get }
    var isConnecting: Bool { get }
    var connectionStage: String { get }
    var deviceName: String { get }
    var lastError: String? { get }
    var manualRsdHost: String { get set }
    var manualRsdPort: String { get set }
    var tunnelUDID: String { get set }
    var isWirelessMode: Bool { get set }
    var objectWillChange: ObservableObjectPublisher { get }

    func connect()
    func connectDevice()
    func disconnect()
    func sendCoordinate(latitude: Double, longitude: Double)
    func sendLocationToDevice(latitude: Double, longitude: Double)
    func startContinuousLocationStream()
    func stopContinuousLocationStream()
    func clearSimulatedLocation()
    func connectDeviceAsync() async throws
    func disconnectAsync() async
    func sendLocationToDeviceAsync(latitude: Double, longitude: Double) async throws
    func clearSimulatedLocationAsync() async throws
}

extension DeviceControlling {
    var logEntries: [String] { debugLog }
    var lastSentCoordinate: CLLocationCoordinate2D? { nil }
    var connectionNotice: String? { nil }

    func connect() {
        connectDevice()
    }

    func sendCoordinate(latitude: Double, longitude: Double) {
        sendLocationToDevice(latitude: latitude, longitude: longitude)
    }

    func connectDeviceAsync() async throws {
        connectDevice()
    }

    func disconnectAsync() async {
        disconnect()
    }

    func sendLocationToDeviceAsync(latitude: Double, longitude: Double) async throws {
        sendLocationToDevice(latitude: latitude, longitude: longitude)
    }

    func clearSimulatedLocationAsync() async throws {
        clearSimulatedLocation()
    }
}
