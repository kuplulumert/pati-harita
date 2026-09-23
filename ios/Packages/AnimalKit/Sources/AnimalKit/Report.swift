import Foundation

public enum ReportStatus: String, Sendable {
    /// Yardım bekliyor.
    case open
    /// Biri "İlgileniyorum" dedi.
    case claimed
    /// Haritadan kalktı (bkz. `ClosedReason`).
    case closed
}

public enum ClosedReason: String, Sendable {
    /// Yardım edildi.
    case resolved
    /// Hayvan artık orada değil.
    case gone
    /// Kimse güncellemedi, süresi doldu.
    case expired
}

/// Bir kullanıcının işareti üstüne alması. Süresi dolunca kendiliğinden düşer.
public struct Claim: Hashable, Sendable {
    public var userID: String
    public var claimedAt: Date
    public var expiresAt: Date

    public init(userID: String, claimedAt: Date, expiresAt: Date) {
        self.userID = userID
        self.claimedAt = claimedAt
        self.expiresAt = expiresAt
    }
}

/// Haritadaki bir yardım işareti.
///
/// Değişiklikler yalnızca `ReportLifecycle` üzerinden yapılır; aynı kurallar
/// Firestore güvenlik kurallarında da uygulanır.
public struct Report: Identifiable, Hashable, Sendable {
    public let id: String
    public let species: Species
    public let need: Need
    public let coordinate: Coordinate
    public let geohash: String
    public let reporterID: String
    public let createdAt: Date

    public internal(set) var status: ReportStatus
    public internal(set) var closedReason: ClosedReason?
    /// En son "görüldüğü" an: oluşturma ya da "Hâlâ orada".
    public internal(set) var lastSeenAt: Date
    /// Bu andan sonra işaret haritada gösterilmez.
    public internal(set) var expiresAt: Date
    public internal(set) var claim: Claim?
    /// "Artık yok" diyen kullanıcılar.
    public internal(set) var goneReports: [String]
    public internal(set) var closedAt: Date?
    /// Kapanan işaretin veritabanından silineceği an (Firestore TTL).
    public internal(set) var purgeAt: Date?

    public init(
        id: String,
        species: Species,
        need: Need,
        coordinate: Coordinate,
        geohash: String,
        reporterID: String,
        createdAt: Date,
        status: ReportStatus,
        closedReason: ClosedReason?,
        lastSeenAt: Date,
        expiresAt: Date,
        claim: Claim?,
        goneReports: [String],
        closedAt: Date?,
        purgeAt: Date?
    ) {
        self.id = id
        self.species = species
        self.need = need
        self.coordinate = coordinate
        self.geohash = geohash
        self.reporterID = reporterID
        self.createdAt = createdAt
        self.status = status
        self.closedReason = closedReason
        self.lastSeenAt = lastSeenAt
        self.expiresAt = expiresAt
        self.claim = claim
        self.goneReports = goneReports
        self.closedAt = closedAt
        self.purgeAt = purgeAt
    }
}

/// Oluşturulduktan sonra değişebilen alanlar. Ham değerler Firestore alan adlarıdır.
///
/// Bir eylemden sonra yalnızca değişen alanlar yazılır: Firestore kuralları her eylem için
/// hangi alanların değişebileceğini sınırlar ve zaman damgaları Date'e çevrilip geri yazıldığında
/// mikro saniye düzeyinde kayabilir, bu da değişmemiş alanı "değişmiş" gösterirdi.
public enum ReportField: String, CaseIterable, Sendable {
    case status
    case closedReason
    case lastSeenAt
    case expiresAt
    case claimedBy
    case claimedAt
    case claimExpiresAt
    case goneReports
    case closedAt
    case purgeAt
}

/// Kullanıcıya gösterilen durum.
public enum ReportPhase: Hashable, Sendable {
    /// "Yardım bekliyor"
    case waiting
    /// "Sen ilgileniyorsun"
    case helpedByMe(until: Date)
    /// "Biri ilgileniyor"
    case helpedByOther(since: Date)
    /// Haritada gösterilmez.
    case closed(ClosedReason)
}

extension Report {
    /// Haritada gösterilmeli mi? Sunucu temizliği birkaç dakika gecikse de
    /// istemci süresi dolan işareti kendisi gizler.
    public func isActive(at now: Date) -> Bool {
        status != .closed && expiresAt > now
    }

    /// Süresi dolmamış sahiplik; `status == .claimed` olsa bile süre dolduysa `nil`.
    public func activeClaim(at now: Date) -> Claim? {
        guard status == .claimed, let claim, claim.expiresAt > now else { return nil }
        return claim
    }

    public func phase(for userID: String?, at now: Date) -> ReportPhase {
        if status == .closed { return .closed(closedReason ?? .resolved) }
        if expiresAt <= now { return .closed(.expired) }
        guard let claim = activeClaim(at: now) else { return .waiting }
        return claim.userID == userID ? .helpedByMe(until: claim.expiresAt) : .helpedByOther(since: claim.claimedAt)
    }

    /// `old` hâlinden bu hâle gelirken değişen alanlar.
    public func changedFields(from old: Report) -> Set<ReportField> {
        var fields = Set<ReportField>()
        if status != old.status { fields.insert(.status) }
        if closedReason != old.closedReason { fields.insert(.closedReason) }
        if lastSeenAt != old.lastSeenAt { fields.insert(.lastSeenAt) }
        if expiresAt != old.expiresAt { fields.insert(.expiresAt) }
        if claim?.userID != old.claim?.userID { fields.insert(.claimedBy) }
        if claim?.claimedAt != old.claim?.claimedAt { fields.insert(.claimedAt) }
        if claim?.expiresAt != old.claim?.expiresAt { fields.insert(.claimExpiresAt) }
        if goneReports != old.goneReports { fields.insert(.goneReports) }
        if closedAt != old.closedAt { fields.insert(.closedAt) }
        if purgeAt != old.purgeAt { fields.insert(.purgeAt) }
        return fields
    }

    /// 1 = az önce görüldü, 0 = süresi dolmak üzere. Haritada eski işaretleri soluklaştırmak için.
    public func freshness(at now: Date) -> Double {
        let total = expiresAt.timeIntervalSince(lastSeenAt)
        guard total > 0 else { return 0 }
        return min(1, max(0, expiresAt.timeIntervalSince(now) / total))
    }
}
