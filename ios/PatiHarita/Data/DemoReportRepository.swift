import AnimalKit
import Foundation

/// Firebase olmadan uygulamayı denemek için bellek içi veri kaynağı.
/// Bakılan bölgede hiç işaret yoksa oraya örnek işaretler koyar.
@MainActor
final class DemoReportRepository: ReportRepository {
    static let demoUserID = "demo-user"
    /// Bakılan yerin bu kadar yakınında hiç işaret yoksa oraya örnekler konur. Sorgu yarıçapından
    /// bağımsızdır: geniş bir görünümün yarıçapı birkaç km olabilir ve uzaktaki örnekleri "yakında" sayardı.
    static let seedSpacing: Double = 1_000
    /// Demo hesabı birkaç gün önce açılmış sayılır: "Çözüldü" kanıtlı olur (ilk gün sınırı yok).
    static let demoAccountAge: TimeInterval = 3 * 24 * 3600
    /// Demoda kanıtlı "Çözüldü" başkalarının haritasından kalkar (TestFlight'taki mod).
    static let closingMode: ClosingMode = .demote

    private var reports: [String: Report] = [:]
    private var observers: [UUID: @MainActor ([Report]) -> Void] = [:]
    private var recordObservers: [UUID: @MainActor (UserRecord?) -> Void] = [:]
    private var seedCount = 0
    /// Demo kullanıcısının `users/{uid}` karşılığı: günlük haklar bellekte sayılır.
    private var userRecord: UserRecord

    init(now: Date = Date()) {
        let createdAt = now.addingTimeInterval(-Self.demoAccountAge)
        userRecord = UserRecord.new(at: createdAt)
    }

    // MARK: Dinleme

    func observeActiveReports(
        center: Coordinate,
        radiusMeters: Double,
        onChange: @escaping @MainActor ([Report]) -> Void
    ) -> ReportSubscription {
        // Demo: bakılan yerin yakınında hiç işaret yoksa oraya örnekler koy.
        if !reports.values.contains(where: { $0.coordinate.distance(to: center) < Self.seedSpacing }) {
            seed(around: center)
        }
        let id = UUID()
        observers[id] = onChange
        onChange(activeReports)
        return ReportSubscription { [weak self] in
            Task { @MainActor in self?.observers[id] = nil }
        }
    }

    func observeUserRecord(
        userID: String,
        onChange: @escaping @MainActor (UserRecord?) -> Void
    ) -> ReportSubscription {
        let id = UUID()
        recordObservers[id] = onChange
        onChange(userID == Self.demoUserID ? userRecord : nil)
        return ReportSubscription { [weak self] in
            Task { @MainActor in self?.recordObservers[id] = nil }
        }
    }

    func observeClosingMode(onChange: @escaping @MainActor (ClosingMode) -> Void) -> ReportSubscription {
        onChange(Self.closingMode)
        return ReportSubscription {}
    }

    func ensureUserRecord(userID: String) async throws {
        // Demo kaydı başlangıçta hazır.
    }

    // MARK: Yeni işaret

    func newReportID() -> String {
        UUID().uuidString
    }

    func create(_ report: Report, onFailure: @escaping @MainActor (Error) -> Void) throws {
        let now = Date()
        guard let spent = Budget.spendCreate(userRecord, at: now) else {
            throw CreateQuotaError.exhausted(
                limit: Budget.createLimit(userRecord, at: now),
                nextCreateAt: Budget.nextCreateAt(userRecord, at: now)
            )
        }
        userRecord = spent.record
        reports[report.id] = report
        notify()
        notifyRecord()
    }

    func retract(reportID: String, onFailure: @escaping @MainActor (Error) -> Void) {
        // Harcanan hak geri verilmez (kurallar da azaltmaya izin vermez).
        guard let report = reports[reportID], ReportLifecycle.canRetract(report, by: Self.demoUserID) else {
            onFailure(ReportError.notAllowed)
            return
        }
        reports[reportID] = nil
        notify()
    }

    // MARK: Eylemler

    func perform(_ action: ReportAction, onReportID reportID: String, by userID: String) async throws -> ActionOutcome {
        guard reports[reportID] != nil else { throw ReportError.notFound }
        // Ağ gecikmesini taklit et; düğmedeki bekleme durumu görülebilsin.
        try await Task.sleep(for: .milliseconds(300))
        // Beklerken değişmiş olabilir: sunucudaki gibi güncel hâle uygulanır.
        guard let report = reports[reportID] else { throw ReportError.notFound }
        let now = Date()
        var decision: CloseDecision?
        if ReportLifecycle.wouldStartClosing(action, on: report, by: userID, at: now) {
            decision = CloseDecision.make(
                report: report,
                userID: userID,
                record: userID == Self.demoUserID ? userRecord : nil,
                at: now,
                attempt: .automatic
            )
        }
        let updated = try ReportLifecycle.apply(action, to: report, by: userID, at: now, credible: decision?.credible ?? false)
        reports[reportID] = updated
        if let spend = decision?.spend {
            userRecord = spend.record
            notifyRecord()
        }
        notify()
        return ActionOutcome(report: updated, credibility: decision?.credibility)
    }

    func fetchReports(ids: [String]) async -> [Report] {
        ids.compactMap { reports[$0] }
    }

    // MARK: Yardımcılar

    private var activeReports: [Report] {
        let now = Date()
        return reports.values.filter { $0.isActive(at: now) }
    }

    private func notify() {
        let active = activeReports
        for observer in observers.values {
            observer(active)
        }
    }

    private func notifyRecord() {
        for observer in recordObservers.values {
            observer(userRecord)
        }
    }

    private func seed(around center: Coordinate) {
        seedCount += 1
        let now = Date()
        let samples: [(Species, Need, Double, Double, TimeInterval, String?, Int)] = [
            // tür, ihtiyaç, kuzey (m), doğu (m), kaç dakika önce, ilgilenen, kaç kişi bildirdi
            // Arayüz testi yaralı kedinin 3 kişiyle başladığını (demo kullanıcısı hariç) varsayar.
            (.cat, .injured, 120, -80, 12, nil, 3),
            (.dog, .food, -200, 150, 95, nil, 2),
            (.cat, .babies, 260, 240, 300, "komsu", 1),
            (.dog, .emergency, -90, -260, 4, nil, 6),
            (.bird, .vet, 380, -30, 40, nil, 1),
            (.cat, .shelter, -330, -120, 900, nil, 1),
            (.other, .other, 60, 380, 600, nil, 1),
        ]
        for (index, sample) in samples.enumerated() {
            let (species, need, north, east, minutesAgo, helper, seers) = sample
            let createdAt = now.addingTimeInterval(-minutesAgo * 60)
            var report = ReportLifecycle.makeReport(
                id: "demo-\(seedCount)-\(index)",
                species: species,
                need: need,
                at: Self.offset(center, north: north, east: east),
                reporterID: "someone-else",
                now: createdAt
            )
            // İşareti koyandan sonra başkaları da "Hâlâ orada" demiş (aradaki zamana yayılır).
            for passerBy in 1..<max(seers, 1) {
                let seenAt = createdAt.addingTimeInterval(minutesAgo * 60 * Double(passerBy) / Double(seers))
                if let seen = try? ReportLifecycle.apply(.confirmStillThere, to: report, by: "passer-by-\(passerBy)", at: seenAt) {
                    report = seen
                }
            }
            if let helper, let claimed = try? ReportLifecycle.apply(.claim, to: report, by: helper, at: now.addingTimeInterval(-20 * 60)) {
                report = claimed
            }
            reports[report.id] = report
        }

        // "Çözüldü dendi" örneği: yoldan geçen biri 20 dk önce dedi, bütçesiz (doğrulanmadı). Haritada "?"
        // rozetiyle kalır ve itiraz ("Hâlâ yardım gerekiyor") akışı denenebilir. Etiketi ("Yaralı / hasta,
        // Köpek") diğer örneklerden ayrılır; arayüz testi onu bununla bulur.
        let closingCreatedAt = now.addingTimeInterval(-90 * 60)
        var closing = ReportLifecycle.makeReport(
            id: "demo-\(seedCount)-\(samples.count)",
            species: .dog,
            need: .injured,
            at: Self.offset(center, north: -260, east: 20),
            reporterID: "someone-else",
            now: closingCreatedAt
        )
        if let seen = try? ReportLifecycle.apply(.confirmStillThere, to: closing, by: "passer-by-1", at: now.addingTimeInterval(-60 * 60)) {
            closing = seen
        }
        if let proposed = try? ReportLifecycle.apply(.resolve, to: closing, by: "passer-by-2", at: now.addingTimeInterval(-20 * 60)) {
            closing = proposed
        }
        reports[closing.id] = closing
    }

    /// Merkezden metre cinsinden kaydırılmış nokta.
    private static func offset(_ center: Coordinate, north: Double, east: Double) -> Coordinate {
        Coordinate(
            latitude: center.latitude + north / 111_320,
            longitude: center.longitude + east / (111_320 * cos(center.latitude * .pi / 180))
        )
    }
}
