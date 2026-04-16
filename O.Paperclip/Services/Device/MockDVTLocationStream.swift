import Foundation

final class MockDVTLocationStream: DVTStreaming {
    var isRunning: Bool = false
    var sentCoordinates: [(latitude: Double, longitude: Double)] = []
    var shouldThrowOnStart = false
    var shouldThrowOnSend = false
    var startCallCount = 0
    var stopCallCount = 0
    var clearCallCount = 0
    var lastHost: String?
    var lastPort: String?
    private var onExitHandler: (@Sendable (Int32) -> Void)?

    func start(
        host: String,
        port: String,
        onOutput: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws {
        if shouldThrowOnStart {
            throw NSError(domain: "MockDVTLocationStream", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "mock start error"
            ])
        }
        startCallCount += 1
        lastHost = host
        lastPort = port
        isRunning = true
        onExitHandler = onExit
    }

    func send(latitude: Double, longitude: Double) throws {
        if shouldThrowOnSend {
            throw NSError(domain: "MockDVTLocationStream", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "mock send error"
            ])
        }
        sentCoordinates.append((latitude: latitude, longitude: longitude))
    }

    func clear() {
        clearCallCount += 1
    }

    func stop() {
        stopCallCount += 1
        isRunning = false
        onExitHandler = nil
    }

    func simulateUnexpectedExit(_ status: Int32) {
        isRunning = false
        onExitHandler?(status)
    }
}
