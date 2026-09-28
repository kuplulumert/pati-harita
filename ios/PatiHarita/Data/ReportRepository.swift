import AnimalKit
import Foundation

/// Haritanın veri kaynağı. `FirestoreReportRepository` (gerçek) ve
/// `DemoReportRepository` (bellek içi) uygulamaları vardır.
@MainActor
protocol ReportRepository: AnyObject {
    /// Merkez çevresindeki aktif (açık / ilgilenilen / "… dendi") işaretleri canlı izler.
    /// Dönen abonelik iptal edilene ya da bırakılana kadar `onChange` her değişiklikte çağrılır.
    func observeActiveReports(
        center: Coordinate,
        radiusMeters: Double,
        onChange: @escaping @MainActor ([Report]) -> Void
    ) -> ReportSubscription

    /// `users/{userID}`: hesap yaşı ve 24 saatlik haklar. Kayıt yoksa (henüz oluşturulmadıysa) `nil`.
    func observeUserRecord(
        userID: String,
        onChange: @escaping @MainActor (UserRecord?) -> Void
    ) -> ReportSubscription

    /// `config/public`: kanıtlı "… dendi"nin başkalarının haritasında nasıl göründüğü ve desteklenen en eski
    /// derleme. Doküman yoksa `PublicConfig.fallback`; okunamazsa son bilinen değer kalır.
    func observePublicConfig(onChange: @escaping @MainActor (PublicConfig) -> Void) -> ReportSubscription

    /// Anonim girişten hemen sonra `users/{userID}` yoksa oluşturur (hesap yaşı buradan sayılır). Ağ gerekir.
    func ensureUserRecord(userID: String) async throws

    /// Yeni işaret için kimlik. Ağ gerektirmez.
    func newReportID() -> String

    /// İşareti kaydeder ve aynı yazımda günlük haktan bir tane harcar. Beklemez: işaret anında haritada
    /// görünür, çevrimdışıysa bağlantı gelince gönderilir. Hak bittiği biliniyorsa hiçbir şey yazmadan
    /// `CreateQuotaError.exhausted` fırlatır. Sunucu reddederse `onFailure` çağrılır (günlük sınır
    /// yüzündense `CreateQuotaError.rejected`, işaret çok geç gönderildiyse `CreateQuotaError.tooLate` ile).
    func create(_ report: Report, onFailure: @escaping @MainActor (Error) -> Void) throws

    /// "Geri al" ya da "İşareti sil": koyanın, kimsenin dokunmadığı işaretini siler (`ReportLifecycle.canRetract`).
    /// Beklemez; bu arada biri işlem yaptıysa sunucu reddeder ve `onFailure` çağrılır (kurallar reddettiyse
    /// `RepositoryError.permissionDenied` ile).
    func retract(reportID: String, onFailure: @escaping @MainActor (Error) -> Void)

    /// Bir eylemi (İlgileniyorum, Çözüldü…) sunucudaki güncel hâl üzerine uygular. Eylem "… dendi"
    /// önerisi başlatıyorsa kanıtlılığı hesaplar; kanıtlıysa aynı yazımda kapatma bütçesinden harcar.
    /// Kurallar reddederse `RepositoryError.permissionDenied`.
    func perform(_ action: ReportAction, onReportID reportID: String, by userID: String) async throws -> ActionOutcome

    /// "Düzenle": işareti koyan yanlış seçtiği türü, ihtiyacı ya da konumu düzeltir (`ReportLifecycle.edit`).
    /// Sunucudaki güncel hâl üzerine uygulanır: bu arada başkası dokunduysa ya da süre geçtiyse
    /// `ReportError.notEditable`, konum çok uzaksa `ReportError.editTooFar`; kurallar reddederse
    /// `RepositoryError.permissionDenied`. Ağ gerekir.
    func edit(
        reportID: String,
        species: Species,
        need: Need,
        coordinate: Coordinate,
        by userID: String
    ) async throws -> Report

    /// "Bu işareti bildir": `flags/{reportId}_{uid}`. Beklemez; çevrimdışıysa bağlantı gelince gönderilir.
    /// Sunucu reddederse `onRejected` çağrılır: çoğunlukla bu kişi işareti zaten bildirmiştir (kurallar ikinci
    /// bildirimi reddeder) ve uygulama bunu başarı sayar; ama kimlik engellenmiş de olabilir.
    func flag(reportID: String, reason: FlagReason, by userID: String, onRejected: @escaping @MainActor () -> Void)

    /// `banned/{userID}` var mı (kimlik konsoldan engellendi mi)? Okunamazsa `nil`.
    func isBanned(userID: String) async -> Bool?

    /// Takip sorusu (A7) için işaretlerin güncel hâli; kapanmışlar da döner. Bulunamayan ya da
    /// okunamayanlar atlanır.
    func fetchReports(ids: [String]) async -> [Report]
}

/// `config/public`: yalnızca konsoldan yazılan uzaktan ayarlar.
struct PublicConfig: Equatable, Sendable {
    /// Kanıtlı "… dendi"nin başkalarının haritasında nasıl göründüğü.
    var closingMode: ClosingMode
    /// `minBuild`: bundan eski derlemeler (CFBundleVersion) "Güncelleme gerekli" der. Yoksa `nil`.
    var minBuild: Int?

    static let fallback = PublicConfig(closingMode: .fallback, minBuild: nil)
}

/// Depo hataları (AnimalKit'in `ReportError`ı dışında).
enum RepositoryError: Error, Equatable {
    /// Güvenlik kuralları yazımı reddetti: işaretin sunucudaki hâli istemcinin bildiğinden farklı ya da
    /// kimlik engellenmiş (uygulama bu durumda `banned/{uid}`'e bir kez bakar).
    case permissionDenied
}

/// Canlı dinlemeyi temsil eder; `cancel()` ya da nesnenin bırakılması dinlemeyi bitirir.
final class ReportSubscription {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }

    deinit {
        onCancel?()
    }
}

/// Bir eylemin sonucu; bildirim metni buna göre seçilir.
struct ActionOutcome: Equatable, Sendable {
    /// Eylemden sonraki hâl (istemci saatiyle; sunucu damgaları birkaç saniye farklı olabilir).
    let report: Report
    /// Eylem "… dendi" önerisi başlattıysa kanıtlılığı; başlatmadıysa `nil`.
    let credibility: CloseCredibility?

    /// Bu kişi az önce "Çözüldü" / "Artık yok" önerisi yaptı (işaret onun haritasından kalkar, "Geri al" açılır).
    var startedClosing: Bool { credibility != nil }
}

/// Yeni işaret hakkı: son 24 saatte 10 (hesabın ilk gününde 5).
enum CreateQuotaError: Error, Equatable {
    /// Hak bitti; işaret kaydedilmedi. `nextCreateAt`: yeni hakkın açılacağı an.
    case exhausted(limit: Int, nextCreateAt: Date?)
    /// Sunucu, günlük sınır yüzünden reddetti (çoğunlukla çevrimdışı konan işaret sonradan gönderilince).
    case rejected
    /// Sunucu reddetti ve işaret neredeyse 24 saat önce konmuştu: kurallar (`maxBackdate`) bu kadar geç
    /// gelen işareti kabul etmez; sebep günlük sınır değil, gecikmedir.
    case tooLate
}

/// Kanıtlı öneri hangi yolla denensin. Sunucu kanıtlı öneriyi reddederse (ör. pencere sınırında telefon
/// saati ileride) önce bir kez diğer dal, o da olmazsa kanıtsız denenir: kullanıcının "Çözüldü"sü kaybolmaz.
enum CloseAttempt: Equatable, Sendable {
    case automatic
    case otherBranch(than: BudgetSpend)
    case notCredible

    /// `branch` dalıyla yapılan kanıtlı deneme reddedildikten sonraki deneme; yoksa `nil`.
    func retry(afterRejected branch: BudgetSpend) -> CloseAttempt? {
        switch self {
        case .automatic: .otherBranch(than: branch)
        case .otherBranch: .notCredible
        case .notCredible: nil
        }
    }
}

/// "… dendi" başlatan eylem için kanıtlılık kararı ve bütçe harcaması. İki depo da aynı kararı verir.
struct CloseDecision: Sendable {
    struct Spend: Sendable {
        /// Harcamadan sonraki kayıt.
        let record: UserRecord
        let branch: BudgetSpend
        /// `closeLast.w`: işaretin ihtiyacına göre 1 ya da 2 puan.
        let cost: Int
    }

    let credibility: CloseCredibility
    /// Kanıtlıysa aynı yazımda yapılacak harcama.
    let spend: Spend?

    var credible: Bool { spend != nil }

    /// Yalnızca `ReportLifecycle.wouldStartClosing` doğruyken çağrılır.
    static func make(
        report: Report,
        userID: String,
        record: UserRecord?,
        at now: Date,
        attempt: CloseAttempt
    ) -> CloseDecision {
        let credibility = ReportLifecycle.credibility(of: report, by: userID, record: record, at: now)
        guard credibility == .credible, let record else {
            return CloseDecision(credibility: credibility, spend: nil)
        }
        let cost = report.need.closeCost
        switch attempt {
        case .automatic:
            guard let spent = Budget.spendClose(record, cost: cost, at: now) else {
                return CloseDecision(credibility: .budgetUsed, spend: nil)
            }
            return CloseDecision(
                credibility: .credible,
                spend: Spend(record: spent.record, branch: spent.spend, cost: cost)
            )
        case .otherBranch(let rejected):
            let branch = rejected.other
            if BudgetSpend.isNearEdge(of: record.closeWindow, at: now),
               let next = Budget.spendClose(record, cost: cost, at: now, branch: branch) {
                return CloseDecision(credibility: .credible, spend: Spend(record: next, branch: branch, cost: cost))
            }
            // Sunucu kanıtlı öneriyi kabul etmedi; kayıt okunamamış gibi kanıtsız yazılır.
            return CloseDecision(credibility: .noRecord, spend: nil)
        case .notCredible:
            return CloseDecision(credibility: .noRecord, spend: nil)
        }
    }
}

extension BudgetSpend {
    /// Pencere sınırında istemci ile sunucu farklı dal seçebilir; yeniden denemede bu pay kullanılır.
    static let edgeTolerance: TimeInterval = 60 * 60

    var other: BudgetSpend {
        self == .sameWindow ? .newWindow : .sameWindow
    }

    /// Şimdi, `windowStart` ile başlayan 24 saatlik pencerenin sonuna yakın mı (iki yönde de)?
    static func isNearEdge(of windowStart: Date, at now: Date) -> Bool {
        abs(now.timeIntervalSince(windowStart.addingTimeInterval(Budget.window))) <= edgeTolerance
    }
}
