import XCTest
@testable import AnimalKit

/// Referans değerler geofire-common ile üretildi (bkz. firebase/tests/contract.test.ts).
final class GeohashTests: XCTestCase {
    private var vectors: GeohashVectors!

    override func setUpWithError() throws {
        vectors = try SharedFixtures.load("geohash-vectors.json", as: GeohashVectors.self)
    }

    func testEncodeMatchesGeofire() {
        for vector in vectors.encode {
            let coordinate = Coordinate(latitude: vector.lat, longitude: vector.lng)
            XCTAssertEqual(Geohash.encode(coordinate, precision: vector.precision), vector.geohash, vector.name)
        }
    }

    func testQueryBoundsMatchGeofire() {
        for vector in vectors.queryBounds {
            let center = Coordinate(latitude: vector.lat, longitude: vector.lng)
            let expected = vector.bounds.map { GeohashRange(start: $0[0], end: $0[1]) }
            XCTAssertEqual(
                Geohash.queryBounds(center: center, radiusMeters: vector.radiusMeters),
                expected,
                "\(vector.name) @ \(vector.radiusMeters) m"
            )
        }
    }

    func testDistanceMatchesGeofire() {
        for vector in vectors.distances {
            let from = Coordinate(latitude: vector.from[0], longitude: vector.from[1])
            let to = Coordinate(latitude: vector.to[0], longitude: vector.to[1])
            XCTAssertEqual(from.distance(to: to), vector.meters, accuracy: 0.001)
        }
    }

    func testQueryBoundsCoverThePointItself() {
        let center = Coordinate(latitude: 40.9903, longitude: 29.029)
        let hash = Geohash.encode(center)
        let ranges = Geohash.queryBounds(center: center, radiusMeters: 500)
        XCTAssertTrue(ranges.contains { $0.start <= hash && hash < $0.end })
    }
}
