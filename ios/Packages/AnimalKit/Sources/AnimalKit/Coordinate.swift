import Foundation

/// CoreLocation'a bağımlı olmayan enlem/boylam çifti.
public struct Coordinate: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// İki nokta arasındaki kuş uçuşu mesafe (metre). geofire-common `distanceBetween` ile aynı formül.
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let latDelta = (other.latitude - latitude) * .pi / 180
        let lonDelta = (other.longitude - longitude) * .pi / 180
        let a = sin(latDelta / 2) * sin(latDelta / 2)
            + cos(latitude * .pi / 180) * cos(other.latitude * .pi / 180)
            * sin(lonDelta / 2) * sin(lonDelta / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}
