import AnimalKit
import FirebaseFirestore
import Foundation

/// `Report` <-> Firestore dokümanı. Alan adları firestore.rules'taki `reportKeys()` ile aynıdır.
/// Kurallar tüm alanların her zaman bulunmasını ister; boş değerler `null` yazılır.
enum FirestoreReportMapper {
    static let collection = "reports"

    enum Field {
        static let species = "species"
        static let need = "need"
        static let lat = "lat"
        static let lng = "lng"
        static let geohash = "geohash"
        static let status = "status"
        static let closedReason = "closedReason"
        static let reporterID = "reporterId"
        static let createdAt = "createdAt"
        static let lastSeenAt = "lastSeenAt"
        static let expiresAt = "expiresAt"
        static let claimedBy = "claimedBy"
        static let claimedAt = "claimedAt"
        static let claimExpiresAt = "claimExpiresAt"
        static let goneReports = "goneReports"
        static let seenBy = "seenBy"
        static let closedAt = "closedAt"
        static let purgeAt = "purgeAt"
    }

    static func data(for report: Report) -> [String: Any] {
        [
            Field.species: report.species.rawValue,
            Field.need: report.need.rawValue,
            Field.lat: report.coordinate.latitude,
            Field.lng: report.coordinate.longitude,
            Field.geohash: report.geohash,
            Field.status: report.status.rawValue,
            Field.closedReason: nullable(report.closedReason?.rawValue),
            Field.reporterID: report.reporterID,
            Field.createdAt: Timestamp(date: report.createdAt),
            Field.lastSeenAt: Timestamp(date: report.lastSeenAt),
            Field.expiresAt: Timestamp(date: report.expiresAt),
            Field.claimedBy: nullable(report.claim?.userID),
            Field.claimedAt: nullable(report.claim.map { Timestamp(date: $0.claimedAt) }),
            Field.claimExpiresAt: nullable(report.claim.map { Timestamp(date: $0.expiresAt) }),
            Field.goneReports: report.goneReports,
            Field.seenBy: report.seenBy,
            Field.closedAt: nullable(report.closedAt.map { Timestamp(date: $0) }),
            Field.purgeAt: nullable(report.purgeAt.map { Timestamp(date: $0) }),
        ]
    }

    /// Bir eylemden sonra yalnızca değişen alanlar. Değişmemiş zaman damgalarını geri yazmak
    /// (Date'e çevirip tekrar Timestamp yapmak) mikro saniye kaydırıp kuralları bozardı.
    static func changes(from old: Report, to updated: Report) -> [String: Any] {
        let changed = Set(updated.changedFields(from: old).map(\.rawValue))
        return data(for: updated).filter { changed.contains($0.key) }
    }

    /// Tanınmayan ya da eksik alanlı dokümanlar (ör. eski sürüm) `nil` döner ve haritada gösterilmez.
    static func report(id: String, data: [String: Any]) -> Report? {
        guard
            let species = (data[Field.species] as? String).flatMap(Species.init(rawValue:)),
            let need = (data[Field.need] as? String).flatMap(Need.init(rawValue:)),
            let latitude = data[Field.lat] as? Double,
            let longitude = data[Field.lng] as? Double,
            let geohash = data[Field.geohash] as? String,
            let status = (data[Field.status] as? String).flatMap(ReportStatus.init(rawValue:)),
            let reporterID = data[Field.reporterID] as? String,
            let createdAt = date(data[Field.createdAt]),
            let lastSeenAt = date(data[Field.lastSeenAt]),
            let expiresAt = date(data[Field.expiresAt])
        else { return nil }

        var claim: Claim?
        if let userID = data[Field.claimedBy] as? String,
           let claimedAt = date(data[Field.claimedAt]),
           let claimExpiresAt = date(data[Field.claimExpiresAt]) {
            claim = Claim(userID: userID, claimedAt: claimedAt, expiresAt: claimExpiresAt)
        }

        return Report(
            id: id,
            species: species,
            need: need,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            geohash: geohash,
            reporterID: reporterID,
            createdAt: createdAt,
            status: status,
            closedReason: (data[Field.closedReason] as? String).flatMap(ClosedReason.init(rawValue:)),
            lastSeenAt: lastSeenAt,
            expiresAt: expiresAt,
            claim: claim,
            goneReports: data[Field.goneReports] as? [String] ?? [],
            // "Kaç kişi bildirdi" öncesinden kalan dokümanda alan yok: yalnızca işareti koyan bildirmiş sayılır.
            seenBy: data[Field.seenBy] as? [String] ?? [reporterID],
            closedAt: date(data[Field.closedAt]),
            purgeAt: date(data[Field.purgeAt])
        )
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? Timestamp)?.dateValue()
    }

    private static func nullable(_ value: Any?) -> Any {
        value ?? NSNull()
    }
}
