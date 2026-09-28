import Foundation

public enum ReportStatus: String, CaseIterable, Sendable {
    /// Yardım bekliyor.
    case open
    /// Biri "İlgileniyorum" dedi.
    case claimed
    /// Biri "Çözüldü", "Artık yok" ya da "Yardım gerekmiyor" dedi ("… dendi"). Haritada kalır, ömrü kısalmaz;
    /// ikinci bir kişi onaylayana, itiraz edilene, geri alınana ya da süresi dolana kadar (bkz. `Closing`).
    case closing
    /// Haritadan kalktı (bkz. `ClosedReason`).
    case closed
}

public enum ClosedReason: String, CaseIterable, Sendable {
    /// Yardım edildi.
    case resolved
    /// Hayvan artık orada değil.
    case gone
    /// Kimse güncellemedi, süresi doldu.
    case expired
    /// "Hayvan orada ama iyi görünüyor": yardım gerekmiyordu (yalnızca mama işaretleri; "Yanlış alarmdı").
    case unneeded

    /// "… dendi" önerisinin nedeni olabilir mi? `expired` yalnızca süre dolunca yazılır.
    public var canBeProposed: Bool {
        switch self {
        case .resolved, .gone, .unneeded: true
        case .expired: false
        }
    }
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

/// "Çözüldü dendi" / "Artık yok dendi" / "Yardım gerekmiyor dendi": henüz doğrulanmamış kapatma önerisi.
///
/// İşaret kapanınca (`closed`) geçmiş olarak kalır; itiraz ya da "Geri al" ile silinir.
public struct Closing: Hashable, Sendable {
    /// `.resolved`, `.gone` ya da `.unneeded` (bkz. `ClosedReason.canBeProposed`).
    public var reason: ClosedReason
    /// Öneriyi yapan kullanıcı.
    public var userID: String
    /// Firestore'a sunucu saati (`serverTimestamp()`) yazılır; kurallar `== request.time` ister.
    public var at: Date
    /// Kapatanın günlük bütçesiyle desteklendi mi (bkz. `Budget`, `ClosingDisplay`).
    public var credible: Bool
    /// Bu sürümün tanımadığı öneri nedeni (daha yeni bir sürüm yazdı); tanınıyorsa `nil`. Doluysa `reason`
    /// yalnızca yer tutucudur: arayüz genel bir "… dendi" gösterir ve bu sürüm öneriyi onaylayamaz ya da
    /// süresi dolunca kapatamaz (kurallar kapanışta aynı nedeni ister). İtiraz ve "Geri al" nedenden bağımsızdır.
    public var unrecognizedReason: String?

    public init(reason: ClosedReason, userID: String, at: Date, credible: Bool, unrecognizedReason: String? = nil) {
        self.reason = reason
        self.userID = userID
        self.at = at
        self.credible = credible
        self.unrecognizedReason = unrecognizedReason
    }
}

/// Haritadaki bir yardım işareti.
///
/// Değişiklikler yalnızca `ReportLifecycle` üzerinden yapılır; aynı kurallar
/// Firestore güvenlik kurallarında da uygulanır.
public struct Report: Identifiable, Hashable, Sendable {
    public let id: String
    /// Tür, ihtiyaç ve konum yalnızca işareti koyanın düzeltmesiyle değişir (`ReportLifecycle.edit`).
    public internal(set) var species: Species
    public internal(set) var need: Need
    public internal(set) var coordinate: Coordinate
    /// Konumla birlikte istemcide yeniden hesaplanır.
    public internal(set) var geohash: String
    public let reporterID: String
    public let createdAt: Date

    public internal(set) var status: ReportStatus
    /// `closed` iken dolu. Bu sürümün tanımadığı neden (ör. sahibin konsoldan yazdığı 'removed') `nil` okunur;
    /// işaret yine kapalıdır.
    public internal(set) var closedReason: ClosedReason?
    /// En son "görüldüğü" an: oluşturma ya da "Hâlâ orada".
    public internal(set) var lastSeenAt: Date
    /// Bu andan sonra işaret haritada gösterilmez.
    public internal(set) var expiresAt: Date
    /// `closing` sırasında da dokümanda kalır (kartta zaman çizelgesi için); canlı sayılmaz.
    public internal(set) var claim: Claim?
    /// "Artık yok" diyen kullanıcılar.
    public internal(set) var goneReports: [String]
    /// Hayvanı gören farklı kullanıcılar: önce işareti koyan, sonra "Hâlâ orada" diyenler
    /// (en fazla `ReportLifecycle.maxSeenBy`).
    public internal(set) var seenBy: [String]
    public internal(set) var closedAt: Date?
    /// Kapanan işaretin veritabanından silineceği an (Firestore TTL).
    public internal(set) var purgeAt: Date?
    /// `status == .closing` iken dolu; `closed` olunca geçmiş olarak kalabilir.
    public internal(set) var closing: Closing?
    /// "Hâlâ yardım gerekiyor" diyen, işareti koyan dışındaki kullanıcılar (her biri bir kez).
    public internal(set) var objectors: [String]
    /// Kapatma önerisine itiraz edilen kullanıcılar: bu işareti bir daha üstüne alamaz, kapatamazlar.
    public internal(set) var disputed: [String]
    /// İşareti koyanın kaç kez düzelttiği (en fazla `ReportLifecycle.maxEdits`).
    public internal(set) var editCount: Int

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
        seenBy: [String],
        closedAt: Date?,
        purgeAt: Date?,
        closing: Closing? = nil,
        objectors: [String] = [],
        disputed: [String] = [],
        editCount: Int = 0
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
        self.seenBy = seenBy
        self.closedAt = closedAt
        self.purgeAt = purgeAt
        self.closing = closing
        self.objectors = objectors
        self.disputed = disputed
        self.editCount = editCount
    }
}

/// Oluşturulduktan sonra değişebilen alanlar. Ham değerler Firestore alan adlarıdır.
///
/// Bir eylemden ya da düzeltmeden sonra yalnızca değişen alanlar yazılır: Firestore kuralları her eylem
/// için hangi alanların değişebileceğini sınırlar ve zaman damgaları Date'e çevrilip geri yazıldığında
/// mikro saniye düzeyinde kayabilir, bu da değişmemiş alanı "değişmiş" gösterirdi.
/// Tür, ihtiyaç, konum (`lat`, `lng`, `geohash`) ve `editCount` yalnızca düzeltmede değişir.
public enum ReportField: String, CaseIterable, Sendable {
    case species
    case need
    case lat
    case lng
    case geohash
    case status
    case closedReason
    case lastSeenAt
    case expiresAt
    case claimedBy
    case claimedAt
    case claimExpiresAt
    case goneReports
    case seenBy
    case closedAt
    case purgeAt
    case closingReason
    case closingBy
    case closingAt
    case closingCredible
    case objectors
    case disputed
    case editCount
}

/// Kullanıcıya gösterilen durum.
public enum ReportPhase: Hashable, Sendable {
    /// "Yardım bekliyor"
    case waiting
    /// "Sen ilgileniyorsun"
    case helpedByMe(until: Date)
    /// "Biri ilgileniyor"
    case helpedByOther(since: Date)
    /// "Çözüldü dendi" / "Artık yok dendi" / "Yardım gerekmiyor dendi": haritada kalır.
    /// `byMe`: öneriyi bu kullanıcı yaptı.
    case closing(reason: ClosedReason, since: Date, byMe: Bool, credible: Bool)
    /// Haritada gösterilmez.
    case closed(ClosedReason)
}

extension Report {
    /// Haritada gösterilmeli mi? Sunucu temizliği birkaç dakika gecikse de
    /// istemci süresi dolan işareti kendisi gizler. "Çözüldü dendi" işaretleri de aktiftir.
    public func isActive(at now: Date) -> Bool {
        status != .closed && expiresAt > now
    }

    /// Açık ya da üstüne alınmış ve süresi dolmamış: "İlgileniyorum", "Hâlâ orada" gibi eylemlere açık.
    public func isWaiting(at now: Date) -> Bool {
        (status == .open || status == .claimed) && expiresAt > now
    }

    /// Hayvanı kaç farklı kişinin bildirdiği ("3 kişi bildirdi"). İşareti koyan da sayılır.
    public var seenCount: Int { seenBy.count }

    /// Süresi dolmamış sahiplik; `status == .claimed` olsa bile süre dolduysa `nil`.
    public func activeClaim(at now: Date) -> Claim? {
        guard status == .claimed, let claim, claim.expiresAt > now else { return nil }
        return claim
    }

    /// Canlı sahiplik `ReportLifecycle.claimStale` süresini doldurdu mu? O zaman başkaları da
    /// "Çözüldü" diyebilir, işareti koyan sahipliği kaldırabilir ve işaret yeniden yardım bekleyen sayılır.
    public func isClaimStale(at now: Date) -> Bool {
        guard let claim = activeClaim(at: now) else { return false }
        return now >= claim.claimedAt.addingTimeInterval(ReportLifecycle.claimStale)
    }

    public func phase(for userID: String?, at now: Date) -> ReportPhase {
        if status == .closed { return .closed(closedReason ?? .resolved) }
        if expiresAt <= now {
            // Süresi dolan öneri, önerildiği nedenle kapanır (kurallardaki isExpire gibi).
            let reason: ClosedReason = status == .closing ? (closing?.reason ?? .expired) : .expired
            return .closed(reason)
        }
        if status == .closing, let closing {
            return .closing(
                reason: closing.reason,
                since: closing.at,
                byMe: closing.userID == userID,
                credible: closing.credible
            )
        }
        guard let claim = activeClaim(at: now) else { return .waiting }
        return claim.userID == userID ? .helpedByMe(until: claim.expiresAt) : .helpedByOther(since: claim.claimedAt)
    }

    /// `old` hâlinden bu hâle gelirken değişen alanlar.
    public func changedFields(from old: Report) -> Set<ReportField> {
        var fields = Set<ReportField>()
        if species != old.species { fields.insert(.species) }
        if need != old.need { fields.insert(.need) }
        if coordinate.latitude != old.coordinate.latitude { fields.insert(.lat) }
        if coordinate.longitude != old.coordinate.longitude { fields.insert(.lng) }
        if geohash != old.geohash { fields.insert(.geohash) }
        if status != old.status { fields.insert(.status) }
        if closedReason != old.closedReason { fields.insert(.closedReason) }
        if lastSeenAt != old.lastSeenAt { fields.insert(.lastSeenAt) }
        if expiresAt != old.expiresAt { fields.insert(.expiresAt) }
        if claim?.userID != old.claim?.userID { fields.insert(.claimedBy) }
        if claim?.claimedAt != old.claim?.claimedAt { fields.insert(.claimedAt) }
        if claim?.expiresAt != old.claim?.expiresAt { fields.insert(.claimExpiresAt) }
        if goneReports != old.goneReports { fields.insert(.goneReports) }
        if seenBy != old.seenBy { fields.insert(.seenBy) }
        if closedAt != old.closedAt { fields.insert(.closedAt) }
        if purgeAt != old.purgeAt { fields.insert(.purgeAt) }
        if closing?.reason != old.closing?.reason { fields.insert(.closingReason) }
        if closing?.userID != old.closing?.userID { fields.insert(.closingBy) }
        if closing?.at != old.closing?.at { fields.insert(.closingAt) }
        if closing?.credible != old.closing?.credible { fields.insert(.closingCredible) }
        if objectors != old.objectors { fields.insert(.objectors) }
        if disputed != old.disputed { fields.insert(.disputed) }
        if editCount != old.editCount { fields.insert(.editCount) }
        return fields
    }

    /// 1 = az önce görüldü, 0 = süresi dolmak üzere. Haritada eski işaretleri soluklaştırmak için.
    public func freshness(at now: Date) -> Double {
        let total = expiresAt.timeIntervalSince(lastSeenAt)
        guard total > 0 else { return 0 }
        return min(1, max(0, expiresAt.timeIntervalSince(now) / total))
    }
}
