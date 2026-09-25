import Foundation

/// Depo kökündeki shared/ klasöründeki, Firebase tarafıyla ortak dosyalar.
enum SharedFixtures {
    static let sharedDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AnimalKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // AnimalKit
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // depo kökü
        .appendingPathComponent("shared")

    static func load<T: Decodable>(_ fileName: String, as type: T.Type = T.self) throws -> T {
        let data = try Data(contentsOf: sharedDirectory.appendingPathComponent(fileName))
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct ReportContract: Decodable {
    struct NeedContract: Decodable {
        let lifetimeHours: Int
    }

    let species: [String]
    let needs: [String: NeedContract]
    let claimHours: Int
    let goneThreshold: Int
    let maxSeenBy: Int
    let retentionDays: Int
    let geohashPrecision: Int
}

struct GeohashVectors: Decodable {
    struct Encode: Decodable {
        let name: String
        let lat: Double
        let lng: Double
        let precision: Int
        let geohash: String
    }

    struct QueryBounds: Decodable {
        let name: String
        let lat: Double
        let lng: Double
        let radiusMeters: Double
        let bounds: [[String]]
    }

    struct Distance: Decodable {
        let from: [Double]
        let to: [Double]
        let meters: Double
    }

    let encode: [Encode]
    let queryBounds: [QueryBounds]
    let distances: [Distance]
}
