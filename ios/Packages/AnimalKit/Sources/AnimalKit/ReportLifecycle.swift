import Foundation

/// Bir işaret üzerinde yapılabilecek eylemler.
public enum ReportAction: String, CaseIterable, Identifiable, Sendable {
    /// "İlgileniyorum": işareti üstüne al.
    case claim
    /// "Vazgeç": sahipliği bırak, işaret yeniden yardım beklesin.
    case release
    /// "Çözüldü": yardım edildi, işaret haritadan kalkar.
    case resolve
    /// "Hâlâ orada": işaretin ömrünü uzatır; kişi "kaç kişi bildirdi" sayısına eklenir.
    case confirmStillThere
    /// "Artık yok": hayvan orada değil.
    case reportGone

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .claim: "İlgileniyorum"
        case .release: "Vazgeç"
        case .resolve: "Çözüldü"
        case .confirmStillThere: "Hâlâ orada"
        case .reportGone: "Artık yok"
        }
    }

    public var symbolName: String {
        switch self {
        case .claim: "hand.raised.fill"
        case .release: "arrow.uturn.backward"
        case .resolve: "checkmark.circle.fill"
        case .confirmStillThere: "eye.fill"
        case .reportGone: "eye.slash"
        }
    }
}

public enum ReportError: Error, Equatable, LocalizedError {
    case notFound
    case notActive
    case alreadyClaimed
    case notClaimedByYou
    case notAllowed
    case alreadyReportedGone

    public var errorDescription: String? {
        switch self {
        case .notFound: "İşaret bulunamadı."
        case .notActive: "Bu işaret artık aktif değil."
        case .alreadyClaimed: "Az önce başka biri ilgilenmeye başladı."
        case .notClaimedByYou: "Bu işaretle şu an sen ilgilenmiyorsun."
        case .notAllowed: "Bunu yalnızca işareti koyan ya da ilgilenen kişi yapabilir."
        case .alreadyReportedGone: "Bunu zaten bildirdin."
        }
    }
}

/// İşaretin yaşam döngüsü: oluşturma, eylemler ve hangi eylemin kime açık olduğu.
///
/// Bu tip saf mantıktır (ağ yok, saat dışarıdan verilir). Firestore güvenlik kuralları
/// (firebase/firestore.rules) aynı geçişleri sunucuda da zorunlu kılar.
public enum ReportLifecycle {
    /// "İlgileniyorum" sonrası, çözülmezse işaretin tekrar açılacağı süre.
    public static let claimDuration: TimeInterval = 3 * 3600
    /// Kaç farklı kişi "Artık yok" derse işaret kapanır.
    public static let goneThreshold = 2
    /// Kapanan işaret ne kadar sonra veritabanından silinir.
    public static let retention: TimeInterval = 30 * 24 * 3600
    public static let geohashPrecision = 10
    /// "Kaç kişi bildirdi" listesinde (`Report.seenBy`) tutulan en fazla kullanıcı sayısı.
    public static let maxSeenBy = 100

    /// Yeni işaret. Tek gereken tür, ihtiyaç ve konum.
    public static func makeReport(
        id: String,
        species: Species,
        need: Need,
        at coordinate: Coordinate,
        reporterID: String,
        now: Date
    ) -> Report {
        Report(
            id: id,
            species: species,
            need: need,
            coordinate: coordinate,
            geohash: Geohash.encode(coordinate, precision: geohashPrecision),
            reporterID: reporterID,
            createdAt: now,
            status: .open,
            closedReason: nil,
            lastSeenAt: now,
            expiresAt: now.addingTimeInterval(need.lifetime),
            claim: nil,
            goneReports: [],
            seenBy: [reporterID],
            closedAt: nil,
            purgeAt: nil
        )
    }

    /// Kullanıcının bu işarette görebileceği eylemler. İlki birincil eylemdir.
    public static func availableActions(for report: Report, userID: String, at now: Date) -> [ReportAction] {
        let isReporter = report.reporterID == userID
        var actions: [ReportAction]

        switch report.phase(for: userID, at: now) {
        case .closed:
            return []
        case .waiting:
            actions = [.claim]
            if isReporter { actions.append(.resolve) }
            actions.append(.confirmStillThere)
        case .helpedByMe:
            actions = [.resolve, .release]
        case .helpedByOther:
            actions = isReporter ? [.resolve] : []
            actions.append(.confirmStillThere)
        }

        if !report.goneReports.contains(userID) {
            actions.append(.reportGone)
        }
        return actions
    }

    /// Eylemi uygular ve işaretin yeni hâlini döndürür.
    public static func apply(_ action: ReportAction, to report: Report, by userID: String, at now: Date) throws -> Report {
        guard report.isActive(at: now) else { throw ReportError.notActive }

        var updated = report
        let claim = report.activeClaim(at: now)
        let isClaimer = claim?.userID == userID
        let isReporter = report.reporterID == userID

        switch action {
        case .claim:
            guard claim == nil else { throw ReportError.alreadyClaimed }
            let claimExpiresAt = now.addingTimeInterval(claimDuration)
            updated.status = .claimed
            updated.claim = Claim(userID: userID, claimedAt: now, expiresAt: claimExpiresAt)
            // İlgilenilen işaret, sahiplik süresi bitmeden haritadan düşmesin.
            updated.expiresAt = max(report.expiresAt, claimExpiresAt)

        case .release:
            guard isClaimer else { throw ReportError.notClaimedByYou }
            updated.status = .open
            updated.claim = nil

        case .resolve:
            guard isClaimer || isReporter else { throw ReportError.notAllowed }
            close(&updated, as: .resolved, at: now)

        case .confirmStillThere:
            updated.lastSeenAt = now
            updated.expiresAt = max(report.expiresAt, now.addingTimeInterval(report.need.lifetime))
            // Gören kişi bir kez sayılır; başkasını ekleyemez, kimseyi çıkaramaz.
            if confirmAddsSeen(to: report, by: userID) {
                updated.seenBy.append(userID)
            }

        case .reportGone:
            guard !report.goneReports.contains(userID) else { throw ReportError.alreadyReportedGone }
            updated.goneReports.append(userID)
            if isReporter || isClaimer || updated.goneReports.count >= goneThreshold {
                close(&updated, as: .gone, at: now)
            }
        }
        return updated
    }

    /// Bu kullanıcının "Hâlâ orada" demesi "kaç kişi bildirdi" sayısını artırır mı?
    /// Listede değilse ve liste dolmadıysa artırır.
    public static func confirmAddsSeen(to report: Report, by userID: String) -> Bool {
        !report.seenBy.contains(userID) && report.seenBy.count < maxSeenBy
    }

    /// "Geri al": kimse dokunmadıysa işareti koyan kişi silebilir.
    public static func canRetract(_ report: Report, by userID: String) -> Bool {
        report.reporterID == userID && report.status == .open && report.goneReports.isEmpty
    }

    private static func close(_ report: inout Report, as reason: ClosedReason, at now: Date) {
        report.status = .closed
        report.closedReason = reason
        report.closedAt = now
        report.purgeAt = now.addingTimeInterval(retention)
    }
}
