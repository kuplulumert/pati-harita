import AnimalKit
import Foundation
import Observation

/// Ana ekranın durumu. Akış:
/// "Hayvan gördüm" → tür → ihtiyaç → işaret haritada → biri "İlgileniyorum" der → "Çözüldü".
@MainActor
@Observable
final class MapViewModel {
    enum Mode: Equatable {
        case browsing
        case choosingSpecies
        case choosingNeed(Species)
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        var undoReportID: String?
    }

    /// Bu yarıçaptan geniş alan görünüyorsa sorgu yapılmaz (şehir ölçeğinde gereksiz veri).
    static let maxQueryRadius: Double = 25_000
    static let minQueryRadius: Double = 1_500
    static let placementZoom: Float = 17.5
    static let browsingZoom: Float = 16
    /// İhtiyaç seçilirken iğnenin bu kadar yakınındaki aynı türden işaret için "Aynı hayvan mı?" sorulur.
    static let duplicateRadius: Double = 40

    private(set) var reports: [Report] = []
    private(set) var now = Date()
    private(set) var mode: Mode = .browsing
    private(set) var selectedReportID: String? = nil
    private(set) var cameraRequest: CameraRequest? = nil
    private(set) var isCameraMoving = false
    private(set) var isZoomedTooFarOut = false
    private(set) var toast: Toast? = nil
    private(set) var busyAction: ReportAction? = nil
    /// Her yeni işarette artar; dokunsal geri bildirimi tetikler.
    private(set) var reportsCreated = 0
    /// İhtiyaç seçilirken iğnenin yakınındaki aynı türden işaret ("Ben de gördüm" önerisi).
    /// Kamera hedefi gözlenmediği için sonuç burada tutulur.
    private(set) var duplicateCandidateID: String? = nil

    let environment: AppEnvironment
    private var repository: ReportRepository { environment.repository }
    var session: UserSession { environment.session }
    var location: LocationProvider { environment.location }

    @ObservationIgnored private var cameraTarget: Coordinate?
    @ObservationIgnored private var visibleArea: (center: Coordinate, radius: Double)?
    @ObservationIgnored private var subscribedArea: (center: Coordinate, radius: Double)?
    @ObservationIgnored private var subscription: ReportSubscription?
    @ObservationIgnored private var hasCenteredOnUser = false

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: Türetilmiş durum

    var userID: String? { session.userID }
    var isPlacing: Bool { mode != .browsing }

    /// Süresi dolanlar sunucu temizliğini beklemeden gizlenir.
    var visibleReports: [Report] {
        reports.filter { $0.isActive(at: now) }
    }

    var selectedReport: Report? {
        guard let selectedReportID else { return nil }
        return visibleReports.first { $0.id == selectedReportID }
    }

    /// Bu arada kapanan ya da süresi dolan işaret önerilmez.
    var duplicateCandidate: Report? {
        guard let duplicateCandidateID else { return nil }
        return visibleReports.first { $0.id == duplicateCandidateID }
    }

    var waitingCount: Int {
        visibleReports.filter { $0.phase(for: userID, at: now) == .waiting }.count
    }

    func distance(to report: Report) -> Double? {
        location.coordinate?.distance(to: report.coordinate)
    }

    // MARK: Yaşam döngüsü

    /// Ekran açıkken çalışır: oturum açar, "x dk önce" metinlerini ve süresi dolanları günceller.
    func run() async {
        location.start()
        await session.ensureSignedIn()
        refreshSubscription()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            now = Date()
        }
    }

    func userLocationChanged() {
        guard !hasCenteredOnUser, let coordinate = location.coordinate else { return }
        hasCenteredOnUser = true
        cameraRequest = CameraRequest(target: coordinate, zoom: Self.browsingZoom)
        // İlk abonelik varsayılan şehir merkezine göreydi; kullanıcının çevresi için yenilensin.
        subscribedArea = nil
    }

    func recenterOnUser() {
        guard let coordinate = location.coordinate else {
            show(Toast(message: location.isDenied
                ? "Konum izni kapalı. Ayarlar'dan açabilirsin."
                : "Konumun bulunuyor…"))
            location.start()
            return
        }
        cameraRequest = CameraRequest(target: coordinate, zoom: max(Self.browsingZoom, 15))
    }

    // MARK: Harita olayları

    func cameraWillMove() {
        isCameraMoving = true
    }

    func cameraMoved(to center: Coordinate) {
        cameraTarget = center
    }

    func cameraBecameIdle(center: Coordinate, visibleRadius: Double) {
        isCameraMoving = false
        cameraTarget = center
        visibleArea = (center, visibleRadius)
        refreshSubscription()
        // İğne kaydırıldı: yakındaki aynı hayvan yeniden aranır.
        updateDuplicateCandidate()
    }

    func markerTapped(_ reportID: String) {
        guard mode == .browsing else { return }
        selectedReportID = reportID
    }

    func mapTapped() {
        selectedReportID = nil
    }

    func mapLongPressed(at coordinate: Coordinate) {
        startPlacing(at: coordinate)
    }

    func closeCard() {
        selectedReportID = nil
    }

    /// Görünen alan, dinlenen alanın dışına taştıysa aboneliği yeniler.
    /// Küçük kaydırmalarda yeniden sorgu yapılmaz (alan 1,5 kat geniş dinlenir).
    private func refreshSubscription() {
        guard let area = visibleArea, session.userID != nil else { return }
        isZoomedTooFarOut = area.radius > Self.maxQueryRadius
        guard !isZoomedTooFarOut else {
            // Artık güncellenmeyecek işaretleri göstermek yerine haritayı temizle.
            subscription?.cancel()
            subscription = nil
            subscribedArea = nil
            reports = []
            // İşaretler kalkınca kart da kapanır; yeniden yakınlaşınca kendiliğinden açılmasın.
            selectedReportID = nil
            return
        }
        if let subscribed = subscribedArea,
           subscribed.center.distance(to: area.center) + area.radius <= subscribed.radius {
            return
        }
        let radius = max(area.radius * 1.5, Self.minQueryRadius)
        subscription?.cancel()
        subscription = repository.observeActiveReports(center: area.center, radiusMeters: radius) { [weak self] reports in
            self?.reports = reports
            self?.now = Date()
        }
        subscribedArea = (area.center, radius)
    }

    // MARK: Yeni işaret

    func startPlacing(at coordinate: Coordinate? = nil) {
        selectedReportID = nil
        toast = nil
        mode = .choosingSpecies
        updateDuplicateCandidate()
        if let target = coordinate ?? location.coordinate {
            cameraRequest = CameraRequest(target: target, zoom: Self.placementZoom)
        }
    }

    func choose(_ species: Species) {
        mode = .choosingNeed(species)
        updateDuplicateCandidate()
    }

    func backToSpecies() {
        mode = .choosingSpecies
        updateDuplicateCandidate()
    }

    func cancelPlacing() {
        mode = .browsing
        updateDuplicateCandidate()
    }

    /// "Ben de gördüm": yeni işaret yerine iğnenin yakınındaki aynı hayvana "Hâlâ orada" denir
    /// ve kartı açılır. Böylece aynı kedi için haritada ikinci bir işaret çıkmaz, sayısı artar.
    func confirmDuplicate(_ report: Report) {
        mode = .browsing
        updateDuplicateCandidate()
        selectedReportID = report.id
        Task { [weak self] in
            await self?.perform(.confirmStillThere, on: report)
        }
    }

    /// İhtiyaç seçilirken: iğneye (kamera hedefine) `duplicateRadius` içindeki en yakın, aynı türden
    /// aktif işaret. Başka her durumda öneri yoktur.
    private func updateDuplicateCandidate() {
        var candidateID: String?
        if case .choosingNeed(let species) = mode, let target = cameraTarget {
            let radius = Self.duplicateRadius
            let nearest = visibleReports
                .filter { $0.species == species }
                .map { (id: $0.id, distance: $0.coordinate.distance(to: target)) }
                .filter { $0.distance <= radius }
                .min { $0.distance < $1.distance }
            candidateID = nearest?.id
        }
        // Aynı değeri yeniden yazmak paneli boşuna yeniden çizdirirdi.
        if candidateID != duplicateCandidateID {
            duplicateCandidateID = candidateID
        }
    }

    /// Son dokunuş: işaret iğnenin olduğu yere (kamera hedefine) hemen kaydedilir.
    func choose(_ need: Need) {
        guard case .choosingNeed(let species) = mode, let target = cameraTarget else { return }
        guard let userID = session.userID else {
            show(Toast(message: "Bağlantı kuruluyor, birkaç saniye sonra tekrar dene."))
            return
        }

        let report = ReportLifecycle.makeReport(
            id: repository.newReportID(),
            species: species,
            need: need,
            at: target,
            reporterID: userID,
            now: Date()
        )
        repository.create(report) { [weak self] _ in
            self?.show(Toast(message: "İşaret kaydedilemedi. Lütfen tekrar dene."))
        }
        mode = .browsing
        updateDuplicateCandidate()
        reportsCreated += 1
        show(Toast(message: "\(species.title) · \(need.title) işaretlendi", undoReportID: report.id))
    }

    func undo(_ toast: Toast) {
        guard let reportID = toast.undoReportID else { return }
        self.toast = nil
        repository.retract(reportID: reportID) { [weak self] _ in
            self?.show(Toast(message: "Geri alınamadı: biri bu işaretle ilgilenmeye başladı."))
        }
    }

    // MARK: İşaret eylemleri

    func perform(_ action: ReportAction, on report: Report) async {
        guard let userID = session.userID, busyAction == nil else { return }
        busyAction = action
        defer { busyAction = nil }
        // "Hâlâ orada" diyen kişi sayıya eklenecek mi? Eylemden önceki hâle bakılır.
        let addsSeen = action == .confirmStillThere && ReportLifecycle.confirmAddsSeen(to: report, by: userID)
        do {
            try await repository.perform(action, onReportID: report.id, by: userID)
            let message = addsSeen
                ? "Teşekkürler! Bu hayvanı artık \(report.seenCount + 1) kişi bildirdi."
                : Self.confirmation(for: action)
            show(Toast(message: message))
        } catch let error as ReportError {
            show(Toast(message: error.errorDescription ?? "İşlem tamamlanamadı."))
        } catch {
            show(Toast(message: "İşlem tamamlanamadı. Bağlantını kontrol et."))
        }
    }

    func directionsURL(for report: Report) -> URL? {
        let destination = "\(report.coordinate.latitude),\(report.coordinate.longitude)"
        // Apple Haritalar'da yürüyerek yol tarifi.
        return URL(string: "https://maps.apple.com/?daddr=\(destination)&dirflg=w")
    }

    private static func confirmation(for action: ReportAction) -> String {
        switch action {
        case .claim: "Teşekkürler! İşaret 3 saat boyunca sende."
        case .release: "İşaret yeniden yardım bekliyor."
        case .resolve: "Harika! İşaret haritadan kaldırıldı."
        case .confirmStillThere: "Teşekkürler, işaret güncellendi."
        case .reportGone: "Bildirdiğin için teşekkürler."
        }
    }

    // MARK: Bildirim

    private func show(_ toast: Toast) {
        self.toast = toast
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if self?.toast?.id == toast.id {
                self?.toast = nil
            }
        }
    }
}
