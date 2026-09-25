import AnimalKit
import FirebaseFirestore
import Foundation

/// `Report` / `UserRecord` <-> Firestore dokümanı. Alan adları firestore.rules'taki `reportKeys()` ve
/// `userKeys()` ile aynıdır. Kurallar tüm alanların her zaman bulunmasını ister; boş değerler `null` yazılır.
enum FirestoreReportMapper {
    static let collection = "reports"
    static let usersCollection = "users"
    static let configCollection = "config"
    /// `config/public`: yalnızca konsoldan yazılır.
    static let publicConfigDocument = "public"
    static let closingModeField = "closingMode"

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
        static let closingReason = "closingReason"
        static let closingBy = "closingBy"
        static let closingAt = "closingAt"
        static let closingCredible = "closingCredible"
        static let objectors = "objectors"
        static let disputed = "disputed"
    }

    enum UserField {
        static let createdAt = "createdAt"
        static let createWindow = "createWindow"
        static let createUsed = "createUsed"
        static let createLast = "createLast"
        static let closeWindow = "closeWindow"
        static let closeUsed = "closeUsed"
        static let closeLast = "closeLast"
        /// `createLast` / `closeLast` içindekiler: harcama anı (sunucu saati), işaret, puan.
        static let spentAt = "t"
        static let reportID = "id"
        static let points = "w"
    }

    // MARK: İşaret

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
            Field.closingReason: nullable(report.closing?.reason.rawValue),
            Field.closingBy: nullable(report.closing?.userID),
            Field.closingAt: nullable(report.closing.map { Timestamp(date: $0.at) }),
            Field.closingCredible: nullable(report.closing?.credible),
            Field.objectors: report.objectors,
            Field.disputed: report.disputed,
        ]
    }

    /// Bir eylemden sonra yalnızca değişen alanlar. Değişmemiş zaman damgalarını geri yazmak
    /// (Date'e çevirip tekrar Timestamp yapmak) mikro saniye kaydırıp kuralları bozardı.
    static func changes(from old: Report, to updated: Report) -> [String: Any] {
        let changed = Set(updated.changedFields(from: old).map(\.rawValue))
        var fields = data(for: updated).filter { changed.contains($0.key) }
        // Kurallar bu iki anı sunucu saatine eşit ister (== request.time): 45 dk'lık sahiplik ve
        // 10 dk'lık "Geri al" süreleri istemci saatiyle sahte bir zaman çizelgesine dayanamasın.
        if changed.contains(Field.claimedAt), updated.claim != nil {
            fields[Field.claimedAt] = FieldValue.serverTimestamp()
        }
        if changed.contains(Field.closingAt), updated.closing != nil {
            fields[Field.closingAt] = FieldValue.serverTimestamp()
        }
        return fields
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

        let closing = self.closing(from: data)
        // "… dendi" dokümanında öneri alanları eksikse (kurallar izin vermez) eylemler yanlış hâle
        // uygulanmasın diye gösterilmez.
        if status == .closing && closing == nil { return nil }

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
            purgeAt: date(data[Field.purgeAt]),
            closing: closing,
            objectors: data[Field.objectors] as? [String] ?? [],
            disputed: data[Field.disputed] as? [String] ?? []
        )
    }

    /// Öneri dörtlüsü: ya hepsi dolu ya hepsi boş (kurallardaki `validShape`).
    private static func closing(from data: [String: Any]) -> Closing? {
        guard
            let reason = (data[Field.closingReason] as? String).flatMap(ClosedReason.init(rawValue:)),
            reason != .expired,
            let userID = data[Field.closingBy] as? String,
            let at = date(data[Field.closingAt]),
            let credible = data[Field.closingCredible] as? Bool
        else { return nil }
        return Closing(reason: reason, userID: userID, at: at, credible: credible)
    }

    // MARK: users/{uid}

    /// Anonim girişten sonraki ilk kayıt. Kurallar üç anın da sunucu saati (`request.time`) olmasını ister.
    static func newUserData() -> [String: Any] {
        [
            UserField.createdAt: FieldValue.serverTimestamp(),
            UserField.createWindow: FieldValue.serverTimestamp(),
            UserField.createUsed: 0,
            UserField.createLast: NSNull(),
            UserField.closeWindow: FieldValue.serverTimestamp(),
            UserField.closeUsed: 0,
            UserField.closeLast: NSNull(),
        ]
    }

    /// Yeni işaretle aynı toplu yazımda: bu işaret için bir hak. Kural `createLast`i getAfter ile
    /// bu an ve bu işaretle eşleştirir; tek harcama iki işarete yetmez.
    static func createSpend(reportID: String, branch: BudgetSpend) -> [String: Any] {
        let last: [String: Any] = [
            UserField.spentAt: FieldValue.serverTimestamp(),
            UserField.reportID: reportID,
        ]
        var fields: [String: Any] = [UserField.createLast: last]
        switch branch {
        case .sameWindow:
            // Çevrimdışıyken de doğru: sayaç sunucudaki değer üstüne artar.
            fields[UserField.createUsed] = FieldValue.increment(Int64(1))
        case .newWindow:
            fields[UserField.createWindow] = FieldValue.serverTimestamp()
            fields[UserField.createUsed] = 1
        }
        return fields
    }

    /// Kanıtlı öneriyle aynı işlemde: bu işaret için `spend.cost` puan.
    static func closeSpend(reportID: String, spend: CloseDecision.Spend) -> [String: Any] {
        let last: [String: Any] = [
            UserField.spentAt: FieldValue.serverTimestamp(),
            UserField.reportID: reportID,
            UserField.points: spend.cost,
        ]
        var fields: [String: Any] = [UserField.closeLast: last]
        switch spend.branch {
        case .sameWindow:
            fields[UserField.closeUsed] = FieldValue.increment(Int64(spend.cost))
        case .newWindow:
            fields[UserField.closeWindow] = FieldValue.serverTimestamp()
            fields[UserField.closeUsed] = spend.cost
        }
        return fields
    }

    /// Eksik alanlı kayıt `nil` döner: hak bilinmiyor sayılır, sunucu karar verir.
    static func userRecord(data: [String: Any]) -> UserRecord? {
        guard
            let createdAt = date(data[UserField.createdAt]),
            let createWindow = date(data[UserField.createWindow]),
            let createUsed = int(data[UserField.createUsed]),
            let closeWindow = date(data[UserField.closeWindow]),
            let closeUsed = int(data[UserField.closeUsed])
        else { return nil }
        return UserRecord(
            createdAt: createdAt,
            createWindow: createWindow,
            createUsed: createUsed,
            closeWindow: closeWindow,
            closeUsed: closeUsed
        )
    }

    // MARK: config/public

    static func closingMode(data: [String: Any]?) -> ClosingMode {
        (data?[closingModeField] as? String).flatMap(ClosingMode.init(rawValue:)) ?? .fallback
    }

    // MARK: Yardımcılar

    private static func date(_ value: Any?) -> Date? {
        (value as? Timestamp)?.dateValue()
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func nullable(_ value: Any?) -> Any {
        value ?? NSNull()
    }
}
