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
        /// Bildirimdeki "Geri al" düğmesi ne yapar.
        enum Undo: Equatable {
            /// Az önce konan işareti siler.
            case retract(reportID: String)
            /// Az önceki "Çözüldü" / "Artık yok" önerisini geri alır (`ReportAction.undoClosing`).
            case undoClosing(reportID: String)
        }

        let id = UUID()
        let message: String
        var undo: Undo? = nil
        /// Ekranda kalma süresi (saniye).
        var duration: TimeInterval = 5

        /// "Geri al" düğmesi gösterilsin mi; hangi işaret için.
        var undoReportID: String? {
            guard let undo else { return nil }
            switch undo {
            case .retract(let reportID), .undoClosing(let reportID):
                return reportID
            }
        }
    }

    /// A7: takip edilen bir işaret için başkası "… dendi" dedi; bu kişiye soru.
    struct FollowUp: Identifiable, Equatable {
        struct Option: Identifiable, Equatable {
            let answer: FollowUpAnswer
            let title: String
            var id: FollowUpAnswer { answer }
        }

        let report: Report
        let message: String
        /// Gösterim sırası; "Bilmiyorum" hep sondadır ve varsayılandır (`FollowUpAnswer.dontKnow`).
        let options: [Option]

        var id: String { report.id }
    }

    enum FollowUpAnswer: String, Hashable {
        /// "Evet, çözüldü" / "Evet, artık yok" (`ReportAction.confirmClosing`)
        case confirm
        /// "Hayır, hâlâ yardım gerekiyor" (`ReportAction.dispute`)
        case dispute
        /// "Bilmiyorum": yalnızca yanıtlandı sayılır.
        case dontKnow
    }

    /// Bu yarıçaptan geniş alan görünüyorsa sorgu yapılmaz (şehir ölçeğinde gereksiz veri).
    static let maxQueryRadius: Double = 25_000
    static let minQueryRadius: Double = 1_500
    static let placementZoom: Float = 17.5
    static let browsingZoom: Float = 16
    /// İhtiyaç seçilirken iğnenin bu kadar yakınındaki aynı türden işaret için "Aynı hayvan mı?" sorulur.
    static let duplicateRadius: Double = 40
    /// Kalan yeni işaret hakkı bu kadar ya da azsa seçim panelinde gösterilir.
    static let lowCreatesThreshold = 3
    /// Günlük sınır bildirimi uzun; okunabilsin.
    static let longToastDuration: TimeInterval = 8

    /// "Hâlâ yardım gerekiyor" onayı: sabahki bir görüşe dayanan yanlış itirazları azaltır.
    static let disputeQuestion = "Hayvan hâlâ yardım bekliyor mu? Bunu yalnızca hayvanı şimdi gördüysen söyle."
    static let disputeConfirmTitle = "Evet, hâlâ yardım gerekiyor"
    static let disputeCancelTitle = "Vazgeç"
    /// 40 m önerisi bir "… dendi" işaretine denk gelince düğmeler (bkz. `duplicatePrompt`).
    static let duplicateDisputeTitle = "Evet, hâlâ yardım gerekiyor"
    static let duplicateDismissTitle = "Hayır, başka bir hayvan"

    private(set) var reports: [Report] = []
    private(set) var now = Date()
    private(set) var mode: Mode = .browsing
    private(set) var selectedReportID: String? = nil
    private(set) var cameraRequest: CameraRequest? = nil
    private(set) var isCameraMoving = false
    private(set) var isZoomedTooFarOut = false
    /// Görünen yarıçap `ClosingDisplay.streetDotMaxRadius` ya da daha küçük: gizlenen "… dendi" işaretleri
    /// gri nokta olarak çizilir (bkz. `streetDotReports`).
    private(set) var showsStreetDots = false
    private(set) var toast: Toast? = nil
    private(set) var busyAction: ReportAction? = nil
    /// Her yeni işarette artar; dokunsal geri bildirimi tetikler.
    private(set) var reportsCreated = 0
    /// İhtiyaç seçilirken iğnenin yakınındaki aynı türden işaret ("Ben de gördüm" önerisi).
    /// Kamera hedefi gözlenmediği için sonuç burada tutulur.
    private(set) var duplicateCandidateID: String? = nil
    /// `config/public.closingMode` (demo: `demote`); okunana kadar `ClosingMode.fallback`.
    private(set) var closingMode: ClosingMode = .fallback
    /// `users/{me}`: hesap yaşı ve günlük haklar; okunana kadar `nil`.
    private(set) var userRecord: UserRecord? = nil
    /// Onay bekleyen itiraz (bkz. `handle(_:on:)`, `disputeQuestion`).
    private(set) var disputeCandidateID: String? = nil
    /// Gösterilecek takip sorusu (A7); arayüz bunu sayfa olarak açar.
    private(set) var followUp: FollowUp? = nil

    let environment: AppEnvironment
    private var repository: ReportRepository { environment.repository }
    var session: UserSession { environment.session }
    var location: LocationProvider { environment.location }
    var watched: WatchedReports { environment.watched }

    @ObservationIgnored private var cameraTarget: Coordinate?
    @ObservationIgnored private var visibleArea: (center: Coordinate, radius: Double)?
    @ObservationIgnored private var subscribedArea: (center: Coordinate, radius: Double)?
    @ObservationIgnored private var subscription: ReportSubscription?
    @ObservationIgnored private var userRecordSubscription: ReportSubscription?
    @ObservationIgnored private var closingModeSubscription: ReportSubscription?
    @ObservationIgnored private var hasCenteredOnUser = false
    /// "Hayır, başka bir hayvan" denen öneriler; yeni işaretleme başlayınca sıfırlanır.
    @ObservationIgnored private var dismissedDuplicateIDs: Set<String> = []
    /// Sırada bekleyen takip soruları (en yeni öneri önce).
    @ObservationIgnored private var followUpQueue: [Report] = []

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: Türetilmiş durum

    var userID: String? { session.userID }
    var isPlacing: Bool { mode != .browsing }

    /// Süresi dolmamış, kapanmamış işaretler (sunucu temizliğini beklemeden). "… dendi" de aktiftir.
    var activeReports: [Report] {
        reports.filter { $0.isActive(at: now) }
    }

    /// Haritada iğne olarak çizilenler. "… dendi" işaretleri bu kişiye ve moda göre gizlenebilir.
    var visibleReports: [Report] {
        activeReports.filter { look(for: $0) != .hidden }
    }

    /// Gizlenen "… dendi" işaretleri: yalnızca sokak yakınlığında gri nokta. Hayvan hâlâ oradaysa
    /// yanındaki kişi dokunup itiraz edebilsin, kapatan da "Geri al" diyebilsin.
    var streetDotReports: [Report] {
        guard showsStreetDots else { return [] }
        return activeReports.filter { look(for: $0) == .hidden }
    }

    /// "… dendi" işaretinin bu kişinin haritasındaki görünüşü; işaret `closing` değilse `nil`.
    func look(for report: Report) -> ClosingLook? {
        ClosingDisplay.look(
            of: report,
            mode: closingMode,
            viewer: userID,
            answered: watched.isAnswered(report),
            at: now
        )
    }

    /// Aktif "… dendi" işaretlerinin görünüşleri (işaret kimliğine göre); harita çizimi için.
    var closingLooks: [String: ClosingLook] {
        activeReports.reduce(into: [:]) { looks, report in
            if let closingLook = look(for: report) {
                looks[report.id] = closingLook
            }
        }
    }

    /// Açık kart. Gizlenmiş (gri nokta) işaret de seçilebilir; yakınlaşma değişince kart kapanmaz.
    var selectedReport: Report? {
        guard let selectedReportID else { return nil }
        return activeReports.first { $0.id == selectedReportID }
    }

    /// Bu arada kapanan, süresi dolan ya da artık üzerinde bir şey yapılamayan işaret önerilmez.
    var duplicateCandidate: Report? {
        guard let duplicateCandidateID else { return nil }
        return activeReports.first { $0.id == duplicateCandidateID && duplicateAction(for: $0) != nil }
    }

    /// Öneriye dokununca yapılacak eylem: bekleyen işarette "Hâlâ orada", "… dendi" işaretinde itiraz
    /// ("Hâlâ yardım gerekiyor"). Yapılamıyorsa (ör. öneriyi bu kişi yaptı) `nil`; öneri gösterilmez.
    func duplicateAction(for report: Report) -> ReportAction? {
        if report.isWaiting(at: now) { return .confirmStillThere }
        if report.status == .closing, report.isActive(at: now),
           let userID, ReportLifecycle.canDispute(report, by: userID) {
            return .dispute
        }
        return nil
    }

    /// Öneri bir "… dendi" işaretiyse panelde sorulacak soru ("Burada 2 sa önce bir kedi için 'Çözüldü'
    /// dendi. …"); düğmeler `duplicateDisputeTitle` / `duplicateDismissTitle`. Bekleyen işarette `nil`.
    var duplicatePrompt: String? {
        guard let report = duplicateCandidate, report.status == .closing else { return nil }
        return Messages.duplicateClosingPrompt(report, now: now)
    }

    /// "N hayvan yardım bekliyor": bekleyen, başkasının 45 dk'yı geçen sahipliği ve doğrulanmamış ("?") öneri.
    var waitingCount: Int {
        activeReports.filter {
            ClosingDisplay.countsAsWaiting($0, viewer: userID, mode: closingMode, at: now)
        }.count
    }

    /// Son 24 saatte kalan yeni işaret hakkı; kayıt henüz okunmadıysa `nil`.
    var remainingCreates: Int? {
        userRecord.map { Budget.remainingCreates($0, at: now) }
    }

    /// Seçim panelinde: "Bugün 3 işaret hakkın kaldı" (≤ `lowCreatesThreshold`) ya da hak bittiyse
    /// "Yeni işaret hakkın saat 14.20'de açılır"; yoksa `nil`.
    var createAllowanceText: String? {
        guard let userRecord else { return nil }
        return Messages.createAllowance(userRecord, lowThreshold: Self.lowCreatesThreshold, now: now)
    }

    /// Onay bekleyen itirazın işareti.
    var disputeCandidate: Report? {
        guard let disputeCandidateID else { return nil }
        return activeReports.first { $0.id == disputeCandidateID }
    }

    func distance(to report: Report) -> Double? {
        location.coordinate?.distance(to: report.coordinate)
    }

    // MARK: Yaşam döngüsü

    /// Ekran açıkken çalışır: oturum açar, hesap kaydını hazırlar, "x dk önce" metinlerini ve süresi
    /// dolanları günceller.
    func run() async {
        location.start()
        await session.ensureSignedIn()
        guard let userID = session.userID else { return }
        observeAccount(userID)
        refreshSubscription()
        // Hesap kaydı (yaş, günlük haklar) ağ gelene kadar arka planda denenir; harita onu beklemez.
        let account = Task { [weak self] in
            await self?.ensureUserRecord(userID)
        }
        defer { account.cancel() }
        Task { [weak self] in
            await self?.refreshWatched()
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            now = Date()
        }
    }

    /// Uygulama öne geldi: saat metinleri hemen güncellenir, takip edilen işaretler (en fazla 10 dk'da bir) okunur.
    func appBecameActive() {
        now = Date()
        Task { [weak self] in
            await self?.refreshWatched()
        }
    }

    private func observeAccount(_ userID: String) {
        userRecordSubscription = repository.observeUserRecord(userID: userID) { [weak self] record in
            self?.userRecord = record
        }
        closingModeSubscription = repository.observeClosingMode { [weak self] mode in
            self?.closingMode = mode
        }
    }

    /// `users/{me}` yoksa oluşturur (anonim girişten hemen sonra); ağ yoksa artan aralıklarla yeniden dener.
    private func ensureUserRecord(_ userID: String) async {
        var delay: Double = 2
        while !Task.isCancelled {
            do {
                try await repository.ensureUserRecord(userID: userID)
                return
            } catch {
                try? await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, 60)
            }
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
        let dots = visibleRadius <= ClosingDisplay.streetDotMaxRadius
        if dots != showsStreetDots {
            showsStreetDots = dots
        }
        refreshSubscription()
        // İğne kaydırıldı: yakındaki aynı hayvan yeniden aranır.
        updateDuplicateCandidate()
    }

    /// İğne ya da gri nokta.
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
        dismissedDuplicateIDs = []
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
        showNextFollowUp()
    }

    /// "Ben de gördüm": yeni işaret yerine iğnenin yakınındaki aynı hayvana "Hâlâ orada" denir ve kartı
    /// açılır; böylece aynı kedi için ikinci işaret çıkmaz, sayısı artar. Öneri bir "… dendi" işaretiyse
    /// ("Evet, hâlâ yardım gerekiyor") itiraz edilir: kişi hayvanın başında, ayrıca onay sorulmaz.
    func confirmDuplicate(_ report: Report) {
        let action = duplicateAction(for: report)
        mode = .browsing
        updateDuplicateCandidate()
        selectedReportID = report.id
        showNextFollowUp()
        guard let action else { return }
        Task { [weak self] in
            await self?.perform(action, on: report)
        }
    }

    /// "Hayır, başka bir hayvan": bu işaretleme boyunca o öneri bir daha gösterilmez.
    func dismissDuplicate() {
        if let duplicateCandidateID {
            dismissedDuplicateIDs.insert(duplicateCandidateID)
        }
        updateDuplicateCandidate()
    }

    /// İhtiyaç seçilirken: iğneye (kamera hedefine) `duplicateRadius` içindeki en yakın, aynı türden ve
    /// üzerinde bir şey yapılabilen aktif işaret (gizlenmiş "… dendi" de). Başka her durumda öneri yoktur.
    private func updateDuplicateCandidate() {
        var candidateID: String?
        if case .choosingNeed(let species) = mode, let target = cameraTarget {
            let radius = Self.duplicateRadius
            let nearest = activeReports
                .filter { $0.species == species && !dismissedDuplicateIDs.contains($0.id) && duplicateAction(for: $0) != nil }
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

    /// Son dokunuş: işaret iğnenin olduğu yere (kamera hedefine) hemen kaydedilir. Günlük hak bittiyse
    /// kaydedilmez; iğne yerinde kalır ki yakındaki aynı hayvana "Ben de gördüm" denebilsin.
    func choose(_ need: Need) {
        guard case .choosingNeed(let species) = mode, let target = cameraTarget else { return }
        guard let userID = session.userID else {
            show(Toast(message: "Bağlantı kuruluyor, birkaç saniye sonra tekrar dene."))
            return
        }

        let now = Date()
        let report = ReportLifecycle.makeReport(
            id: repository.newReportID(),
            species: species,
            need: need,
            at: target,
            reporterID: userID,
            now: now
        )
        do {
            try repository.create(report) { [weak self] error in
                self?.createFailed(report, error: error)
            }
        } catch CreateQuotaError.exhausted(let limit, let nextCreateAt) {
            show(Toast(
                message: Messages.createLimit(limit: limit, nextCreateAt: nextCreateAt, now: now),
                duration: Self.longToastDuration
            ))
            return
        } catch {
            show(Toast(message: "İşaret kaydedilemedi. Lütfen tekrar dene."))
            return
        }
        watched.watch(report)
        mode = .browsing
        updateDuplicateCandidate()
        reportsCreated += 1
        show(Toast(message: "\(species.title) · \(need.title) işaretlendi", undo: .retract(reportID: report.id)))
        showNextFollowUp()
    }

    private func createFailed(_ report: Report, error: Error) {
        watched.forget(report.id)
        let message = error is CreateQuotaError ? Messages.createRejected : "İşaret kaydedilemedi. Lütfen tekrar dene."
        show(Toast(message: message))
    }

    /// Bildirimdeki "Geri al".
    func undo(_ toast: Toast) {
        guard let undo = toast.undo else { return }
        self.toast = nil
        switch undo {
        case .retract(let reportID):
            watched.forget(reportID)
            repository.retract(reportID: reportID) { [weak self] _ in
                self?.show(Toast(message: "Geri alınamadı: başka biri de bu işaretle ilgilendi."))
            }
        case .undoClosing(let reportID):
            guard let report = reports.first(where: { $0.id == reportID }) else {
                show(Toast(message: "Geri alınamadı: işaret artık haritada değil."))
                return
            }
            Task { [weak self] in
                await self?.perform(.undoClosing, on: report)
            }
        }
    }

    // MARK: İşaret eylemleri

    /// Karttaki düğme. "Hâlâ yardım gerekiyor" önce onay ister (`disputeCandidate`); diğerleri hemen yapılır.
    func handle(_ action: ReportAction, on report: Report) {
        if action == .dispute {
            disputeCandidateID = report.id
            return
        }
        Task { [weak self] in
            await self?.perform(action, on: report)
        }
    }

    /// İtiraz onaylandı ("Evet, hâlâ yardım gerekiyor"). İşaret, onay sorulduğu andaki hâliyle verilir.
    func confirmDispute(_ report: Report) {
        disputeCandidateID = nil
        Task { [weak self] in
            await self?.perform(.dispute, on: report)
        }
    }

    func cancelDispute() {
        disputeCandidateID = nil
    }

    func perform(_ action: ReportAction, on report: Report) async {
        guard let userID = session.userID, busyAction == nil else { return }
        busyAction = action
        defer { busyAction = nil }
        // "Hâlâ orada" diyen kişi sayıya eklenecek mi? Eylemden önceki hâle bakılır.
        let addsSeen = action == .confirmStillThere && ReportLifecycle.confirmAddsSeen(to: report, by: userID)
        do {
            let outcome = try await repository.perform(action, onReportID: report.id, by: userID)
            remember(action, outcome.report)
            if let credibility = outcome.credibility {
                // Öneriyi yapanın haritasından işaret hemen kalkar, kartı da kapanır; "Geri al" bildirimde.
                if selectedReportID == report.id {
                    selectedReportID = nil
                }
                show(Toast(
                    message: Messages.closerToast(
                        for: outcome.report,
                        by: userID,
                        credibility: credibility,
                        mode: closingMode,
                        now: Date()
                    ),
                    undo: .undoClosing(reportID: report.id),
                    duration: ClosingDisplay.closerUndoToastDuration
                ))
            } else {
                show(Toast(message: Messages.actionDone(action, outcome: outcome, addsSeen: addsSeen)))
            }
        } catch let error as ReportError {
            show(Toast(message: error.errorDescription ?? "İşlem tamamlanamadı."))
        } catch {
            show(Toast(message: "İşlem tamamlanamadı. Bağlantını kontrol et."))
        }
    }

    /// A7: kişinin ilgilendiği işaretler takip edilir (koyduğu işaret `choose(_:)`'da eklenir).
    private func remember(_ action: ReportAction, _ report: Report) {
        switch action {
        case .claim, .confirmStillThere, .dispute:
            watched.watch(report)
        case .release, .resolve, .reportGone, .confirmClosing, .undoClosing, .expire:
            break
        }
    }

    func directionsURL(for report: Report) -> URL? {
        let destination = "\(report.coordinate.latitude),\(report.coordinate.longitude)"
        // Apple Haritalar'da yürüyerek yol tarifi.
        return URL(string: "https://maps.apple.com/?daddr=\(destination)&dirflg=w")
    }

    // MARK: Takip sorusu (A7)

    /// Takip edilen işaretleri okur (en fazla `WatchedReports.refreshInterval`'da bir); başkasının
    /// "… dendi" dediği ve bu kişinin yanıtlayabileceği işaretler için soru sıraya girer.
    private func refreshWatched() async {
        let started = Date()
        guard let userID, watched.needsRefresh(at: started) else { return }
        watched.beginRefresh(at: started)
        let fetched = await repository.fetchReports(ids: watched.ids)
        let now = Date()
        watched.update(with: fetched, at: now)
        followUpQueue = fetched
            .filter { needsFollowUp($0, userID: userID, at: now) }
            .sorted { ($0.closing?.at ?? .distantPast) > ($1.closing?.at ?? .distantPast) }
        showNextFollowUp()
    }

    private func needsFollowUp(_ report: Report, userID: String, at now: Date) -> Bool {
        guard report.status == .closing, report.isActive(at: now), let closing = report.closing,
              closing.userID != userID, !watched.isAnswered(report)
        else { return false }
        return ReportLifecycle.canConfirmClosing(report, by: userID) || ReportLifecycle.canDispute(report, by: userID)
    }

    /// Sıradaki soruyu gösterir; işaretleme sürerken ya da başka soru açıkken bekler.
    private func showNextFollowUp() {
        guard followUp == nil, mode == .browsing, let userID else { return }
        let now = Date()
        while !followUpQueue.isEmpty {
            let queued = followUpQueue.removeFirst()
            // Sıradayken değişmiş olabilir: haritadaki güncel hâline bakılır.
            let report = reports.first { $0.id == queued.id } ?? queued
            if needsFollowUp(report, userID: userID, at: now) {
                followUp = makeFollowUp(for: report, userID: userID, at: now)
                return
            }
        }
    }

    private func makeFollowUp(for report: Report, userID: String, at now: Date) -> FollowUp {
        var options: [FollowUp.Option] = []
        if ReportLifecycle.canConfirmClosing(report, by: userID) {
            let reason = report.closing?.reason ?? .resolved
            options.append(FollowUp.Option(answer: .confirm, title: Messages.confirmClosingTitle(reason)))
        }
        if ReportLifecycle.canDispute(report, by: userID) {
            let title = report.reporterID == userID ? "Hayır, hâlâ yardım gerekiyor" : "Hâlâ yardım gerekiyor"
            options.append(FollowUp.Option(answer: .dispute, title: title))
        }
        options.append(FollowUp.Option(answer: .dontKnow, title: "Bilmiyorum"))

        // Paydaş yanıtlayana kadar işareti görür; başkalarının haritasından kalkış anı soruda söylenir.
        var leavesAt: Date?
        if case .fading(let date)? = look(for: report) {
            leavesAt = date
        }
        return FollowUp(
            report: report,
            message: Messages.followUp(report, viewer: userID, leavesAt: leavesAt, now: now),
            options: options
        )
    }

    /// Takip sorusunun yanıtı. Her yanıt (Bilmiyorum dahil) bu öneri için "yanıtlandı" sayılır.
    func answerFollowUp(_ answer: FollowUpAnswer) {
        guard let followUp else { return }
        self.followUp = nil
        watched.markAnswered(followUp.report)
        let action: ReportAction
        switch answer {
        case .confirm:
            action = .confirmClosing
        case .dispute:
            action = .dispute
        case .dontKnow:
            showNextFollowUp()
            return
        }
        Task { [weak self] in
            await self?.perform(action, on: followUp.report)
            self?.showNextFollowUp()
        }
    }

    /// Sayfa kaydırılıp kapatıldı: "Bilmiyorum" gibi.
    func dismissFollowUp() {
        answerFollowUp(.dontKnow)
    }

    // MARK: Bildirim

    private func show(_ toast: Toast) {
        self.toast = toast
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(toast.duration))
            if self?.toast?.id == toast.id {
                self?.toast = nil
            }
        }
    }
}
