import Foundation

/// Bir işaret üzerinde yapılabilecek eylemler.
public enum ReportAction: String, CaseIterable, Identifiable, Sendable {
    /// "İlgileniyorum": işareti üstüne al.
    case claim
    /// "Vazgeç": sahipliği bırak, işaret yeniden yardım beklesin. İşareti koyan da
    /// 45 dk'dır haber vermeyen sahipliği kaldırabilir ("İlgilenen gelmedi").
    case release
    /// "Çözüldü": yardım edildi. Yalnızca işareti koyan tek tanıksa hemen kapanır;
    /// diğer her durumda "Çözüldü dendi" olur.
    case resolve
    /// "Hâlâ orada": işaretin ömrünü uzatır; kişi "kaç kişi bildirdi" sayısına eklenir.
    case confirmStillThere
    /// "Artık yok": hayvan orada değil.
    case reportGone
    /// "Hayvan orada ama iyi görünüyor" (mama işaretinde "Yardım gerekmiyor" altında): `resolve` gibi işler,
    /// nedeni `unneeded`. Yalnızca işareti koyan tek tanıksa hemen kapanır ("Yanlış alarmdı");
    /// diğer her durumda "Yardım gerekmiyor dendi" olur.
    case reportUnneeded
    /// "Hâlâ yardım gerekiyor": "… dendi" önerisine itiraz; işaret yeniden yardım bekler.
    case dispute
    /// "Evet, çözüldü" (gone için arayüz "Evet, artık yok", unneeded için "Evet, ihtiyacı yoktu" der):
    /// ikinci kişi öneriyi onaylar.
    case confirmClosing
    /// "Geri al": öneriyi yapan kişi 10 dk içinde geri alır. Geçerli sahiplik kalır.
    case undoClosing
    /// Süresi dolan işareti kapatır (Spark'ta temizlik fonksiyonu yerine). Kullanıcıya gösterilmez.
    case expire

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .claim: "İlgileniyorum"
        case .release: "Vazgeç"
        case .resolve: "Çözüldü"
        case .confirmStillThere: "Hâlâ orada"
        case .reportGone: "Artık yok"
        case .reportUnneeded: "Hayvan orada ama iyi görünüyor"
        case .dispute: "Hâlâ yardım gerekiyor"
        case .confirmClosing: "Evet, çözüldü"
        case .undoClosing: "Geri al"
        case .expire: "Süresi doldu"
        }
    }

    public var symbolName: String {
        switch self {
        case .claim: "hand.raised.fill"
        case .release: "arrow.uturn.backward"
        case .resolve: "checkmark.circle.fill"
        case .confirmStillThere: "eye.fill"
        case .reportGone: "eye.slash"
        case .reportUnneeded: "hand.thumbsup.fill"
        case .dispute: "exclamationmark.circle.fill"
        case .confirmClosing: "checkmark.seal.fill"
        case .undoClosing: "arrow.uturn.backward"
        case .expire: "clock"
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
    /// Bu kişinin kapatma önerisine itiraz edildi; işareti bir daha üstüne alamaz, kapatamaz.
    case disputed
    /// Başkasının 45 dk'dan genç sahipliği varken "Çözüldü" denemez.
    case claimTooFresh
    /// İşareti koyan dışındakiler bir işarete bir kez itiraz edebilir.
    case alreadyObjected
    /// İşaret `ReportLifecycle.maxDisputed` itiraz aldı; yalnızca süresi dolunca kalkar.
    case tooManyDisputes
    /// `expire`: süresi henüz dolmadı.
    case notExpired
    /// "Geri al" yalnızca öneriyi yapan kişiye ve `ReportLifecycle.undoWindow` içinde açık.
    case notYourClosing
    /// Kart açıkken işaretin durumu değişti (ör. biri az önce "Çözüldü" dedi ya da itiraz etti).
    case statusChanged
    /// Düzeltme yalnızca işareti koyana, kimse dokunmamışken, `ReportLifecycle.editWindow` içinde
    /// ve en fazla `ReportLifecycle.maxEdits` kez açık.
    case notEditable
    /// Düzeltmede iğne en fazla ~200 m kaydırılabilir (`ReportLifecycle.editMaxLatDelta` / `editMaxLngDelta`).
    case editTooFar

    public var errorDescription: String? {
        switch self {
        case .notFound: "İşaret bulunamadı."
        case .notActive: "Bu işaret artık aktif değil."
        case .alreadyClaimed: "Az önce başka biri ilgilenmeye başladı."
        case .notClaimedByYou: "Bu işaretle şu an sen ilgilenmiyorsun."
        case .notAllowed: "Bunu şu an yapamazsın."
        case .alreadyReportedGone: "Bunu zaten bildirdin."
        case .disputed: "Bu işaret için dediğine itiraz edildi; artık 'İlgileniyorum' ya da 'Çözüldü' diyemezsin."
        case .claimTooFresh:
            "Biri az önce ilgilenmeye başladı. 45 dk içinde haber gelmezse sen de 'Çözüldü' diyebilirsin."
        case .alreadyObjected: "Bu işarete zaten itiraz ettin."
        case .tooManyDisputes: "Bu işaret çok itiraz aldı; süresi dolunca kendiliğinden kalkar."
        case .notExpired: "Bu işaretin süresi henüz dolmadı."
        case .notYourClosing: "Geri alma süresi doldu. 'Çözüldü' ya da 'Artık yok' yalnızca 10 dk içinde geri alınabilir."
        case .statusChanged: "Bu işaretin durumu az önce değişti."
        case .notEditable: "Bu işaret artık düzenlenemez: başkası gördü ya da 30 dakika geçti."
        case .editTooFar: "Konum en fazla 200 m kaydırılabilir."
        }
    }
}

/// İşaretin yaşam döngüsü: oluşturma, eylemler ve hangi eylemin kime açık olduğu.
///
///     open ──İlgileniyorum──▶ claimed ──(Vazgeç / 3 sa)──▶ open
///     open ──Düzenle (koyan; kimse dokunmadan, 30 dk içinde, en fazla 3 kez)──▶ open
///     open|claimed ──Çözüldü / Artık yok / Yardım gerekmiyor──▶ closing ("… dendi"; haritada kalır, ömrü kısalmaz)
///     closing ──Hâlâ yardım gerekiyor (kapatan dışında herkes)──▶ open
///     closing ──Evet, çözüldü (ikinci kişi)──▶ closed
///     closing ──Geri al (kapatan, 10 dk)──▶ claimed (sahiplik hâlâ geçerliyse) | open
///     open|claimed ──Çözüldü / Artık yok / Yardım gerekmiyor (koyan; başka gören yoksa)──▶ closed
///     open|claimed|closing ──süresi doldu──▶ closed
///
/// "Yardım gerekmiyor" (`reportUnneeded`) yalnızca mama işaretlerinde vardır (`Need.allowsUnneeded`).
///
/// Değişmez kural: başkasının da gördüğü bir işareti tek bir kişi süresinden önce kaldıramaz.
///
/// Bu tip saf mantıktır (ağ yok, saat dışarıdan verilir). Firestore güvenlik kuralları
/// (firebase/firestore.rules) aynı geçişleri sunucuda da zorunlu kılar.
public enum ReportLifecycle {
    /// "İlgileniyorum" sonrası, çözülmezse işaretin tekrar açılacağı süre.
    public static let claimDuration: TimeInterval = 3 * 3600
    /// Başkası bu kadar süredir ilgileniyorsa herkes "Çözüldü" diyebilir, işareti koyan sahipliği kaldırabilir.
    public static let claimStale: TimeInterval = 45 * 60
    /// Kapatma önerisini yapanın "Geri al" süresi.
    public static let undoWindow: TimeInterval = 10 * 60
    /// Hiçbir işaret oluşturulmasından bu kadar sonra haritada kalamaz ("Hâlâ orada" da uzatamaz).
    public static let maxAge: TimeInterval = 7 * 24 * 3600
    /// Başka sahiplik yokken kaç farklı kişi "Artık yok" derse "Artık yok dendi" olur.
    public static let goneThreshold = 3
    /// İtiraz alan en fazla kapatma önerisi; dolunca yalnızca süre kapatır.
    public static let maxDisputed = 10
    /// Kapanan işaret ne kadar sonra veritabanından silinir.
    public static let retention: TimeInterval = 30 * 24 * 3600
    public static let geohashPrecision = 10
    /// "Kaç kişi bildirdi" listesinde (`Report.seenBy`) tutulan en fazla kullanıcı sayısı.
    public static let maxSeenBy = 100
    /// "Artık yok" listesinin (`Report.goneReports`) kurallardaki üst sınırı.
    public static let maxGoneReports = 20
    /// İşareti koyan, yanlış koyduğu işareti oluşturduktan sonra bu süre içinde düzeltebilir.
    public static let editWindow: TimeInterval = 30 * 60
    /// Bir işaret en fazla bu kadar kez düzeltilebilir.
    public static let maxEdits = 3
    /// Bir düzeltmede konumun enlemde ve boylamda en fazla kayabileceği derece: ikisi de ~200 m
    /// (Türkiye enlemlerinde bir boylam derecesi daha kısadır).
    public static let editMaxLatDelta = 0.0018
    public static let editMaxLngDelta = 0.0024

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
            purgeAt: nil,
            closing: nil,
            objectors: [],
            disputed: [],
            editCount: 0
        )
    }

    // MARK: Kim ne yapabilir

    /// Kullanıcının bu işarette görebileceği eylemler. İlki birincil eylemdir
    /// (İlgileniyorum / Çözüldü / Evet, çözüldü); `expire` hiçbir zaman gösterilmez.
    /// Mama işaretinde "Çözüldü"nün açık olduğu her yerde `reportUnneeded` de vardır ("Artık yok"tan hemen önce).
    public static func availableActions(for report: Report, userID: String, at now: Date) -> [ReportAction] {
        let isReporter = report.reporterID == userID
        let canResolve = reporterAlone(report, userID: userID) || mayPropose(report, by: userID, at: now)
        var actions: [ReportAction]

        switch report.phase(for: userID, at: now) {
        case .closed:
            return []
        case .closing(_, let since, let byMe, _):
            if byMe {
                return now < since.addingTimeInterval(undoWindow) ? [.undoClosing] : []
            }
            actions = []
            if canConfirmClosing(report, by: userID) { actions.append(.confirmClosing) }
            if canDispute(report, by: userID) { actions.append(.dispute) }
            return actions
        case .waiting:
            actions = report.disputed.contains(userID) ? [] : [.claim]
            if isReporter && canResolve { actions.append(.resolve) }
            actions.append(.confirmStillThere)
            // Yoldan geçen için "Çözüldü" ikincil düğmedir.
            if !isReporter && canResolve { actions.append(.resolve) }
        case .helpedByMe:
            actions = canResolve ? [.resolve, .release] : [.release]
        case .helpedByOther:
            actions = isReporter && canResolve ? [.resolve] : []
            actions.append(.confirmStillThere)
            if !isReporter && canResolve { actions.append(.resolve) }
            // "İlgilenen gelmedi"
            if isReporter && report.isClaimStale(at: now) { actions.append(.release) }
        }

        // Bu evrelerde "Çözüldü" tam olarak `canResolve` iken sunulur; "Yardım gerekmiyor" aynı yoldan geçer.
        if canResolve && report.need.allowsUnneeded {
            actions.append(.reportUnneeded)
        }
        if canReportGone(report, by: userID) {
            actions.append(.reportGone)
        }
        return actions
    }

    /// Hayvanı koyandan başka gören yok: işareti koyanın "Çözüldü" / "Artık yok" / "Yardım gerekmiyor"u
    /// hemen kapatır.
    public static func reporterAlone(_ report: Report, userID: String) -> Bool {
        report.reporterID == userID && report.seenBy == [userID]
    }

    /// Bu kişi işareti "… dendi"ye alabilir mi? Başkasının 45 dk'dan genç sahipliğine saygı gösterilir;
    /// itiraz edilmiş kişi ve `maxDisputed` itiraz almış işaret öneremez.
    public static func mayPropose(_ report: Report, by userID: String, at now: Date) -> Bool {
        guard !report.disputed.contains(userID), report.disputed.count < maxDisputed else { return false }
        guard let claim = report.activeClaim(at: now) else { return true }
        return claim.userID == userID
            || report.reporterID == userID
            || now >= claim.claimedAt.addingTimeInterval(claimStale)
    }

    /// Eylem işareti şimdi "… dendi"ye alır mı? Öyleyse depo kanıtlılığı hesaplar
    /// (`credibility(of:by:record:at:)`) ve kanıtlıysa bütçeden harcar.
    public static func wouldStartClosing(_ action: ReportAction, on report: Report, by userID: String, at now: Date) -> Bool {
        guard report.status != .closing,
              let updated = try? apply(action, to: report, by: userID, at: now)
        else { return false }
        return updated.status == .closing
    }

    /// "Evet, çözüldü": ikinci kişi onaylar. Kapatan başkasıysa işareti koyan;
    /// kapatan koyansa hayvanı gören başka biri. Tanınmayan nedenli öneri bu sürümde onaylanamaz.
    public static func canConfirmClosing(_ report: Report, by userID: String) -> Bool {
        guard report.status == .closing, let closing = report.closing, closing.unrecognizedReason == nil else {
            return false
        }
        let isReporter = report.reporterID == userID
        if isReporter { return closing.userID != userID }
        return closing.userID == report.reporterID && report.seenBy.contains(userID)
    }

    /// "Hâlâ yardım gerekiyor": kapatan dışında herkes; işareti koyan sınırsız, diğerleri bir kez.
    public static func canDispute(_ report: Report, by userID: String) -> Bool {
        guard report.status == .closing, let closing = report.closing, closing.userID != userID else { return false }
        guard report.disputed.count < maxDisputed else { return false }
        if report.reporterID == userID { return true }
        return !report.objectors.contains(userID) && report.objectors.count < maxDisputed
    }

    /// "… dendi" önerisine bu kişi yanıt verebilir mi ("Evet, çözüldü" ya da "Hâlâ yardım gerekiyor")?
    /// Takip sorusu yalnızca bu kişilere sorulur; yanıt veremeyen paydaş işareti başkaları gibi görür.
    public static func canAnswerClosing(_ report: Report, by userID: String) -> Bool {
        canConfirmClosing(report, by: userID) || canDispute(report, by: userID)
    }

    /// Bu kullanıcının "Hâlâ orada" demesi "kaç kişi bildirdi" sayısını artırır mı?
    /// Listede değilse ve liste dolmadıysa artırır.
    public static func confirmAddsSeen(to report: Report, by userID: String) -> Bool {
        !report.seenBy.contains(userID) && report.seenBy.count < maxSeenBy
    }

    /// "Geri al" (silme): yalnızca işareti koyanın, kimsenin görmediği ve dokunmadığı işareti.
    public static func canRetract(_ report: Report, by userID: String) -> Bool {
        report.reporterID == userID
            && report.status == .open
            && report.seenBy == [userID]
            && report.goneReports.isEmpty
            && report.disputed.isEmpty
    }

    /// "Düzenle": yalnızca işareti koyan; işaret açık ve süresi dolmamışken, kimse dokunmamışken (başka gören,
    /// "Artık yok", itiraz yok), oluşturulduktan sonraki `editWindow` içinde ve en fazla `maxEdits` kez
    /// (kurallardaki `isEdit`).
    public static func canEdit(_ report: Report, by userID: String, at now: Date) -> Bool {
        report.reporterID == userID
            && report.status == .open
            && report.expiresAt > now
            && report.seenBy == [userID]
            && report.goneReports.isEmpty
            && report.objectors.isEmpty
            && report.disputed.isEmpty
            && now < report.createdAt.addingTimeInterval(editWindow)
            && report.editCount < maxEdits
    }

    /// Yeni konum bir düzeltmede izin verilen kaymanın içinde mi? Sınır her düzeltmede işaretin
    /// o anki konumundan ölçülür.
    public static func isWithinEditRange(_ report: Report, to coordinate: Coordinate) -> Bool {
        abs(coordinate.latitude - report.coordinate.latitude) <= editMaxLatDelta
            && abs(coordinate.longitude - report.coordinate.longitude) <= editMaxLngDelta
    }

    /// İşaretin ömrünün hiçbir uzatmayla geçemeyeceği an: oluşturma + `maxAge`.
    public static func lifeCap(_ report: Report) -> Date {
        report.createdAt.addingTimeInterval(maxAge)
    }

    /// Süresi dolmuş ama henüz kapanmamış: herkes `expire` ile kapatabilir. Tanınmayan nedenli öneriyi
    /// bu sürüm kapatamaz (kurallar aynı nedeni ister); onu yeni sürümler kapatır.
    public static func isDue(_ report: Report, at now: Date) -> Bool {
        report.status != .closed && report.expiresAt <= now && !hasUnrecognizedClosing(report)
    }

    // MARK: Eylemler

    /// Eylemi uygular ve işaretin yeni hâlini döndürür.
    ///
    /// `credible`: "… dendi" önerisi kapatanın günlük bütçesiyle destekleniyor mu. Depo bunu yalnızca
    /// `credibility(of:by:record:at:) == .credible` iken ve aynı yazımda bütçeden harcayarak verir;
    /// öneri başlatmayan eylemlerde yok sayılır.
    public static func apply(
        _ action: ReportAction,
        to report: Report,
        by userID: String,
        at now: Date,
        credible: Bool = false
    ) throws -> Report {
        guard report.status != .closed else { throw ReportError.notActive }

        var updated = report
        let claim = report.activeClaim(at: now)
        let isClaimer = claim?.userID == userID
        let isReporter = report.reporterID == userID

        switch action {
        case .claim:
            try requireWaiting(report, at: now)
            guard !report.disputed.contains(userID) else { throw ReportError.disputed }
            guard claim == nil else { throw ReportError.alreadyClaimed }
            let claimExpiresAt = now.addingTimeInterval(claimDuration)
            updated.status = .claimed
            updated.claim = Claim(userID: userID, claimedAt: now, expiresAt: claimExpiresAt)
            // İlgilenilen işaret, sahiplik süresi bitmeden haritadan düşmesin.
            updated.expiresAt = extendedExpiry(of: report, to: claimExpiresAt)

        case .release:
            try requireWaiting(report, at: now)
            guard isClaimer || (isReporter && report.isClaimStale(at: now)) else {
                throw ReportError.notClaimedByYou
            }
            updated.status = .open
            updated.claim = nil

        case .resolve:
            try requireWaiting(report, at: now)
            if reporterAlone(report, userID: userID) {
                close(&updated, as: .resolved, at: now)
            } else {
                try requireProposal(report, by: userID, at: now, credible: credible)
                startClosing(&updated, as: .resolved, by: userID, at: now, credible: credible)
            }

        case .confirmStillThere:
            try requireWaiting(report, at: now)
            refresh(&updated, by: userID, at: now)
            // Günler arayla verilen "Artık yok" oyları toplanmasın.
            updated.goneReports = []

        case .reportUnneeded:
            try requireWaiting(report, at: now)
            guard report.need.allowsUnneeded else { throw ReportError.notAllowed }
            if reporterAlone(report, userID: userID) {
                close(&updated, as: .unneeded, at: now)
            } else {
                try requireProposal(report, by: userID, at: now, credible: credible)
                startClosing(&updated, as: .unneeded, by: userID, at: now, credible: credible)
            }

        case .reportGone:
            try requireWaiting(report, at: now)
            guard !report.goneReports.contains(userID) else { throw ReportError.alreadyReportedGone }
            guard report.goneReports.count < maxGoneReports else { throw ReportError.notAllowed }
            updated.goneReports.append(userID)
            if reporterAlone(report, userID: userID) {
                close(&updated, as: .gone, at: now)
            } else if mayPropose(report, by: userID, at: now)
                        && (isReporter || isClaimer || (claim == nil && updated.goneReports.count >= goneThreshold)) {
                // Oylar başkasının canlı sahipliği üstüne öneri başlatamaz; o zaman yalnızca sayılır.
                try requireProposal(report, by: userID, at: now, credible: credible)
                startClosing(&updated, as: .gone, by: userID, at: now, credible: credible)
            }

        case .dispute:
            let closing = try requireClosing(report, at: now)
            guard closing.userID != userID else { throw ReportError.notAllowed }
            guard isReporter || !report.objectors.contains(userID) else { throw ReportError.alreadyObjected }
            guard report.disputed.count < maxDisputed, isReporter || report.objectors.count < maxDisputed else {
                throw ReportError.tooManyDisputes
            }
            updated.status = .open
            updated.closing = nil
            updated.claim = nil
            updated.goneReports = []
            // Kapatan bu işarette bir daha öneremez; itiraz eden hayvanı şimdi görmüş sayılır.
            updated.disputed.append(closing.userID)
            if !isReporter { updated.objectors.append(userID) }
            refresh(&updated, by: userID, at: now)

        case .confirmClosing:
            let closing = try requireClosing(report, at: now)
            guard canConfirmClosing(report, by: userID) else { throw ReportError.notAllowed }
            close(&updated, as: closing.reason, at: now)

        case .undoClosing:
            let closing = try requireClosing(report, at: now)
            guard closing.userID == userID, now < closing.at.addingTimeInterval(undoWindow) else {
                throw ReportError.notYourClosing
            }
            updated.closing = nil
            // Öneriden önceki sahiplik hâlâ geçerliyse (başkasınınki de) aynen kalır: "Çözüldü" + "Geri al"
            // taze bir sahipliği düşüremez (kurallardaki isUndo).
            if let kept = report.claim, kept.expiresAt > now {
                updated.status = .claimed
            } else {
                updated.status = .open
                updated.claim = nil
            }

        case .expire:
            guard report.expiresAt <= now else { throw ReportError.notExpired }
            guard isDue(report, at: now) else { throw ReportError.notAllowed }
            let reason: ClosedReason = report.status == .closing ? (report.closing?.reason ?? .expired) : .expired
            close(&updated, as: reason, at: now)
        }
        return updated
    }

    /// Yanlış konan işareti düzeltir: tür, ihtiyaç ve konum (`isWithinEditRange`). Her çağrı bir düzeltme
    /// sayılır, bir şey değişmese de: kurallar `editCount`un tam bir artmasını ister.
    ///
    /// İhtiyaç değişirse ömür yeni ihtiyaca göre şimdiden yeniden başlar (kısalabilir de); değişmezse
    /// `expiresAt` aynı kalır. `geohash` yeni konumdan hesaplanır (kurallar doğrulayamaz). Görülme anı,
    /// "kaç kişi bildirdi" ve diğer alanlar değişmez.
    public static func edit(
        _ report: Report,
        species: Species,
        need: Need,
        coordinate: Coordinate,
        by userID: String,
        at now: Date
    ) throws -> Report {
        guard report.status != .closed, report.expiresAt > now else { throw ReportError.notActive }
        guard canEdit(report, by: userID, at: now) else { throw ReportError.notEditable }
        guard isWithinEditRange(report, to: coordinate) else { throw ReportError.editTooFar }

        var updated = report
        updated.species = species
        if need != report.need {
            updated.need = need
            updated.expiresAt = min(now.addingTimeInterval(need.lifetime), lifeCap(report))
        }
        if coordinate != report.coordinate {
            updated.coordinate = coordinate
            updated.geohash = Geohash.encode(coordinate, precision: geohashPrecision)
        }
        updated.editCount += 1
        return updated
    }

    // MARK: Yardımcılar

    /// open|claimed eylemleri: süresi dolmamış ve "… dendi" olmamış işaret.
    private static func requireWaiting(_ report: Report, at now: Date) throws {
        guard report.expiresAt > now else { throw ReportError.notActive }
        guard report.isWaiting(at: now) else { throw ReportError.statusChanged }
    }

    /// closing eylemleri: süresi dolmamış "… dendi" işareti.
    private static func requireClosing(_ report: Report, at now: Date) throws -> Closing {
        guard report.expiresAt > now else { throw ReportError.notActive }
        guard report.status == .closing, let closing = report.closing else { throw ReportError.statusChanged }
        return closing
    }

    private static func requireProposal(_ report: Report, by userID: String, at now: Date, credible: Bool) throws {
        guard !report.disputed.contains(userID) else { throw ReportError.disputed }
        guard report.disputed.count < maxDisputed else { throw ReportError.tooManyDisputes }
        guard mayPropose(report, by: userID, at: now) else { throw ReportError.claimTooFresh }
        // Sunucu kanıtlı öneriyi yalnızca az itiraz almış işarette kabul eder.
        guard !credible || report.disputed.count <= Budget.credibleMaxDisputed else { throw ReportError.notAllowed }
    }

    /// `expiresAt` aynı kalır ya da `limit`e kadar uzar; `lifeCap`i asla geçmez, asla kısalmaz.
    private static func extendedExpiry(of report: Report, to limit: Date) -> Date {
        max(report.expiresAt, min(limit, lifeCap(report)))
    }

    /// "Hayvanı şimdi gördüm": lastSeenAt yenilenir, ömür uzar, kişi seenBy'a bir kez eklenir.
    private static func refresh(_ report: inout Report, by userID: String, at now: Date) {
        let before = report
        report.lastSeenAt = now
        report.expiresAt = extendedExpiry(of: before, to: now.addingTimeInterval(before.need.lifetime))
        // Gören kişi bir kez sayılır; başkasını ekleyemez, kimseyi çıkaramaz.
        if confirmAddsSeen(to: before, by: userID) {
            report.seenBy.append(userID)
        }
    }

    private static func canReportGone(_ report: Report, by userID: String) -> Bool {
        !report.goneReports.contains(userID) && report.goneReports.count < maxGoneReports
    }

    private static func hasUnrecognizedClosing(_ report: Report) -> Bool {
        report.status == .closing && report.closing?.unrecognizedReason != nil
    }

    /// Sahiplik alanları kartta zaman çizelgesi için kalır; `expiresAt` değişmez.
    private static func startClosing(
        _ report: inout Report,
        as reason: ClosedReason,
        by userID: String,
        at now: Date,
        credible: Bool
    ) {
        report.status = .closing
        report.closing = Closing(reason: reason, userID: userID, at: now, credible: credible)
    }

    /// `closing` varsa geçmiş olarak kalır.
    private static func close(_ report: inout Report, as reason: ClosedReason, at now: Date) {
        report.status = .closed
        report.closedReason = reason
        report.closedAt = now
        report.purgeAt = now.addingTimeInterval(retention)
    }
}
