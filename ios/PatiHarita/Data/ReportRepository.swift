import AnimalKit
import Foundation

/// Haritanın veri kaynağı. `FirestoreReportRepository` (gerçek) ve
/// `DemoReportRepository` (bellek içi) uygulamaları vardır.
@MainActor
protocol ReportRepository: AnyObject {
    /// Merkez çevresindeki aktif (açık / ilgilenilen) işaretleri canlı izler.
    /// Dönen abonelik iptal edilene ya da bırakılana kadar `onChange` her değişiklikte çağrılır.
    func observeActiveReports(
        center: Coordinate,
        radiusMeters: Double,
        onChange: @escaping @MainActor ([Report]) -> Void
    ) -> ReportSubscription

    /// Yeni işaret için kimlik. Ağ gerektirmez.
    func newReportID() -> String

    /// İşareti kaydeder. Beklemez: işaret anında haritada görünür, çevrimdışıysa
    /// bağlantı gelince gönderilir. Sunucu reddederse `onFailure` çağrılır.
    func create(_ report: Report, onFailure: @escaping @MainActor (Error) -> Void)

    /// "Geri al": az önce koyulan işareti siler. Bu arada biri işlem yaptıysa sunucu reddeder.
    func retract(reportID: String, onFailure: @escaping @MainActor (Error) -> Void)

    /// Bir eylemi (İlgileniyorum, Çözüldü…) sunucudaki güncel hâl üzerine uygular.
    func perform(_ action: ReportAction, onReportID reportID: String, by userID: String) async throws
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
