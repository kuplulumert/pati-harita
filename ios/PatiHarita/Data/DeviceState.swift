import AnimalKit
import Foundation
import Observation

/// Yalnızca bu cihazda tutulan küçük durum: kabul edilen kurallar, "Yardıma ihtiyacı var mı?" sayaçları,
/// kişinin haritasından kaldırdığı işaretler, gece hatırlatmasının son gösterimi, ilk gidişteki güvenlik uyarısı,
/// engel bilgisi ve "Hâlâ orada mı?" kaydı (sorulan işaretler, sıklık).
///
/// `UserDefaults`'ta saklanır. `defaults` `nil` ise (`-demo` argümanı, arayüz testi) hiçbir şey saklanmaz: test
/// her seferinde ilk açılıştaki gibi başlar. `persistsReports` `false` ise (plist'siz demo derlemesi, ör. TestFlight)
/// cihaza ait olanlar (kabul edilen kurallar, hafif işaret sayacı, gece hatırlatması, güvenlik uyarısı) saklanır;
/// işaret kimliklerine bağlı olanlar (gizlenen ve son 24 saatin işaretleri, "Hâlâ orada mı?" kaydı) ve demo
/// kimliğinin engel bilgisi yalnızca bellektedir, çünkü örnek işaretlerin kimlikleri her açılışta yeniden kullanılır.
@MainActor
@Observable
final class DeviceState {
    /// Bu cihazda konan bir işaret (acil yardım hariç); `GentleCheck.recentWindow` sonra unutulur.
    struct RecentReport: Codable, Equatable {
        let id: String
        let at: Date
    }

    /// Gizlenen işaret bu kadar sonra unutulur: hiçbir işaret `ReportLifecycle.maxAge`'den uzun yaşamaz.
    static let hiddenRetention: TimeInterval = ReportLifecycle.maxAge + 24 * 3600

    private enum Key {
        static let acceptedTermsVersion = "acceptedTermsVersion"
        static let lightReportCount = "gentleCheck.lightReports"
        static let recentReports = "gentleCheck.recentReports.v1"
        static let hiddenReports = "hiddenReports.v1"
        static let nightReminderShownAt = "nightReminder.shownAt"
        static let goSafetyTipShown = "goSafetyTip.shown"
        static let knownBanned = "banned.known"
        static let nearbyAsked = "nearbyPrompt.asked.v1"
        static let nearbyLog = "nearbyPrompt.log.v1"
    }

    /// Kabul edilen kurallar sürümü (`AppInfo.termsVersion`); hiç kabul edilmediyse 0.
    private(set) var acceptedTermsVersion = 0
    /// "Bu işareti bildir" ya da "Bu işareti gizle" denen işaretler ve o an.
    private(set) var hiddenReports: [String: Date] = [:]
    /// Bu cihazın şimdiye kadar koyduğu hafif işaret sayısı (`Need.needsGentleCheck`).
    @ObservationIgnored private(set) var lightReportCount = 0
    @ObservationIgnored private var recentReports: [RecentReport] = []
    @ObservationIgnored private(set) var nightReminderShownAt: Date? = nil
    /// "Yardıma gidiyorsun" uyarısı ya da onun yerine gece hatırlatması bu cihazda gösterildi (ilk "İlgileniyorum"
    /// ya da "Yol tarifi").
    @ObservationIgnored private(set) var goSafetyTipShown = false
    /// Son bakıldığında bu kimlik engelliydi: açılışta yeniden bakılır.
    @ObservationIgnored private(set) var knownBanned = false
    /// "Hâlâ orada mı?" sorulan işaretler ve soruldukları an: aynı işaret bir daha sorulmaz.
    @ObservationIgnored private var nearbyAsked: [String: Date] = [:]
    /// "Hâlâ orada mı?" sıklığı (son 24 saatin gösterimleri, yanıtsız serisi, sessizlik).
    @ObservationIgnored private var nearbyLog = NearbyPrompt.Log()

    /// Cihaza ait olanlar: kabul edilen kurallar, hafif işaret sayacı, gece hatırlatması, güvenlik uyarısı.
    private let defaults: UserDefaults?
    /// İşaret kimliklerine ve kimliğe bağlı olanlar: gizlenen ve son 24 saatin işaretleri, engel bilgisi.
    private let reportDefaults: UserDefaults?

    init(defaults: UserDefaults?, persistsReports: Bool = true, now: Date = Date()) {
        let reportDefaults = persistsReports ? defaults : nil
        self.defaults = defaults
        self.reportDefaults = reportDefaults
        acceptedTermsVersion = defaults?.integer(forKey: Key.acceptedTermsVersion) ?? 0
        lightReportCount = defaults?.integer(forKey: Key.lightReportCount) ?? 0
        nightReminderShownAt = defaults?.object(forKey: Key.nightReminderShownAt) as? Date
        goSafetyTipShown = defaults?.bool(forKey: Key.goSafetyTipShown) ?? false
        recentReports = Self.decode([RecentReport].self, from: reportDefaults?.data(forKey: Key.recentReports)) ?? []
        hiddenReports = Self.decode([String: Date].self, from: reportDefaults?.data(forKey: Key.hiddenReports)) ?? [:]
        knownBanned = reportDefaults?.bool(forKey: Key.knownBanned) ?? false
        nearbyAsked = Self.decode([String: Date].self, from: reportDefaults?.data(forKey: Key.nearbyAsked)) ?? [:]
        nearbyLog = Self.decode(NearbyPrompt.Log.self, from: reportDefaults?.data(forKey: Key.nearbyLog)) ?? NearbyPrompt.Log()
        prune(at: now)
    }

    // MARK: Kurallar

    func acceptTerms(version: Int) {
        guard acceptedTermsVersion != version else { return }
        acceptedTermsVersion = version
        defaults?.set(version, forKey: Key.acceptedTermsVersion)
    }

    // MARK: Yeni işaretler

    /// Yeni işaret kaydedildi: hafifse sayaç artar, acil değilse son 24 saate eklenir.
    func recordReport(id: String, need: Need, at now: Date) {
        if need.needsGentleCheck {
            lightReportCount += 1
            defaults?.set(lightReportCount, forKey: Key.lightReportCount)
        }
        if need != .emergency {
            recentReports.append(RecentReport(id: id, at: now))
        }
        prune(at: now)
        saveRecentReports()
    }

    /// İşaret geri alındı, silindi ya da sunucu reddetti: son 24 saatten çıkar. Hafif sayaç azalmaz; kontrolü
    /// o işaret için zaten görmüştü.
    func forgetReport(id: String) {
        let kept = recentReports.filter { $0.id != id }
        guard kept.count != recentReports.count else { return }
        recentReports = kept
        saveRecentReports()
    }

    /// Bu cihazın son 24 saatte koyduğu, acil olmayan işaretler.
    func recentReportCount(at now: Date) -> Int {
        recentReports.filter { GentleCheck.isRecent($0.at, at: now) }.count
    }

    // MARK: Gizlenen işaretler

    func isHidden(_ reportID: String) -> Bool {
        hiddenReports[reportID] != nil
    }

    func hide(_ reportID: String, at now: Date) {
        hiddenReports[reportID] = now
        prune(at: now)
        save(hiddenReports, forKey: Key.hiddenReports)
    }

    // MARK: Güvenlik hatırlatmaları ve engel

    func markNightReminderShown(at now: Date) {
        nightReminderShownAt = now
        defaults?.set(now, forKey: Key.nightReminderShownAt)
    }

    func markGoSafetyTipShown() {
        guard !goSafetyTipShown else { return }
        goSafetyTipShown = true
        defaults?.set(true, forKey: Key.goSafetyTipShown)
    }

    func setKnownBanned(_ banned: Bool) {
        guard knownBanned != banned else { return }
        knownBanned = banned
        reportDefaults?.set(banned, forKey: Key.knownBanned)
    }

    // MARK: "Hâlâ orada mı?"

    /// Daha önce sorulan işaretler (`NearbyPrompt.askedRetention` içinde).
    func nearbyAskedIDs(at now: Date) -> Set<String> {
        Set(NearbyPrompt.prunedAsked(nearbyAsked, at: now).keys)
    }

    /// Soru gösterildiği an işaret "soruldu" sayılır: yanıtlanmasa da bir daha sorulmaz.
    func markNearbyAsked(_ reportID: String, at now: Date) {
        nearbyAsked[reportID] = now
        nearbyAsked = NearbyPrompt.prunedAsked(nearbyAsked, at: now)
        save(nearbyAsked, forKey: Key.nearbyAsked)
    }

    func nearbyPromptLog(at now: Date) -> NearbyPrompt.Log {
        nearbyLog.pruned(at: now)
    }

    /// Gösterim, yanıt, yanıtsız kalma (3 kez üst üste: 7 gün sessizlik) ya da kesilme.
    func recordNearbyPrompt(_ result: NearbyPrompt.Result, at now: Date) {
        var log = nearbyLog
        log.record(result, at: now)
        guard log != nearbyLog else { return }
        nearbyLog = log
        save(nearbyLog, forKey: Key.nearbyLog)
    }

    // MARK: Saklama

    private func prune(at now: Date) {
        let recent = recentReports.filter { GentleCheck.isRecent($0.at, at: now) }
        if recent.count != recentReports.count {
            recentReports = recent
            saveRecentReports()
        }
        let hidden = hiddenReports.filter { now.timeIntervalSince($0.value) < Self.hiddenRetention }
        if hidden.count != hiddenReports.count {
            hiddenReports = hidden
            save(hiddenReports, forKey: Key.hiddenReports)
        }
        let asked = NearbyPrompt.prunedAsked(nearbyAsked, at: now)
        if asked.count != nearbyAsked.count {
            nearbyAsked = asked
            save(nearbyAsked, forKey: Key.nearbyAsked)
        }
        let log = nearbyLog.pruned(at: now)
        if log != nearbyLog {
            nearbyLog = log
            save(nearbyLog, forKey: Key.nearbyLog)
        }
    }

    private func saveRecentReports() {
        save(recentReports, forKey: Key.recentReports)
    }

    /// Yalnızca işaret kimliklerine bağlı listeler (`reportDefaults`) için.
    private func save<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let reportDefaults, let data = try? JSONEncoder().encode(value) else { return }
        reportDefaults.set(data, forKey: key)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
