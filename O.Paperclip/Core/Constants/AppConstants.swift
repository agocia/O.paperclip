import CoreLocation

enum AppConstants {
    enum Timeouts {
        static let pymobiledeviceCheck: TimeInterval = 25.0
        static let rsdInfo: TimeInterval = 25.0
        static let tunnelReady: TimeInterval = 60.0
        static let mountTimeout: TimeInterval = 45.0
        static let pollInterval: TimeInterval = 0.2
        static let coordinateSend: TimeInterval = 15.0
        static let dvtStreamStop: TimeInterval = 0.1
    }
    enum Simulation {
        static let timerInterval: TimeInterval = 1.2
        static let joystickTimerInterval: TimeInterval = 0.12
        static let minimumDistance: CLLocationDistance = 2.0
        static let minimumTimeInterval: TimeInterval = 3.0
        static let joystickMinimumDistance: CLLocationDistance = 0.8
        static let joystickMinimumTimeInterval: TimeInterval = 0.35
        static let defaultSpeed: Double = 5.0
        static let maximumSpeed: Double = 300.0
        static let speedStep: Double = 0.1
        static let speedPresets: [Double] = [8.0, 18.0, 30.0, 46.0, 60.0, 150.0, 300.0]
    }
    enum Map {
        static let defaultLatitude: Double = 25.0330
        static let defaultLongitude: Double = 121.5654
        static let defaultSpanDelta: Double = 0.02
        static let minimumSpanDelta: Double = 0.0005
        static let maximumSpanDelta: Double = 180.0
    }
    enum PurePoint {
        static let viewportActivationCount = 180
        static let renderedLimit = 220
        static let viewportPadding: Double = 0.12
        static let wideSpanThreshold: Double = 0.18
    }
    enum Formatting {
        static let coordinatePrecision = "%.7f"
    }
    enum DeviceStream {
        static let ackLogInterval = 50
        static let reconnectBackoffCap: TimeInterval = 8.0
        static let healthCheckInterval: TimeInterval = 2.0
        static let healthCheckTimeout: TimeInterval = 3.0
        static let healthCheckMissingThreshold = 2
    }
    enum Search {
        static let maxCompletionResults = 12
    }
}
