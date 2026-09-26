import Foundation

/// `users/{uid}`: hesap yaşı ve 24 saatlik haklar (yeni işaret, kanıtlı "Çözüldü").
///
/// Her harcama Firestore'da bir işarete bağlanır (`createLast` / `closeLast` = `{t, id[, w]}`,
/// `t` sunucu saati); bu alanlar yalnızca yazımda anlamlı olduğu için burada tutulmaz.
public struct UserRecord: Hashable, Sendable {
    /// Hesabın oluşturulduğu an (sunucu saati, değişmez).
    public var createdAt: Date
    /// Geçerli yeni işaret penceresinin başı.
    public var createWindow: Date
    /// Bu pencerede konan işaret sayısı.
    public var createUsed: Int
    /// Geçerli kapatma bütçesi penceresinin başı.
    public var closeWindow: Date
    /// Bu pencerede harcanan kapatma puanı.
    public var closeUsed: Int

    public init(createdAt: Date, createWindow: Date, createUsed: Int, closeWindow: Date, closeUsed: Int) {
        self.createdAt = createdAt
        self.createWindow = createWindow
        self.createUsed = createUsed
        self.closeWindow = closeWindow
        self.closeUsed = closeUsed
    }

    /// Anonim girişten hemen sonra oluşturulan kayıt (kurallar: pencereler `createdAt` ile başlar, sayaçlar 0).
    public static func new(at now: Date) -> UserRecord {
        UserRecord(createdAt: now, createWindow: now, createUsed: 0, closeWindow: now, closeUsed: 0)
    }
}

/// Bir harcamanın hangi kural dalıyla yazılacağı.
public enum BudgetSpend: Equatable, Sendable {
    /// Pencere aynı kalır, sayaç artar (kurallar bunu her zaman kabul eder; yalnızca daha sıkıdır).
    case sameWindow
    /// Pencere şimdi yeniden başlar (pencere başı `serverTimestamp()` yazılır), sayaç harcama kadardır.
    case newWindow
}

/// Kanıtlı "Çözüldü" olmamasının nedeni; bildirim metnini seçmek için.
public enum CloseCredibility: Equatable, Sendable {
    case credible
    /// `users/{uid}` henüz yok (oluşturulamadı ya da okunamadı).
    case noRecord
    /// İşaret `Budget.credibleMaxDisputed`'dan fazla itiraz aldı.
    case disputed
    /// Hesap 24 saatten genç ve işareti koyan değil.
    case newAccount
    /// Son 24 saatteki kapatma puanı bitti.
    case budgetUsed
}

/// Kişi başı 24 saatlik haklar. Değerler shared/report-contract.json ve firestore.rules ile aynı olmalıdır.
public enum Budget {
    /// Hakların sayıldığı kayan pencere.
    public static let window: TimeInterval = 24 * 3600
    /// Bundan genç hesap "ilk gün"dedir: daha az işaret koyar, kanıtlı kapatamaz.
    public static let newAccountAge: TimeInterval = 24 * 3600
    /// Bir pencerede en fazla yeni işaret.
    public static let maxCreates = 10
    /// Hesabın ilk gününde en fazla yeni işaret.
    public static let maxCreatesFirstDay = 5
    /// Bir pencerede kanıtlı kapatma puanı (ağır ihtiyaç 2, hafif 1; bkz. `Need.closeCost`).
    public static let closePoints = 8
    /// Bundan fazla itiraz almış işarette kapatma kanıtlı sayılmaz.
    public static let credibleMaxDisputed = 1
    /// İstemci saati sunucudan ileride olabilir: pencere ve hesap yaşı ancak bu pay da geçince dolmuş sayılır,
    /// yoksa sunucu yeni pencereyi reddederdi. Kuralların saat toleransıyla (skew) aynı.
    public static let resetMargin: TimeInterval = 15 * 60

    /// Hesap hâlâ ilk gününde mi (istemci tarafında pay ile)?
    public static func isNewAccount(_ record: UserRecord, at now: Date) -> Bool {
        now < record.createdAt.addingTimeInterval(newAccountAge + resetMargin)
    }

    // MARK: Yeni işaret

    /// Bu penceredeki yeni işaret hakkı: ilk gün 5, sonra 10.
    public static func createLimit(_ record: UserRecord, at now: Date) -> Int {
        isNewAccount(record, at: now) ? maxCreatesFirstDay : maxCreates
    }

    public static func remainingCreates(_ record: UserRecord, at now: Date) -> Int {
        let limit = createLimit(record, at: now)
        if windowEnded(record.createWindow, at: now) { return limit }
        return max(0, limit - record.createUsed)
    }

    /// Yeni işaret hakkının açılacağı an (dakikaya yukarı yuvarlanır, gösterilen saat tutsun);
    /// şimdi hak varsa `nil`.
    public static func nextCreateAt(_ record: UserRecord, at now: Date) -> Date? {
        guard remainingCreates(record, at: now) == 0 else { return nil }
        var next = record.createWindow.addingTimeInterval(window + resetMargin)
        // İlk gün sınırı pencereden önce kalkabilir.
        if isNewAccount(record, at: now) && record.createUsed < maxCreates {
            next = min(next, record.createdAt.addingTimeInterval(newAccountAge + resetMargin))
        }
        return roundedUpToMinute(next)
    }

    /// Yeni işaretle aynı yazımda yapılacak harcama; hak yoksa `nil`.
    public static func spendCreate(_ record: UserRecord, at now: Date) -> (record: UserRecord, spend: BudgetSpend)? {
        let branch: BudgetSpend = windowEnded(record.createWindow, at: now) ? .newWindow : .sameWindow
        guard let next = spendCreate(record, at: now, branch: branch) else { return nil }
        return (record: next, spend: branch)
    }

    /// Belirli bir dalla harcama (sınır aşılırsa `nil`). Pencere sınırında sunucu seçilen dalı
    /// reddederse diğer dalla bir kez yeniden denemek için; `.newWindow` saati denetlemez.
    public static func spendCreate(_ record: UserRecord, at now: Date, branch: BudgetSpend) -> UserRecord? {
        var next = record
        switch branch {
        case .sameWindow:
            next.createUsed += 1
        case .newWindow:
            next.createWindow = now
            next.createUsed = 1
        }
        return next.createUsed <= createLimit(record, at: now) ? next : nil
    }

    // MARK: Kanıtlı kapatma

    /// Kanıtlı "Çözüldü" ile aynı yazımda yapılacak harcama; puan yetmezse `nil`.
    public static func spendClose(
        _ record: UserRecord,
        cost: Int,
        at now: Date
    ) -> (record: UserRecord, spend: BudgetSpend)? {
        let branch: BudgetSpend = windowEnded(record.closeWindow, at: now) ? .newWindow : .sameWindow
        guard let next = spendClose(record, cost: cost, at: now, branch: branch) else { return nil }
        return (record: next, spend: branch)
    }

    /// Belirli bir dalla harcama (bkz. `spendCreate(_:at:branch:)`).
    public static func spendClose(_ record: UserRecord, cost: Int, at now: Date, branch: BudgetSpend) -> UserRecord? {
        // Kurallar: closeLast.w in [1, 2].
        guard cost == 1 || cost == 2 else { return nil }
        var next = record
        switch branch {
        case .sameWindow:
            next.closeUsed += cost
        case .newWindow:
            next.closeWindow = now
            next.closeUsed = cost
        }
        return next.closeUsed <= closePoints ? next : nil
    }

    // MARK: Yardımcılar

    private static func windowEnded(_ start: Date, at now: Date) -> Bool {
        now >= start.addingTimeInterval(window + resetMargin)
    }

    private static func roundedUpToMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.up) * 60)
    }
}

extension ReportLifecycle {
    /// Bu kişinin şimdiki "Çözüldü" / "Artık yok" önerisi kanıtlı olabilir mi?
    /// Kurallardaki `credible()` ile aynı sıra: kayıt, itiraz sayısı, hesap yaşı (işareti koyan hariç), bütçe.
    public static func credibility(of report: Report, by userID: String, record: UserRecord?, at now: Date) -> CloseCredibility {
        guard let record else { return .noRecord }
        guard report.disputed.count <= Budget.credibleMaxDisputed else { return .disputed }
        guard report.reporterID == userID || !Budget.isNewAccount(record, at: now) else { return .newAccount }
        guard Budget.spendClose(record, cost: report.need.closeCost, at: now) != nil else { return .budgetUsed }
        return .credible
    }
}
