import AnimalKit
import FirebaseFirestore
import Foundation
import OSLog

private let log = Logger(subsystem: "app.patiharita", category: "firestore")

@MainActor
final class FirestoreReportRepository: ReportRepository {
    private typealias Field = FirestoreReportMapper.Field

    private let db: Firestore
    private let collection: CollectionReference

    init(db: Firestore) {
        self.db = db
        self.collection = db.collection(FirestoreReportMapper.collection)
    }

    func observeActiveReports(
        center: Coordinate,
        radiusMeters: Double,
        onChange: @escaping @MainActor ([Report]) -> Void
    ) -> ReportSubscription {
        // Firestore'da konum sorgusu: alanı kapsayan birkaç geohash aralığı, her biri ayrı dinlenir.
        let ranges = Geohash.queryBounds(center: center, radiusMeters: radiusMeters)
        var pages = [[Report]?](repeating: nil, count: ranges.count)

        let registrations: [ListenerRegistration] = ranges.enumerated().map { index, range in
            collection
                .whereField(Field.status, in: [ReportStatus.open.rawValue, ReportStatus.claimed.rawValue])
                .order(by: Field.geohash)
                .start(at: [range.start])
                .end(at: [range.end])
                .addSnapshotListener { snapshot, error in
                    // Firestore dinleyicileri ana kuyrukta çağırır.
                    if let snapshot {
                        pages[index] = snapshot.documents.compactMap {
                            FirestoreReportMapper.report(id: $0.documentID, data: $0.data())
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
                    onChange(Array(merged.values))
                }
        }

        return ReportSubscription {
            registrations.forEach { $0.remove() }
        }
    }

    func newReportID() -> String {
        collection.document().documentID
    }

    func create(_ report: Report, onFailure: @escaping @MainActor (Error) -> Void) {
        // Tamamlanmayı beklemeyiz: Firestore yazıyı yerelde hemen uygular (dinleyiciler anında görür)
        // ve çevrimdışıysa bağlantı gelince gönderir.
        collection.document(report.id).setData(FirestoreReportMapper.data(for: report)) { error in
            guard let error else { return }
            log.error("İşaret kaydedilemedi: \(error.localizedDescription, privacy: .public)")
            onFailure(error)
        }
    }

    func retract(reportID: String, onFailure: @escaping @MainActor (Error) -> Void) {
        collection.document(reportID).delete { error in
            guard let error else { return }
            log.error("İşaret geri alınamadı: \(error.localizedDescription, privacy: .public)")
            onFailure(error)
        }
    }

    func perform(_ action: ReportAction, onReportID reportID: String, by userID: String) async throws {
        let ref = collection.document(reportID)
        // İşlem bloğu Firestore'un arka plan kuyruğunda, gerekirse birkaç kez çalışır;
        // bu yüzden yalnızca saf mantık (ReportLifecycle) kullanır.
        let outcome = try await db.runTransaction { @Sendable transaction, errorPointer in
            Self.apply(action, to: ref, by: userID, in: transaction, errorPointer: errorPointer)
        }
        if let error = outcome as? Error {
            throw error
        }
    }

    /// Alan kuralı ihlali (ör. başkası az önce ilgilenmeye başladı) değer olarak döner;
    /// Firestore hataları `errorPointer` ile işlemi iptal eder.
    private nonisolated static func apply(
        _ action: ReportAction,
        to ref: DocumentReference,
        by userID: String,
        in transaction: Transaction,
        errorPointer: NSErrorPointer
    ) -> Any? {
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
        do {
            let updated = try ReportLifecycle.apply(action, to: report, by: userID, at: Date())
            transaction.updateData(FirestoreReportMapper.changes(from: report, to: updated), forDocument: ref)
            return nil
        } catch {
            return error
        }
    }
}
