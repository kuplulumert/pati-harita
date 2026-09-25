import AnimalKit
import Foundation
import Observation

/// A7: bu cihazda konulan, "Hâlâ orada" denen, üstüne alınan ya da itiraz edilen işaretler.
///
/// Uygulama öne gelince (en fazla `refreshInterval`'da bir) güncel hâlleri tek tek okunur; biri başkası
/// tarafından "Çözüldü dendi" yapıldıysa takip sorusu sorulur. Her "… dendi" önerisi için soruyu
/// yanıtlayıp yanıtlamadığı da burada tutulur: yanıtlamayan paydaş işareti görmeye devam eder
/// (bkz. `ClosingDisplay.look`). Yalnızca bu cihazda, `UserDefaults`'ta saklanır.
@MainActor
@Observable
final class WatchedReports {
    struct Entry: Codable, Equatable {
        let id: String
        /// Bu andan sonra unutulur: işaretin süresi + `keepAfterExpiry`.
        var keepUntil: Date
        /// Takip sorusunun yanıtlandığı öneri (öneri anı). Sonra gelen yeni öneri yeniden sorulur.
        var answeredClosingAt: Date?
    }

    static let maxCount = 50
    /// Süresi dolduktan sonra da bu kadar tutulur; geç açılan uygulama da işaretin sonunu öğrensin.
    static let keepAfterExpiry: TimeInterval = 24 * 3600
    static let refreshInterval: TimeInterval = 10 * 60
    private static let storageKey = "watchedReports.v1"

    private(set) var entries: [String: Entry] = [:]
    /// `nil`: yalnızca bellekte (demo; örnek işaret kimlikleri her açılışta yeniden kullanılır).
    private let defaults: UserDefaults?
    @ObservationIgnored private var lastRefresh: Date?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        prune(at: Date())
    }

    var ids: [String] { Array(entries.keys) }

    /// Kişi bu işaretle ilgilendi (koydu, gördü, üstüne aldı, itiraz etti): takip edilir.
    func watch(_ report: Report) {
        let keepUntil = report.expiresAt.addingTimeInterval(Self.keepAfterExpiry)
        var entry = entries[report.id] ?? Entry(id: report.id, keepUntil: keepUntil, answeredClosingAt: nil)
        entry.keepUntil = max(entry.keepUntil, keepUntil)
        entries[report.id] = entry
        trim()
        save()
    }

    func forget(_ reportID: String) {
        guard entries[reportID] != nil else { return }
        entries[reportID] = nil
        save()
    }

    /// Şimdiki "… dendi" önerisi için takip sorusu yanıtlandı mı?
    func isAnswered(_ report: Report) -> Bool {
        guard let closing = report.closing, let answered = entries[report.id]?.answeredClosingAt else { return false }
        // Sunucu damgası Date'e çevrilince mikro saniye oynayabilir; farklı öneriler saniyelerce arayla gelir.
        return abs(answered.timeIntervalSince(closing.at)) < 1
    }

    /// Takip sorusuna yanıt verildi ("Bilmiyorum" dahil). Paydaşın haritasında işaret artık başkalarınınki gibi görünür.
    func markAnswered(_ report: Report) {
        guard let closing = report.closing else { return }
        let keepUntil = report.expiresAt.addingTimeInterval(Self.keepAfterExpiry)
        var entry = entries[report.id] ?? Entry(id: report.id, keepUntil: keepUntil, answeredClosingAt: nil)
        entry.answeredClosingAt = closing.at
        entries[report.id] = entry
        trim()
        save()
    }

    /// Takip edilen işaret varsa ve son okumadan beri `refreshInterval` geçtiyse.
    func needsRefresh(at now: Date) -> Bool {
        guard !entries.isEmpty else { return false }
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= Self.refreshInterval
    }

    /// Okuma başladı: bu arada gelen öne gelme olayları yeniden okumasın.
    func beginRefresh(at now: Date) {
        lastRefresh = now
    }

    /// Okunan güncel hâller: kapananlar unutulur, uzayan ömürler kaydedilir, süresi geçenler atılır.
    func update(with reports: [Report], at now: Date) {
        for report in reports {
            guard var entry = entries[report.id] else { continue }
            if report.status == .closed {
                entries[report.id] = nil
                continue
            }
            entry.keepUntil = report.expiresAt.addingTimeInterval(Self.keepAfterExpiry)
            entries[report.id] = entry
        }
        prune(at: now)
    }

    // MARK: Saklama

    private func prune(at now: Date) {
        let kept = entries.filter { $0.value.keepUntil > now }
        if kept.count != entries.count {
            entries = kept
        }
        save()
    }

    /// En fazla `maxCount`: en önce unutulacaklar atılır.
    private func trim() {
        guard entries.count > Self.maxCount else { return }
        let dropped = entries.values
            .sorted { $0.keepUntil < $1.keepUntil }
            .prefix(entries.count - Self.maxCount)
        for entry in dropped {
            entries[entry.id] = nil
        }
    }

    private func save() {
        guard let defaults else { return }
        guard let data = try? JSONEncoder().encode(Array(entries.values)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
