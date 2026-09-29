import Foundation
@testable import AnimalKit

extension Coordinate {
    /// Bu noktadan `north` metre kuzeydeki ve `east` metre doğudaki nokta (`distance(to:)` ile aynı küre).
    /// Kayan nokta yüzünden uzaklık metreden milyarda bir kadar sapabilir; sınır testleri pay bırakır.
    func offset(north: Double = 0, east: Double = 0) -> Coordinate {
        let metersPerDegree = 6_371_000.0 * .pi / 180
        return Coordinate(
            latitude: latitude + north / metersPerDegree,
            longitude: longitude + east / (metersPerDegree * cos(latitude * .pi / 180))
        )
    }
}
