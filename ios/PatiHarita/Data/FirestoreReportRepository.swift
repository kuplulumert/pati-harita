import AnimalKit
import FirebaseFirestore
import Foundation
import OSLog

private let log = Logger(subsystem: "app.patiharita", category: "firestore")

@MainActor
final class FirestoreReportRepository: ReportRepository {
    private typealias Field = FirestoreReportMapper.Field

    /// Süresi dolan işaretler (Spark'ta temizlik fonksiyonu yok) istemcilerce kapatılır: aynı anda en fazla
    /// bu kadarı, her biri rastgele bir beklemeden sonra (herkes aynı anda yazmasın).
    private static let maxExpiriesInFlight = 3
    private static let maxExpiryDelay: Double = 30

    private let db: Firestore
    private let collection: CollectionReference
    private let users: CollectionReference

    /// Oturum açan kullanıcı; süresi dolan işaretleri kapatırken kullanılır.
    private var userID: String?
    /// users/{me} dinleyicisinin son bildirdiği (ya da az önceki yeni işaretle güncellenmiş) kayıt.
    private var userRecord: UserRecord?
    private var userRecordObservers: [UUID: @MainActor (UserRecord?) -> Void] = [:]
    private var expiryAttempted: Set<String> = []
    private var expiriesInFlight = 0

    init(db: Firestore) {
        self.db = db
        self.collection = db.collection(FirestoreReportMapper.collection)
        self.users = db.collection(FirestoreReportMapper.usersCollection)
    }

    // MARK: Dinleme

    func observeActiveReports(
        center: Coordinate,
        radiusMeters: Double,
        onChange: @escaping @MainActor ([Report]) -> Void
    ) -> ReportSubscription {
        // Firestore'da konum sorgusu: alanı kapsayan birkaç geohash aralığı, her biri ayrı dinlenir.
        let ranges = Geohash.queryBounds(center: center, radiusMeters: radiusMeters)
        var pages = [[Report]?](repeating: nil, count: ranges.count)
        let statuses = [ReportStatus.open, .claimed, .closing].map(\.rawValue)

        let registrations: [ListenerRegistration] = ranges.enumerated().map { index, range in
            collection
                .whereField(Field.status, in: statuses)
                .order(by: Field.geohash)
                .start(at: [range.start])
                .end(at: [range.end])
                .addSnapshotListener { [weak self] snapshot, error in
                    // Firestore dinleyicileri ana kuyrukta çağırır.
                    if let snapshot {
                        pages[index] = snapshot.documents.compactMap {
                            FirestoreReportMapper.report(id: $0.documentID, data: $0.data(with: .estimate))
                        }
                    } else {
                        // Bir aralık başarısız olsa da diğerlerindeki işaretler gösterilsin.
                        log.error("İşaretler dinlenemedi: \(error?.localizedDescription ?? "-", privacy: .public)")
                        pages[index] = pages[index] ?? []
                    }
                    // Tüm aralıklar ilk sonucunu verene kadar bekle; yoksa işaretler bir an kaybolup geri gelir.
                    guard pages.allSatisfy({ $0 != nil }) else { return }
                    var merged: [String: Report] = [:]
                    for page in pages {
                        for report in page ?? [] {
                            merged[report.id] = report
                        }
                    }
                    let reports = Array(merged.values)
                    onChange(reports)
                    self?.expireDueReports(reports)
                }
        }

        return ReportSubscription {
            registrations.forEach { $0.remove() }
        }
    }

    func observeUserRecord(
        userID: String,
        onChange: @escaping @MainActor (UserRecord?) -> Void
    ) -> ReportSubscription {
        self.userID = userID
        let id = UUID()
        userRecordObservers[id] = onChange
        let registration = users.document(userID).addSnapshotListener { [weak self] snapshot, error in
            guard let snapshot else {
                // Son bilinen kayıt kalır; bağlantı gelince dinleyici kendini yeniler.
                log.error("Hesap kaydı dinlenemedi: \(error?.localizedDescription ?? "-", privacy: .public)")
                return
            }
            // Bekleyen yazımdaki sunucu saati (yeni pencere) yerel tahminle okunur; yoksa alan boş gelirdi.
            let record = snapshot.data(with: .estimate).flatMap { FirestoreReportMapper.userRecord(data: $0) }
            self?.setUserRecord(record)
        }
        return ReportSubscription { [weak self] in
            registration.remove()
            Task { @MainActor in self?.userRecordObservers[id] = nil }
        }
    }

    func observeClosingMode(onChange: @escaping @MainActor (ClosingMode) -> Void) -> ReportSubscription {
        let registration = db.collection(FirestoreReportMapper.configCollection)
            .document(FirestoreReportMapper.publicConfigDocument)
            .addSnapshotListener { snapshot, error in
                guard let snapshot else {
                    log.error("Gösterim modu okunamadı: \(error?.localizedDescription ?? "-", privacy: .public)")
                    return
                }
                onChange(FirestoreReportMapper.closingMode(data: snapshot.data()))
            }
        return ReportSubscription {
            registration.remove()
        }
    }

    private func setUserRecord(_ record: UserRecord?) {
        userRecord = record
        for observer in userRecordObservers.values {
            observer(record)
        }
    }

    // MARK: Hesap kaydı

    func ensureUserRecord(userID: String) async throws {
        self.userID = userID
        let ref = users.document(userID)
        _ = try await db.runTransaction { @Sendable transaction, errorPointer in
            Self.createUserIfMissing(ref, in: transaction, errorPointer: errorPointer)
        }
    }

    /// Kayıt varsa dokunulmaz: hesap yaşı ve haklar sıfırlanamasın (kurallar da güncellemeye izin vermez).
    private nonisolated static func createUserIfMissing(
        _ ref: DocumentReference,
        in transaction: Transaction,
        errorPointer: NSErrorPointer
    ) -> Any? {
        do {
            let snapshot = try transaction.getDocument(ref)
            if snapshot.exists { return nil }
        } catch {
            errorPointer?.pointee = error as NSError
            return nil
        }
        transaction.setData(FirestoreReportMapper.newUserData(), forDocument: ref)
        return nil
    }

    // MARK: Yeni işaret

    func newReportID() -> String {
        collection.document().documentID
    }

    func create(_ report: Report, onFailure: @escaping @MainActor (Error) -> Void) throws {
        let now = Date()
        let record = userRecord
        // Kayıt henüz okunmadıysa (ör. ilk açılışta çevrimdışı) sayaç artırılır; sunucu karar verir.
        var branch = BudgetSpend.sameWindow
        if let record {
            guard let spent = Budget.spendCreate(record, at: now) else {
                throw CreateQuotaError.exhausted(
                    limit: Budget.createLimit(record, at: now),
                    nextCreateAt: Budget.nextCreateAt(record, at: now)
                )
            }
            branch = spent.spend
            // Dinleyici yerel yazımı birazdan bildirir; arada konan ikinci işaret eski sayıyla denetlenmesin.
            setUserRecord(spent.record)
        }
        commitCreate(report, branch: branch, record: record, canRetry: true, onFailure: onFailure)
    }

    /// Tamamlanmayı beklemeyiz: Firestore yazıyı yerelde hemen uygular (dinleyiciler anında görür)
    /// ve çevrimdışıysa bağlantı gelince gönderir. İşaret ile hak harcaması tek toplu yazımdır.
    private func commitCreate(
        _ report: Report,
        branch: BudgetSpend,
        record: UserRecord?,
        canRetry: Bool,
        onFailure: @escaping @MainActor (Error) -> Void
    ) {
        let batch = db.batch()
        batch.setData(FirestoreReportMapper.data(for: report), forDocument: collection.document(report.id))
        batch.updateData(
            FirestoreReportMapper.createSpend(reportID: report.id, branch: branch),
            forDocument: users.document(report.reporterID)
        )
        batch.commit { [weak self] error in
            guard let error else { return }
            guard Self.isPermissionDenied(error), let record else {
                log.error("İşaret kaydedilemedi: \(error.localizedDescription, privacy: .public)")
                onFailure(error)
                return
            }
            // Pencere sınırında telefon saati sunucudan farklı dal seçmiş olabilir: bir kez diğer dalla.
            let other = branch.other
            if canRetry, let self,
               BudgetSpend.isNearEdge(of: record.createWindow, at: Date()),
               Budget.spendCreate(record, at: Date(), branch: other) != nil {
                log.notice("Yeni işaret hakkı diğer pencere dalıyla yeniden deneniyor.")
                self.commitCreate(report, branch: other, record: record, canRetry: false, onFailure: onFailure)
                return
            }
            log.error("İşaret günlük sınır nedeniyle reddedildi: \(error.localizedDescription, privacy: .public)")
            onFailure(CreateQuotaError.rejected)
        }
    }

    func retract(reportID: String, onFailure: @escaping @MainActor (Error) -> Void) {
        collection.document(reportID).delete { error in
            guard let error else { return }
            log.error("İşaret geri alınamadı: \(error.localizedDescription, privacy: .public)")
            onFailure(error)
        }
    }

    // MARK: Eylemler

    func perform(_ action: ReportAction, onReportID reportID: String, by userID: String) async throws -> ActionOutcome {
        let ref = collection.document(reportID)
        let userRef = users.document(userID)
        let spendLog = SpendLog()
        var attempt = CloseAttempt.automatic
        while true {
            let current = attempt
            do {
                // İşlem bloğu Firestore'un arka plan kuyruğunda, gerekirse birkaç kez çalışır;
                // bu yüzden yalnızca saf mantık (ReportLifecycle, Budget) kullanır.
                let result = try await db.runTransaction { @Sendable transaction, errorPointer in
                    Self.apply(
                        action,
                        to: ref,
                        userRef: userRef,
                        by: userID,
                        attempt: current,
                        spendLog: spendLog,
                        in: transaction,
                        errorPointer: errorPointer
                    )
                }
                if let error = result as? Error {
                    throw error
                }
                guard let outcome = result as? ActionOutcome else {
                    throw ReportError.notFound
                }
                return outcome
            } catch let error where Self.isPermissionDenied(error) {
                // Yalnızca kanıtlı öneri yeniden denenir (ör. pencere sınırında telefon saati ileride):
                // önce diğer dal, sonra kanıtsız. Diğer reddedilen eylemler olduğu gibi bildirilir.
                guard let branch = spendLog.branch, let next = current.retry(afterRejected: branch) else {
                    throw error
                }
                log.notice("Kanıtlı öneri reddedildi, yeniden deneniyor.")
                attempt = next
            }
        }
    }

    /// Alan kuralı ihlali (ör. başkası az önce ilgilenmeye başladı) değer olarak döner;
    /// Firestore hataları `errorPointer` ile işlemi iptal eder. Başarıda `ActionOutcome` döner.
    private nonisolated static func apply(
        _ action: ReportAction,
        to ref: DocumentReference,
        userRef: DocumentReference,
        by userID: String,
        attempt: CloseAttempt,
        spendLog: SpendLog,
        in transaction: Transaction,
        errorPointer: NSErrorPointer
    ) -> Any? {
        spendLog.branch = nil
        let snapshot: DocumentSnapshot
        do {
            snapshot = try transaction.getDocument(ref)
        } catch {
            errorPointer?.pointee = error as NSError
            return nil
        }
        guard let data = snapshot.data(),
              let report = FirestoreReportMapper.report(id: snapshot.documentID, data: data)
        else {
            return ReportError.notFound
        }

        let now = Date()
        var decision: CloseDecision?
        if ReportLifecycle.wouldStartClosing(action, on: report, by: userID, at: now) {
            // Hesap yaşı ve bütçe yalnızca öneri başlatan eylemde okunur (1 okuma). Yazımlardan önce
            // okunmalı: Firestore işlemlerinde tüm okumalar yazımlardan önce gelir.
            let userSnapshot: DocumentSnapshot
            do {
                userSnapshot = try transaction.getDocument(userRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            let record = userSnapshot.data().flatMap { FirestoreReportMapper.userRecord(data: $0) }
            decision = CloseDecision.make(report: report, userID: userID, record: record, at: now, attempt: attempt)
        }

        do {
            let updated = try ReportLifecycle.apply(
                action,
                to: report,
                by: userID,
                at: now,
                credible: decision?.credible ?? false
            )
            transaction.updateData(FirestoreReportMapper.changes(from: report, to: updated), forDocument: ref)
            if let spend = decision?.spend {
                // Kural (getAfter) bu harcamayı bu an ve bu işaretle eşleştirir; closingCredible: true ancak böyle geçer.
                transaction.updateData(
                    FirestoreReportMapper.closeSpend(reportID: report.id, spend: spend),
                    forDocument: userRef
                )
                spendLog.branch = spend.branch
            }
            return ActionOutcome(report: updated, credibility: decision?.credibility)
        } catch {
            return error
        }
    }

    // MARK: Takip sorusu

    func fetchReports(ids: [String]) async -> [Report] {
        guard !ids.isEmpty else { return [] }
        let collection = self.collection
        // Tek tek `get`: liste sorgusu gerekmez (Tier B'de listeleme kısıtlansa da çalışır), hepsi aynı anda.
        return await withCheckedContinuation { continuation in
            let batch = FetchBatch(count: ids.count)
            for id in ids {
                collection.document(id).getDocument { snapshot, error in
                    // Firestore geri çağrıları ana kuyrukta gelir.
                    var report: Report?
                    if let snapshot, let data = snapshot.data(with: .estimate) {
                        report = FirestoreReportMapper.report(id: snapshot.documentID, data: data)
                    } else if let error {
                        log.error("Takip edilen işaret okunamadı: \(error.localizedDescription, privacy: .public)")
                    }
                    if batch.finish(report) {
                        continuation.resume(returning: batch.reports)
                    }
                }
            }
        }
    }

    // MARK: Süresi dolanlar

    /// Spark'ta temizlik fonksiyonu yok: süresi dolan işaretleri gören istemciler kapatır. Kurallar yalnızca
    /// `expiresAt <= request.time` iken izin verir; yarışta (başkası önce kapattı) hata yok sayılır.
    private func expireDueReports(_ reports: [Report]) {
        guard let userID else { return }
        let now = Date()
        let due = reports.filter { ReportLifecycle.isDue($0, at: now) && !expiryAttempted.contains($0.id) }
        let slots = max(0, Self.maxExpiriesInFlight - expiriesInFlight)
        for report in due.prefix(slots) {
            let reportID = report.id
            expiryAttempted.insert(reportID)
            expiriesInFlight += 1
            let delay = Double.random(in: 0...Self.maxExpiryDelay)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                _ = try? await self?.perform(.expire, onReportID: reportID, by: userID)
                self?.expiriesInFlight -= 1
            }
        }
    }

    // MARK: Yardımcılar

    private nonisolated static func isPermissionDenied(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == FirestoreErrorDomain
            && error.code == FirestoreErrorCode.Code.permissionDenied.rawValue
    }
}

/// İşlem bloğunun son çalışmasında hangi dalla kanıtlı harcama yazıldığı. Blok arka plan kuyruğunda
/// çalışır; işlem reddedilince yeniden denemeye buradan bakılır.
private final class SpendLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedBranch: BudgetSpend?

    var branch: BudgetSpend? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedBranch
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedBranch = newValue
        }
    }
}

/// `fetchReports`: yanıtlar ana kuyrukta birer birer gelir; sonuncusu gelince hepsi döner.
private final class FetchBatch {
    private(set) var reports: [Report] = []
    private var remaining: Int

    init(count: Int) {
        remaining = count
    }

    /// Son yanıt buysa `true`.
    func finish(_ report: Report?) -> Bool {
        if let report {
            reports.append(report)
        }
        remaining -= 1
        return remaining == 0
    }
}
