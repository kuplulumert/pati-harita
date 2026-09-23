import AnimalKit
import Foundation

/// Firebase olmadan uygulamayı denemek için bellek içi veri kaynağı.
/// Bakılan bölgede hiç işaret yoksa oraya örnek işaretler koyar.
@MainActor
final class DemoReportRepository: ReportRepository {
    static let demoUserID = "demo-user"

    private var reports: [String: Report] = [:]
    private var observers: [UUID: @MainActor ([Report]) -> Void] = [:]
    private var seedCount = 0

    func observeActiveReports(
        center: Coordinate,
        radiusMeters: Double,
        onChange: @escaping @MainActor ([Report]) -> Void
    ) -> ReportSubscription {
        // Demo: bakılan bölgede hiç işaret yoksa oraya örnekler koy.
        if !reports.values.contains(where: { $0.coordinate.distance(to: center) < radiusMeters }) {
            seed(around: center)
        }
        let id = UUID()
        observers[id] = onChange
        onChange(activeReports)
        return ReportSubscription { [weak self] in
            Task { @MainActor in self?.observers[id] = nil }
        }
    }

    func newReportID() -> String {
        UUID().uuidString
    }

    func create(_ report: Report, onFailure: @escaping @MainActor (Error) -> Void) {
        reports[report.id] = report
        notify()
    }

    func retract(reportID: String, onFailure: @escaping @MainActor (Error) -> Void) {
        guard let report = reports[reportID], ReportLifecycle.canRetract(report, by: Self.demoUserID) else {
            onFailure(ReportError.notAllowed)
            return
        }
        reports[reportID] = nil
        notify()
    }

    func perform(_ action: ReportAction, onReportID reportID: String, by userID: String) async throws {
        guard let report = reports[reportID] else { throw ReportError.notFound }
        // Ağ gecikmesini taklit et; düğmedeki bekleme durumu görülebilsin.
        try await Task.sleep(for: .milliseconds(300))
        reports[reportID] = try ReportLifecycle.apply(action, to: report, by: userID, at: Date())
        notify()
    }

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

    private func seed(around center: Coordinate) {
        seedCount += 1
        let now = Date()
        let samples: [(Species, Need, Double, Double, TimeInterval, String?)] = [
            // tür, ihtiyaç, kuzey (m), doğu (m), kaç dakika önce, ilgilenen
            (.cat, .injured, 120, -80, 12, nil),
            (.dog, .food, -200, 150, 95, nil),
            (.cat, .babies, 260, 240, 300, "komsu"),
            (.dog, .emergency, -90, -260, 4, nil),
            (.bird, .vet, 380, -30, 40, nil),
            (.cat, .shelter, -330, -120, 900, nil),
            (.other, .other, 60, 380, 600, nil),
        ]
        for (index, sample) in samples.enumerated() {
            let (species, need, north, east, minutesAgo, helper) = sample
            let coordinate = Coordinate(
                latitude: center.latitude + north / 111_320,
                longitude: center.longitude + east / (111_320 * cos(center.latitude * .pi / 180))
            )
            let createdAt = now.addingTimeInterval(-minutesAgo * 60)
            var report = ReportLifecycle.makeReport(
                id: "demo-\(seedCount)-\(index)",
                species: species,
                need: need,
                at: coordinate,
                reporterID: "someone-else",
                now: createdAt
            )
            if let helper, let claimed = try? ReportLifecycle.apply(.claim, to: report, by: helper, at: now.addingTimeInterval(-20 * 60)) {
                report = claimed
            }
            reports[report.id] = report
        }
    }
}
