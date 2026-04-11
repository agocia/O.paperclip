import CoreGraphics
import CoreLocation
import Foundation

enum JoystickDirection: String, CaseIterable, Hashable {
    case up
    case down
    case left
    case right
}

enum JoystickMotionEngine {
    private static let metersPerLatitudeDegree: CLLocationDistance = 111_320.0

    static func normalizedVector(for directions: Set<JoystickDirection>) -> CGVector {
        var dx: Double = 0
        var dy: Double = 0

        if directions.contains(.left) {
            dx -= 1
        }
        if directions.contains(.right) {
            dx += 1
        }
        if directions.contains(.up) {
            dy += 1
        }
        if directions.contains(.down) {
            dy -= 1
        }

        let magnitude = hypot(dx, dy)
        guard magnitude > 0 else { return .zero }

        return CGVector(dx: dx / magnitude, dy: dy / magnitude)
    }

    static func coordinate(
        from origin: CLLocationCoordinate2D,
        directions: Set<JoystickDirection>,
        distanceMeters: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        let vector = normalizedVector(for: directions)
        guard vector != .zero, distanceMeters.isFinite, distanceMeters > 0 else {
            return origin
        }

        return translatedCoordinate(
            from: origin,
            northMeters: vector.dy * distanceMeters,
            eastMeters: vector.dx * distanceMeters
        )
    }

    static func translatedCoordinate(
        from origin: CLLocationCoordinate2D,
        northMeters: CLLocationDistance,
        eastMeters: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        guard CLLocationCoordinate2DIsValid(origin) else { return origin }

        let latitudeRadians = origin.latitude * .pi / 180.0
        let longitudeMetersPerDegree = max(abs(cos(latitudeRadians)) * metersPerLatitudeDegree, 1.0)

        let latitudeDelta = northMeters / metersPerLatitudeDegree
        let longitudeDelta = eastMeters / longitudeMetersPerDegree

        let coordinate = CLLocationCoordinate2D(
            latitude: origin.latitude + latitudeDelta,
            longitude: origin.longitude + longitudeDelta
        )

        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : origin
    }
}
