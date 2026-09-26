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
        let closeCost: Int
        let demoteMinutes: Int
    }

    struct CreateQuotaContract: Decodable {
        let perWindow: Int
        let firstDay: Int
    }

    struct CloseBudgetContract: Decodable {
        let points: Int
        let maxDisputed: Int
    }

    struct ClosingDisplayContract: Decodable {
        let dayStartHour: Int
        let dayEndHour: Int
        let utcOffsetHours: Int
        let streetDotMaxRadiusMeters: Double
        let closerUndoToastSeconds: Double
        let modes: [String]
        let defaultMode: String
    }

    let species: [String]
    let statuses: [String]
    let needs: [String: NeedContract]
    let claimHours: Int
    let claimStaleMinutes: Int
    let undoMinutes: Int
    let goneThreshold: Int
    let maxSeenBy: Int
    let maxDisputed: Int
    let maxReportAgeDays: Int
    let retentionDays: Int
    let clockSkewMinutes: Int
    let geohashPrecision: Int
    let newAccountHours: Int
    let budgetWindowHours: Int
    let createQuota: CreateQuotaContract
    let closeBudget: CloseBudgetContract
    let closingDisplay: ClosingDisplayContract
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
