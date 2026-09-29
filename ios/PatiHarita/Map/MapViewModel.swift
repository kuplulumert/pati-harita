import AnimalKit
import Foundation
import Observation
import UIKit

/// Ana ekranın durumu. Akış:
/// "Yardım gereken hayvan" → tür → ihtiyaç (hafif ihtiyaçta bazen "Yardıma ihtiyacı var mı?") → işaret haritada
/// → biri "İlgileniyorum" der → "Çözüldü". İşareti koyan, kimse dokunmadan kısa süre içinde düzeltebilir ya da silebilir.
@MainActor
@Observable
final class MapViewModel {
    enum Mode: Equatable {
        case browsing
        case choosingSpecies
        case choosingNeed(Species)
        /// "İşareti düzelt": önce tür (`species` `nil`), sonra ihtiyaç; ihtiyaca dokununca kaydedilir.
        /// İğne yeni işaretlemedeki gibi haritanın ortasındadır.
        case editing(reportID: String, species: Species?)
    }

    struct Toast: Identifiable, Equatable {
        /// Bildirimdeki "Geri al" düğmesi ne yapar.
        enum Undo: Equatable {
            /// Az önce konan işareti siler.
            case retract(reportID: String)
            /// Az önceki "Çözüldü" / "Artık yok" / "Yardım gerekmiyor" önerisini geri alır (`ReportAction.undoClosing`).
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

    /// İhtiyaç seçildi ama işaret henüz kaydedilmedi: seçim panelinde ızgaranın yerinde "Yardıma ihtiyacı var mı?"
    /// sorusu var. İşaretlemeyi engellemez; yakınlık kapısı ihtiyaca dokunulduğunda zaten geçildi.
    struct PendingReport: Equatable {
        enum Step: Equatable {
            /// "Yardıma ihtiyacı var mı?" (`GentleCheck`). `recentCount`: metin "Son 24 saatte N işaret koydun."
            /// ile başlar; cihazın ilk hafif işaretlerinden biriyse `nil`.
            case gentleCheck(recentCount: Int?)
        }

        let species: Species
        let need: Need
        /// İhtiyaca dokunulduğu andaki iğne: işaret buraya konur.
        let coordinate: Coordinate
        var step: Step

        var title: String { Messages.gentleCheckTitle }

        var message: String {
            switch step {
            case .gentleCheck(let recentCount): Messages.gentleCheck(need: need, recentCount: recentCount)
            }
        }

        /// `confirmPendingReport()`: işaret kaydedilir.
        var confirmTitle: String { Messages.gentleCheckConfirmTitle }
        /// `cancelPendingReport()`: işaretlemeden vazgeçilir.
        var cancelTitle: String { Messages.gentleCheckCancelTitle }
        /// Arayüz testi düğmeleri bunlarla bulur.
        var confirmIdentifier: String { "check-confirm" }
        var cancelIdentifier: String { "check-cancel" }
    }

    /// Yanından geçilen işaret için "Yakınındaki kedi hâlâ orada mı?" (`NearbyPrompt`); üstte kısa bir şerit.
    struct NearbyQuestion: Equatable {
        /// Soru gösterildiği andaki işaret.
        let report: Report
        var step: NearbyPrompt.Step
        /// Adımın gösterildiği an; 20 sn ve düğmelerin 0,8 sn beklemesi her adımda yeniden başlar.
        var shownAt: Date
        /// Düğmeler açık mı (yanlışlıkla basılmasın diye kısa bir bekleme).
        var isArmed: Bool
    }

    /// Yardıma giderken güvenlik hatırlatması; "Devam et" deyince bekleyen iş yapılır.
    struct NightReminder: Identifiable, Equatable {
        enum Kind: Equatable {
            /// Gece acil, yaralı ya da yavru işaretine gidilirken (`nightReminderTitle`).
            case night
            /// Bu cihazda ilk "İlgileniyorum" ya da "Yol tarifi" (`Messages.goSafetyTitle`).
            case firstGo
        }

        enum Pending: Equatable {
            /// "İlgileniyorum"
            case claim
            /// "Yol tarifi": bu bağlantı açılır.
            case directions(URL)
        }

        let kind: Kind
        let report: Report
        let pending: Pending

        var id: String { report.id }
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
        /// "Evet, çözüldü" / "Evet, artık yok" / "Evet, ihtiyacı yoktu" (`ReportAction.confirmClosing`)
        case confirm
        /// "Hayır/Evet, hâlâ yardım gerekiyor" (`ReportAction.dispute`)
        case dispute
        /// "Bilmiyorum": yalnızca yanıtlandı sayılır.
        case dontKnow
    }

    /// Bu yarıçaptan geniş alan görünüyorsa sorgu yapılmaz (şehir ölçeğinde gereksiz veri).
    static let maxQueryRadius: Double = 25_000
    static let minQueryRadius: Double = 1_500
    /// 41°'de ~0,9 m/nokta: 150 m'lik çevre ekranda ~166 nokta yarıçapla görünür.
    static let placementZoom: Float = 17
    static let browsingZoom: Float = 16
    /// İhtiyaç seçilirken iğnenin bu kadar yakınındaki aynı türden işaret için "Aynı hayvan mı?" sorulur.
    static let duplicateRadius: Double = 40
    /// Kalan yeni işaret hakkı bu kadar ya da azsa seçim panelinde gösterilir.
    static let lowCreatesThreshold = 3
    /// Günlük sınır bildirimi uzun; okunabilsin.
    static let longToastDuration: TimeInterval = 8
    /// Düzeltmede iğne bundan az kaydıysa konum değişmiş sayılmaz (harita merkezinin yuvarlama farkı); o zaman
    /// konum ve alan hiç denetlenmez.
    static let editMoveThreshold: Double = PlacementGate.unmovedTolerance
    /// Bundan az değişen çevre halkası yeniden çizilmez (metre).
    static let placementAreaTolerance: Double = 2
    /// İğne konumundan bu kadar uzaksa "İğneyi konumuma getir" gösterilir (metre).
    static let recenterPinDistance: Double = 10
    /// İşaretlerken karar bu aralıkla yeniden hesaplanır (okumanın eskimesi, "hâlâ bulunamadı").
    static let placementTickInterval: TimeInterval = 2
    /// Engel duyurusu VoiceOver'da en fazla bu aralıkla okunur.
    static let blockedAnnouncementInterval: TimeInterval = 3
    /// "Hâlâ orada mı?" okuma başına değil, en fazla bu aralıkla değerlendirilir.
    static let nearbyFixEvaluationInterval: TimeInterval = 3
    /// Sıklık engeli bundan kısa sürede kalkacaksa o an için bir kez yeniden bakılır.
    static let nearbyRecheckHorizon: TimeInterval = 15 * 60
    /// Bir yazım reddedilince `banned/{me}`'e en fazla bu aralıkla bakılır.
    static let bannedCheckInterval: TimeInterval = 10 * 60

    /// "Hâlâ yardım gerekiyor" onayı: sabahki bir görüşe dayanan yanlış itirazları azaltır.
    static let disputeQuestion = "Hayvan hâlâ yardım bekliyor mu? Bunu yalnızca hayvanı şimdi gördüysen söyle."
    static let disputeConfirmTitle = "Evet, hâlâ yardım gerekiyor"
    static let disputeCancelTitle = "Vazgeç"
    /// 40 m önerisi bir "… dendi" işaretine denk gelince düğmeler (bkz. `duplicatePrompt`).
    static let duplicateDisputeTitle = "Evet, hâlâ yardım gerekiyor"
    static let duplicateDismissTitle = "Hayır, başka bir hayvan"

    /// Karttaki "Düzenle" (`canEdit`, `startEditing`) ve düzeltme paneli.
    static let editButtonTitle = "Düzenle"
    static let editPanelTitle = "İşareti düzelt"
    static let editPanelSubtitle = "Türü ve ihtiyacı düzeltebilirsin. İğneyi yalnızca yanındaysan kaydırabilirsin."
    static let placementPanelSubtitle = "İğneyi ayarlamak için haritayı kaydır (en fazla 150 m)"
    /// Düzeltme panelindeki "İşareti sil".
    static let retractButtonTitle = "İşareti sil"
    static let retractQuestion = "Bu işareti silmek istiyor musun?"
    static let retractConfirmTitle = "Sil"
    static let retractCancelTitle = "Vazgeç"
    /// Kartın "⋯ Diğer" menüsünün son bölümü.
    static let flagMenuTitle = "Bu işareti bildir"
    static let hideMenuTitle = "Bu işareti gizle"
    static let flagMailMenuTitle = "E-postayla ayrıntı gönder"
    static let flagQuestion = "Bu işarette ne sorun var?"
    static let flagMessage = "Tehlikedeysen 112'yi ara."
    static let flagCancelTitle = "Vazgeç"

    /// Gece (yerel saatle 21.00–06.00) bu ihtiyaçlara "İlgileniyorum" ya da "Yol tarifi" denince, kurulum
    /// başına en fazla `nightReminderInterval`'da bir.
    static let nightReminderNeeds: Set<Need> = [.emergency, .injured, .babies]
    static let nightStartHour = 21
    static let nightEndHour = 6
    static let nightReminderInterval: TimeInterval = 7 * 24 * 3600
    static let nightReminderTitle = "Gece yardıma gidiyorsun"
    static let nightReminderMessage = "Mümkünse biriyle git ve konumunu bir yakınınla paylaş. Işıksız, ıssız ya da kapalı bir yere (bina içi, inşaat, bodrum) girme. Durum şüpheliyse yaklaşma, 112'yi ara."
    static let nightReminderContinueTitle = "Devam et"

    /// Hatırlatmanın başlığı: gece ya da ilk gidiş ("Yardıma gidiyorsun").
    static func reminderTitle(_ kind: NightReminder.Kind) -> String {
        switch kind {
        case .night: nightReminderTitle
        case .firstGo: Messages.goSafetyTitle
        }
    }

    static func reminderMessage(_ kind: NightReminder.Kind) -> String {
        switch kind {
        case .night: nightReminderMessage
        case .firstGo: Messages.safetyRule
        }
    }

    /// "Konumu paylaş" bu ihtiyaçların kartında: ilgilenene döşeme, diğerlerine "⋯ Diğer" menüsünde.
    static let shareLocationNeeds: Set<Need> = [.emergency, .injured, .babies]
    static let shareLocationTitle = "Konumu paylaş"

    private(set) var reports: [Report] = []
    private(set) var now = Date()
    private(set) var mode: Mode = .browsing
    /// Açık kart; yalnızca `selectReport(_:)` ile değişir (yakınlık da o an ölçülür).
    private(set) var selectedReportID: String? = nil
    /// Kart açılırken hayvana yakın mıydın (`CardLayout.isNear`); kart açıkken düğmeler yer değiştirmesin diye
    /// yeniden ölçülmez. Konum yoksa `false` ("uzak").
    private(set) var cardIsNear = false
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
    /// `config/public.minBuild`; yoksa `nil` (bkz. `requiresUpdate`).
    private(set) var minBuild: Int? = nil
    /// `users/{me}`: hesap yaşı ve günlük haklar; okunana kadar `nil`.
    private(set) var userRecord: UserRecord? = nil
    /// Onay bekleyen itiraz (bkz. `handle(_:on:)`, `disputeQuestion`).
    private(set) var disputeCandidateID: String? = nil
    /// Gösterilecek takip sorusu (A7); arayüz bunu sayfa olarak açar.
    private(set) var followUp: FollowUp? = nil
    /// İhtiyaç seçildi, önce soru soruluyor (bkz. `PendingReport`).
    private(set) var pendingReport: PendingReport? = nil
    /// Düzeltme kaydediliyor: panel düğmeleri beklesin.
    private(set) var isSavingEdit = false
    /// Düzeltmede iğne işaretin konumundan izin verilenden uzağa kaydı (kamera durunca güncellenir).
    private(set) var isEditTargetTooFar = false
    /// "Bu işarette ne sorun var?" sorulan işaret.
    private(set) var flagCandidateID: String? = nil
    /// "Bu işareti silmek istiyor musun?" sorulan işaret (düzeltme panelinden).
    private(set) var retractCandidateID: String? = nil
    /// Gösterilecek güvenlik hatırlatması (gece ya da ilk gidiş).
    private(set) var nightReminder: NightReminder? = nil
    /// Bu kimlik konsoldan engellendi (`banned/{me}` görüldü): üst etikette söylenir, yeni işaret açılmaz.
    private(set) var isBanned = false
    /// İşaretlerken iğne şimdi kaydedilebilir mi (`PlacementGate`): paneldeki tek satır ve ihtiyaç düğmeleri.
    /// Yalnızca değişince yazılır; göz atarken hep `ready`.
    private(set) var placementVerdict: PlacementVerdict = .ready
    /// Haritadaki çevre halkası (kişinin konumu ve izin verilen yarıçap); işaretlerken ve konum kullanılabilirken.
    private(set) var placementArea: PlacementArea? = nil
    /// Kullanılabilir konum var ve iğne ondan uzakta: "İğneyi konumuma getir".
    private(set) var canRecenterPin = false
    /// Düzeltmede iğne işaretin yerinden kaydırıldı: "İğneyi eski yerine getir".
    private(set) var isEditingPinMoved = false
    /// Konum izni kapalıyken "Yardım gereken hayvan": "Konum izni gerekiyor" uyarısı.
    private(set) var locationAlert = false
    /// Engellenen her dokunuşta ve iğne engele girince artar; uyarı titreşimini tetikler.
    private(set) var blockedFeedback = 0
    /// Ekrandaki "Hâlâ orada mı?" sorusu.
    private(set) var nearbyPrompt: NearbyQuestion? = nil
    /// Her yeni "Hâlâ orada mı?" sorusunda artar; hafif titreşimi tetikler.
    private(set) var nearbyPromptsShown = 0

    let environment: AppEnvironment
    private var repository: ReportRepository { environment.repository }
    var session: UserSession { environment.session }
    var location: LocationProvider { environment.location }
    var watched: WatchedReports { environment.watched }
    var device: DeviceState { environment.device }

    @ObservationIgnored private var cameraTarget: Coordinate?
    @ObservationIgnored private var visibleArea: (center: Coordinate, radius: Double)?
    @ObservationIgnored private var subscribedArea: (center: Coordinate, radius: Double)?
    @ObservationIgnored private var subscription: ReportSubscription?
    @ObservationIgnored private var userRecordSubscription: ReportSubscription?
    @ObservationIgnored private var publicConfigSubscription: ReportSubscription?
    @ObservationIgnored private var hasCenteredOnUser = false
    /// "Hayır, başka bir hayvan" denen öneriler; yeni işaretleme başlayınca sıfırlanır.
    @ObservationIgnored private var dismissedDuplicateIDs: Set<String> = []
    /// Bu işaretleme boyunca "Yardıma ihtiyacı var" denen ihtiyaçlar: "İğneyi düzelt"ten sonra yeniden sorulmaz.
    @ObservationIgnored private var confirmedGentleChecks: Set<Need> = []
    /// Sırada bekleyen takip soruları (en yeni öneri önce).
    @ObservationIgnored private var followUpQueue: [Report] = []
    /// `banned/{me}`'e en son ne zaman bakıldı (bkz. `checkBannedAfterDenial`).
    @ObservationIgnored private var lastBannedCheck: Date?
    /// İşaretleme başladığı an: bu kadar süredir konum yoksa "hâlâ bulunamadı" denir.
    @ObservationIgnored private var locatingSince: Date?
    /// Kişi bu işaretlemede haritayı kendisi kaydırdı: konum sonradan gelince iğne yerinden oynatılmaz.
    @ObservationIgnored private var userMovedPin = false
    /// İşaretleme kullanılabilir konum olmadan başladı: konum gelince iğne bir kez kişinin üstüne gelir.
    @ObservationIgnored private var startedWithoutFix = false
    /// İşaretlerken kararı 2 sn'de bir yeniler.
    @ObservationIgnored private var placementTicker: Task<Void, Never>?
    /// Son engel duyurusu (VoiceOver).
    @ObservationIgnored private var lastBlockedAnnouncement: Date?
    /// Sahne etkin mi (uygulama önde).
    @ObservationIgnored private var isSceneActive = true
    /// Açıklama sayfası (ve içinden açılan kurallar) açık: arkasındaki karartılmış haritada "Hâlâ orada mı?"
    /// görünür ama dokunulamaz.
    @ObservationIgnored private var isLegendShown = false
    /// Harita en son ne zaman etkin oldu (açılış, öne gelme, kuralların kabulü): "Hâlâ orada mı?" hemen sorulmaz.
    @ObservationIgnored private var activeSince = Date()
    /// Kişinin son kendi işareti: hemen ardından başkasınınki sorulmaz.
    @ObservationIgnored private var lastOwnReportAt: Date?
    /// "Hâlâ orada mı?" okumayla en son ne zaman değerlendirildi.
    @ObservationIgnored private var lastNearbyFixEvaluation: Date?
    /// Sıklık engeli kalkınca bir kez yeniden bakılır.
    @ObservationIgnored private var nearbyRecheck: Task<Void, Never>?
    @ObservationIgnored private var nearbyRecheckAt: Date?
    /// Sıradaki değerlendirme zaten istendi (aynı turda birden çok istek tek değerlendirme olur).
    @ObservationIgnored private var nearbyEvaluationPending = false
    /// Sorunun adımı değişince artar: eski adımın zamanlayıcıları hiçbir şey yapmaz.
    @ObservationIgnored private var nearbyStepToken = 0

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: Türetilmiş durum

    var userID: String? { session.userID }
    var isPlacing: Bool { mode != .browsing }

    /// Süresi dolmamış, kapanmamış işaretler (sunucu temizliğini beklemeden). "… dendi" de aktiftir.
    /// Bu kişinin bildirdiği ya da gizlediği işaretler yoktur: haritada, sayılarda ve önerilerde görünmez.
    var activeReports: [Report] {
        reports.filter { $0.isActive(at: now) && !device.isHidden($0.id) }
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

    /// Üst etiketin sayıları (`Messages.waitingHeadline`): bekleyen, başkasının 45 dk'yı geçen sahipliği ve
    /// doğrulanmamış ("?") öneri; ağır ihtiyaçlar ve hafifler (mama, "düşük öncelikli") ayrı.
    var waitingCounts: WaitingCounts {
        ClosingDisplay.waitingCounts(activeReports, viewer: userID, mode: closingMode, at: now)
    }

    /// Son 24 saatte kalan yeni işaret hakkı; kayıt henüz okunmadıysa `nil`.
    var remainingCreates: Int? {
        userRecord.map { Budget.remainingCreates($0, at: now) }
    }

    /// Seçim panelinde: "3 yeni işaret hakkın kaldı" (≤ `lowCreatesThreshold`) ya da hak bittiyse
    /// "Yeni işaret hakkın saat 14.20'de açılır"; düzeltmede ve hak boldaysa `nil`.
    var createAllowanceText: String? {
        guard let userRecord, !isEditing else { return nil }
        return Messages.createAllowance(userRecord, lowThreshold: Self.lowCreatesThreshold, now: now)
    }

    /// Onay bekleyen itirazın işareti.
    var disputeCandidate: Report? {
        guard let disputeCandidateID else { return nil }
        return activeReports.first { $0.id == disputeCandidateID }
    }

    /// "Bu işarette ne sorun var?" sorulan işaret.
    var flagCandidate: Report? {
        guard let flagCandidateID else { return nil }
        return activeReports.first { $0.id == flagCandidateID }
    }

    /// "Bu işareti silmek istiyor musun?" sorulan işaret.
    var retractCandidate: Report? {
        guard let retractCandidateID else { return nil }
        return activeReports.first { $0.id == retractCandidateID }
    }

    /// Onay, seçim ya da hatırlatma açık: takip sorusu sayfası bunlar kapanınca gösterilir.
    var isShowingPrompt: Bool {
        disputeCandidate != nil || flagCandidate != nil || retractCandidate != nil || nightReminder != nil
    }

    /// Kurallar sayfası gösterilmeli: bu sürümün kuralları bu cihazda henüz kabul edilmedi.
    var needsOnboarding: Bool {
        device.acceptedTermsVersion < AppInfo.termsVersion
    }

    /// Bu derleme `config/public.minBuild`den eski: "Güncelleme gerekli" sayfası kapatılamaz.
    var requiresUpdate: Bool {
        AppInfo.requiresUpdate(build: AppInfo.build, minBuild: minBuild)
    }

    func distance(to report: Report) -> Double? {
        location.coordinate?.distance(to: report.coordinate)
    }

    /// "Yanlış mı? Bize yaz": iğne alan yüzünden engellendiyse ve iletişim adresi varsa hazır e-posta
    /// (iğnenin yaklaşık yeri, ~1 km). Adres boşken `nil`: düğme gösterilmez.
    var reportWrongURL: URL? {
        guard placementVerdict.isAreaBlock, let pin = cameraTarget else { return nil }
        return AppInfo.supportMailURL(
            subject: Messages.reportWrongBlockMailSubject,
            body: Messages.reportWrongBlockMailBody(
                placementVerdict,
                dataVersion: environment.areaClassifier.dataVersion,
                pin: pin
            )
        )
    }

    // MARK: Düzeltme durumu

    var editingReportID: String? {
        if case .editing(let reportID, _) = mode { return reportID }
        return nil
    }

    var isEditing: Bool { editingReportID != nil }

    /// Düzeltilen işaret (haritadaki güncel hâli); panel mevcut türü ve ihtiyacı bundan gösterir.
    var editingReport: Report? {
        guard let editingReportID else { return nil }
        return activeReports.first { $0.id == editingReportID }
    }

    /// Ortadaki iğnenin türü: ihtiyaç seçilirken seçilen tür, düzeltmede seçilen ya da işaretin türü.
    var placementSpecies: Species? {
        switch mode {
        case .choosingNeed(let species):
            return species
        case .editing(_, let species):
            return species ?? editingReport?.species
        case .browsing, .choosingSpecies:
            return nil
        }
    }

    /// Düzeltme panelinde "İşareti sil" gösterilsin mi (`ReportLifecycle.canRetract`).
    var canRetractEditing: Bool {
        guard let report = editingReport, let userID else { return false }
        return ReportLifecycle.canRetract(report, by: userID)
    }

    /// Kartta "Düzenle" gösterilsin mi (`ReportLifecycle.canEdit`: koyan, kimse dokunmadan, 30 dk içinde, en fazla 3 kez).
    func canEdit(_ report: Report) -> Bool {
        guard let userID else { return false }
        return ReportLifecycle.canEdit(report, by: userID, at: now)
    }

    // MARK: Kart

    /// "⋯ Diğer" menüsündeki bildir ve gizle işareti koyana gösterilmez.
    func canFlag(_ report: Report) -> Bool {
        guard let userID else { return false }
        return report.reporterID != userID
    }

    /// Kartın düzeni (`CardLayout.plan`): birincil düğme, yakınlığa göre döşemeler ve "⋯ Diğer" menüsü.
    /// Yakınlık kart açılırken ölçülen değerdir (`cardIsNear`).
    func cardPlan(for report: Report) -> CardPlan {
        CardLayout.plan(
            for: report,
            userID: userID,
            at: now,
            isNear: selectedReportID == report.id && cardIsNear,
            canEdit: canEdit(report),
            canShare: Self.shareLocationNeeds.contains(report.need),
            canFlag: canFlag(report),
            hasMail: flagMailURL(for: report) != nil
        )
    }

    /// Kartı açar (`reportID`) ya da kapatır (`nil`). Yakınlık burada bir kez ölçülür: taze (≤ 2 dk), doğru
    /// (≤ 50 m) bir konumla hayvana en fazla 100 m. Aynı kart yeniden açılınca yeniden ölçülür.
    private func selectReport(_ reportID: String?) {
        if reportID != nil {
            // Kart açıldı: "Hâlâ orada mı?" kesilir (sayılmaz).
            endNearbyPrompt(.interrupted)
        }
        selectedReportID = reportID
        var near = false
        if let reportID, let fix = location.fix, let report = reports.first(where: { $0.id == reportID }) {
            near = CardLayout.isNear(
                distance: fix.coordinate.distance(to: report.coordinate),
                accuracy: fix.horizontalAccuracy,
                fixAge: Date().timeIntervalSince(fix.timestamp)
            )
        }
        if near != cardIsNear {
            cardIsNear = near
        }
    }

    /// "E-postayla ayrıntı gönder": işaret kimliğiyle hazır e-posta; iletişim adresi yoksa `nil` (menüde yok).
    func flagMailURL(for report: Report) -> URL? {
        AppInfo.supportMailURL(subject: Messages.flagMailSubject, body: Messages.flagMailBody(reportID: report.id))
    }

    // MARK: Yaşam döngüsü

    /// Ekran açıkken çalışır: oturum açar, hesap kaydını hazırlar, "x dk önce" metinlerini ve süresi
    /// dolanları günceller.
    func run() async {
        // Okuma başına ekran yeniden çizilmesin: işaretleme durumu gözlenmeyen geri çağrılarla güncellenir.
        location.onFix = { [weak self] in
            self?.locationFixed()
        }
        location.onAccessChange = { [weak self] in
            self?.locationAccessChanged()
        }
        activeSince = Date()
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
        // Önceki açılışta engelliydi: etiket hemen söyler; sahip kaldırmış olabilir, bir kez bakılır.
        if device.knownBanned {
            isBanned = true
            Task { [weak self] in
                await self?.refreshBanned(userID)
            }
        }
        requestNearbyEvaluation()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            now = Date()
            evaluateNearbyPrompt(now: now)
        }
    }

    /// Uygulama öne geldi: saat metinleri hemen güncellenir, konum yeniden başlar, takip edilen işaretler (en fazla
    /// 10 dk'da bir) okunur.
    func appBecameActive() {
        now = Date()
        activeSince = now
        location.start()
        Task { [weak self] in
            await self?.refreshWatched()
        }
        requestNearbyEvaluation()
    }

    /// Sahne etkinleşti ya da etkinliğini yitirdi (arka plan, Denetim Merkezi, gelen arama).
    func scenePhaseChanged(isActive: Bool) {
        guard isActive != isSceneActive else { return }
        isSceneActive = isActive
        if isActive {
            appBecameActive()
        } else {
            endNearbyPrompt(.interrupted)
        }
    }

    /// Açıklama sayfası açıldı ya da kapandı. Açıkken "Hâlâ orada mı?" sorulmaz; ekrandaki soru kesilir (yanıtsız
    /// sayılmaz). Kapanınca yeniden bakılır.
    func legendPresented(_ shown: Bool) {
        guard shown != isLegendShown else { return }
        isLegendShown = shown
        if shown {
            endNearbyPrompt(.interrupted)
        } else {
            requestNearbyEvaluation()
        }
    }

    private func observeAccount(_ userID: String) {
        userRecordSubscription = repository.observeUserRecord(userID: userID) { [weak self] record in
            self?.userRecord = record
        }
        publicConfigSubscription = repository.observePublicConfig { [weak self] config in
            guard let self else { return }
            self.closingMode = config.closingMode
            self.minBuild = config.minBuild
            if self.requiresUpdate {
                // Kapatılamayan "Güncelleme gerekli" sayfası açılır.
                self.endNearbyPrompt(.interrupted)
            }
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
        requestNearbyEvaluation()
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

    // MARK: Kurallar

    /// "Kabul ediyorum, başla": bu sürümün kuralları bu cihazda bir daha sorulmaz.
    func acceptTerms() {
        device.acceptTerms(version: AppInfo.termsVersion)
        activeSince = Date()
        showNextFollowUp()
        requestNearbyEvaluation()
    }

    // MARK: Harita olayları

    /// Kişi haritayı kendisi hareket ettirmeye başladı (programatik kamera hareketi değil).
    func cameraWillMove() {
        isCameraMoving = true
        if isPlacing {
            userMovedPin = true
        }
        endNearbyPrompt(.interrupted)
    }

    /// Her karede: halka ve ihtiyaç düğmeleri iğneyi canlı izler.
    func cameraMoved(to center: Coordinate) {
        cameraTarget = center
        if isPlacing {
            updatePlacementVerdict(now: Date())
        }
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
        // İğne kaydırıldı: yakındaki aynı hayvan yeniden aranır, karar ve düzeltme uzaklığı yeniden denetlenir.
        updatePlacementVerdict(now: Date())
        updateDuplicateCandidate()
        requestNearbyEvaluation()
    }

    /// İğne ya da gri nokta.
    func markerTapped(_ reportID: String) {
        guard mode == .browsing else { return }
        // Başka bir işaretin "Geri al" bildirimi yeni kartın üstünde kalmasın (hangi işareti geri alacağı belli olmaz).
        if let undoID = toast?.undoReportID, undoID != reportID {
            toast = nil
        }
        selectReport(reportID)
        // Kart haritanın alt yarısını örter: işaret, kart ile üst kenar arasındaki alanın ortasına gelsin.
        if let report = reports.first(where: { $0.id == reportID }) {
            cameraRequest = CameraRequest(target: report.coordinate)
        }
    }

    func mapTapped() {
        selectReport(nil)
    }

    func mapLongPressed(at coordinate: Coordinate) {
        if isEditing {
            // Düzeltme sürer; iğne basılan yere gider. Çevrenin ya da alanın dışındaysa panel söyler, 200 m sınırı
            // kaydederken de denetlenir.
            cameraRequest = CameraRequest(target: coordinate, zoom: Self.placementZoom)
            return
        }
        startPlacing(at: coordinate)
    }

    func closeCard() {
        selectReport(nil)
        requestNearbyEvaluation()
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
            // Sorulan işaret de artık bilinmiyor.
            endNearbyPrompt(.interrupted)
            // İşaretler kalkınca kart da kapanır; yeniden yakınlaşınca kendiliğinden açılmasın.
            selectReport(nil)
            // Düzeltilen işaret de artık bilinmiyor.
            if isEditing {
                finishEditing(select: nil, message: nil)
            }
            return
        }
        if let subscribed = subscribedArea,
           subscribed.center.distance(to: area.center) + area.radius <= subscribed.radius {
            return
        }
        let radius = max(area.radius * 1.5, Self.minQueryRadius)
        subscription?.cancel()
        subscription = repository.observeActiveReports(center: area.center, radiusMeters: radius) { [weak self] reports in
            guard let self else { return }
            self.reports = reports
            self.now = Date()
            self.reportsChanged()
        }
        subscribedArea = (area.center, radius)
    }

    /// Düzeltilen işaret bu arada kapandıysa, süresi dolduysa ya da başkası dokunduysa düzeltme biter. Sorulan
    /// işaret artık yardım beklemiyorsa soru kalkar; yakında yeni bir işaret belirmiş olabilir.
    private func reportsChanged() {
        if let prompt = nearbyPrompt {
            let current = activeReports.first { $0.id == prompt.report.id }
            if current?.isWaiting(at: Date()) != true {
                endNearbyPrompt(.interrupted)
            }
        }
        requestNearbyEvaluation()
        guard let reportID = editingReportID, !isSavingEdit, let userID else { return }
        guard let report = activeReports.first(where: { $0.id == reportID }) else {
            finishEditing(select: nil, message: "Bu işaret artık haritada değil.")
            return
        }
        if !ReportLifecycle.canEdit(report, by: userID, at: Date()) {
            finishEditing(select: reportID, message: ReportError.notEditable.errorDescription)
        }
    }

    // MARK: Yeni işaret

    /// "Yardım gereken hayvan" (`pressed` `nil`) ya da haritaya uzun basma. İşaret yalnızca kişinin bulunduğu yerin
    /// çevresine konabilir (`PlacementGate`): izin kapalıysa uyarı çıkar, çevrenin dışına uzun basınca işaretleme
    /// başlamaz. Konum yoksa panel açılır ve "Konumun bulunuyor…"da bekler; konum gelince kendiliğinden açılır.
    func startPlacing(at pressed: Coordinate? = nil) {
        if isBanned {
            show(Toast(message: Messages.banned, duration: Self.longToastDuration))
            return
        }
        let now = Date()
        let access = location.access
        if access == .denied {
            // Panel hiç açılmaz: izin olmadan işaret konamaz.
            endNearbyPrompt(.interrupted)
            locationAlert = true
            return
        }
        let fix = location.gateFix(at: now)
        if let pressed, !PlacementGate.acceptsLongPress(at: pressed, fix: fix, at: now) {
            // Süren bir işaretleme de olduğu gibi kalır.
            show(Toast(message: Messages.farLongPress, duration: Self.longToastDuration))
            blockedFeedback += 1
            return
        }
        switch access {
        case .notDetermined:
            location.start()
        case .approximate:
            location.requestFullAccuracy()
        case .denied, .full:
            break
        }
        if let fix, fix.age(at: now) > PlacementGate.refreshIfOlderThan {
            location.refresh()
        }
        let usableFix = PlacementGate.isUsable(fix, at: now) ? fix : nil
        // En taze okuma: yayımlanan konum yalnızca 10 m'de bir değişir.
        let target = pressed ?? fix?.coordinate ?? location.coordinate ?? cameraTarget ?? visibleArea?.center

        endNearbyPrompt(.interrupted)
        selectReport(nil)
        toast = nil
        pendingReport = nil
        dismissedDuplicateIDs = []
        confirmedGentleChecks = []
        mode = .choosingSpecies
        locatingSince = now
        userMovedPin = false
        startedWithoutFix = pressed == nil && usableFix == nil
        if let target {
            // Hemen yazılır: kamera zaten oradaysa MapKit bölge değişikliği bildirmez.
            cameraTarget = target
            cameraRequest = CameraRequest(target: target, zoom: Self.placementZoom)
        }
        updatePlacementVerdict(now: now)
        updateDuplicateCandidate()
        startPlacementTicker()
    }

    func choose(_ species: Species) {
        pendingReport = nil
        if case .editing(let reportID, _) = mode {
            mode = .editing(reportID: reportID, species: species)
        } else {
            mode = .choosingNeed(species)
        }
        updateDuplicateCandidate()
    }

    func backToSpecies() {
        pendingReport = nil
        if case .editing(let reportID, _) = mode {
            mode = .editing(reportID: reportID, species: nil)
        } else {
            mode = .choosingSpecies
        }
        updateDuplicateCandidate()
    }

    /// Paneldeki "Vazgeç". Düzeltmede işaret değişmeden kalır ve kartı yeniden açılır.
    func cancelPlacing() {
        if let reportID = editingReportID {
            finishEditing(select: reportID, message: nil)
            return
        }
        pendingReport = nil
        returnToBrowsing()
        updateDuplicateCandidate()
        showNextFollowUp()
    }

    /// "Ben de gördüm": yeni işaret yerine iğnenin yakınındaki aynı hayvana "Hâlâ orada" denir ve kartı
    /// açılır; böylece aynı kedi için ikinci işaret çıkmaz, sayısı artar. Öneri bir "… dendi" işaretiyse
    /// ("Evet, hâlâ yardım gerekiyor") itiraz edilir: kişi hayvanın başında, ayrıca onay sorulmaz.
    func confirmDuplicate(_ report: Report) {
        let action = duplicateAction(for: report)
        pendingReport = nil
        returnToBrowsing()
        updateDuplicateCandidate()
        selectReport(report.id)
        cameraRequest = CameraRequest(target: report.coordinate)
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
    /// üzerinde bir şey yapılabilen aktif işaret (gizlenmiş "… dendi" de). İğne çevrenin dışındaysa ve başka her
    /// durumda (düzeltme dahil) öneri yoktur. Konum beklenirken ya da alan engelinde öneri kalır: yeni işaret
    /// açmaz.
    private func updateDuplicateCandidate() {
        var candidateID: String?
        if case .choosingNeed(let species) = mode, placementVerdict != .tooFar, let target = cameraTarget {
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

    /// Son dokunuş. Yeni işarette işaret iğnenin olduğu yere (kamera hedefine) kaydedilir; gerekirse önce
    /// "Yardıma ihtiyacı var mı?" sorulur (`pendingReport`). Günlük hak bittiyse kaydedilmez; iğne yerinde kalır ki
    /// yakındaki aynı hayvana "Ben de gördüm" denebilsin. Düzeltmede değişiklik kaydedilir.
    func choose(_ need: Need) {
        switch mode {
        case .editing(let reportID, let species?):
            saveEdit(reportID: reportID, species: species, need: need)
        case .choosingNeed(let species):
            guard pendingReport == nil, let target = cameraTarget else { return }
            // Son söz bu andaki karar: düğme açıkken okuma eskimiş olabilir. Engel hiçbir zaman sessiz değildir.
            let now = Date()
            updatePlacementVerdict(now: now)
            guard placementVerdict == .ready else {
                signalBlocked(now: now)
                return
            }
            placeReport(species: species, need: need, at: target)
        case .browsing, .choosingSpecies, .editing:
            return
        }
    }

    /// Hafif ihtiyaçta bazen önce "Yardıma ihtiyacı var mı?"; yoksa hemen kaydedilir.
    private func placeReport(species: Species, need: Need, at target: Coordinate) {
        guard session.userID != nil else {
            show(Toast(message: "Bağlantı kuruluyor, birkaç saniye sonra tekrar dene."))
            return
        }
        if let step = gentleCheckStep(for: need, at: Date()) {
            pendingReport = PendingReport(species: species, need: need, coordinate: target, step: step)
            return
        }
        createReport(species: species, need: need, at: target)
    }

    /// "Yardıma ihtiyacı var, işaretle": işaret, ihtiyaca dokunulduğu andaki yere kaydedilir. Yakınlık kapısı
    /// yeniden denetlenmez: kişiye önce sorulup sonra "konamaz" denmesin.
    func confirmPendingReport() {
        guard let pending = pendingReport else { return }
        // Sınır yüzünden kaydedilemezse aynı ihtiyaca yeniden dokununca bir daha sorulmaz.
        confirmedGentleChecks.insert(pending.need)
        pendingReport = nil
        createReport(species: pending.species, need: pending.need, at: pending.coordinate)
    }

    /// "Sağlıklı görünüyor, vazgeç": işaretleme biter, teşekkür edilir.
    func cancelPendingReport() {
        guard pendingReport != nil else { return }
        pendingReport = nil
        returnToBrowsing()
        updateDuplicateCandidate()
        show(Toast(message: Messages.gentleCheckCancelled, duration: Self.longToastDuration))
        showNextFollowUp()
    }

    /// Cihazın ilk hafif işaretleri ya da son 24 saatte çok işaret: "Yardıma ihtiyacı var mı?".
    private func gentleCheckStep(for need: Need, at now: Date) -> PendingReport.Step? {
        guard !confirmedGentleChecks.contains(need),
              let reason = GentleCheck.reason(
                for: need,
                lightReportsSoFar: device.lightReportCount,
                recentReports: device.recentReportCount(at: now)
              )
        else { return nil }
        switch reason {
        case .intro: return .gentleCheck(recentCount: nil)
        case .recent(let count): return .gentleCheck(recentCount: count)
        }
    }

    private func createReport(species: Species, need: Need, at target: Coordinate) {
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
        device.recordReport(id: report.id, need: need, at: now)
        // Kendi işaretinden hemen sonra başkasınınki sorulmaz ("Hâlâ orada mı?").
        lastOwnReportAt = now
        returnToBrowsing()
        updateDuplicateCandidate()
        reportsCreated += 1
        show(Toast(message: "\(species.title) · \(need.title) işaretlendi", undo: .retract(reportID: report.id)))
        showNextFollowUp()
    }

    // MARK: Yakınlık kapısı

    /// Kararı, çevre halkasını ve panelin düğmelerini yeniden hesaplar. Bir uzaklık ve bir ızgara bakışıdır, her
    /// karede çağrılabilir; değerler yalnızca değişince yazılır. İğne hazırken engele girerse uyarı titreşimi ve
    /// (VoiceOver'da, en fazla 3 sn'de bir) duyuru.
    private func updatePlacementVerdict(now: Date) {
        guard isPlacing else {
            resetPlacementState()
            return
        }
        let fix = location.gateFix(at: now)
        let isFixUsable = PlacementGate.isUsable(fix, at: now)
        let since = locatingSince ?? now
        var verdict = PlacementVerdict.locating(slow: now.timeIntervalSince(since) >= PlacementGate.slowLocatingAfter)
        var recenter = false
        var moved = false
        if let pin = cameraTarget {
            // İğnenin (kişinin değil) alanı.
            let pinArea = environment.areaClassifier.areaClass(at: pin)
            if isEditing, let original = editingReport?.coordinate {
                verdict = PlacementGate.editVerdict(
                    original: original,
                    pin: pin,
                    fix: fix,
                    access: location.access,
                    rejectsSimulated: environment.rejectsSimulatedFixes,
                    area: pinArea,
                    locatingSince: since,
                    at: now
                )
                moved = original.distance(to: pin) >= PlacementGate.unmovedTolerance
            } else {
                verdict = PlacementGate.verdict(
                    pin: pin,
                    fix: fix,
                    access: location.access,
                    rejectsSimulated: environment.rejectsSimulatedFixes,
                    area: pinArea,
                    locatingSince: since,
                    at: now
                )
            }
            if isFixUsable, let fix {
                recenter = pin.distance(to: fix.coordinate) > Self.recenterPinDistance
            }
        }

        var area: PlacementArea?
        if isFixUsable, let fix {
            var center = fix.coordinate
            var radius = PlacementGate.allowedRadius(accuracy: fix.horizontalAccuracy)
            if let shown = placementArea, !Self.placementAreaMoved(from: shown, center: center, radius: radius) {
                // Konumun birkaç metrelik oynaması halkayı yeniden çizdirmez. Engel değişince merkez ve yarıçap
                // aynı kalır ki harita halkayı yeniden eklemeden yalnızca rengini değiştirsin.
                center = shown.center
                radius = shown.radius
            }
            area = PlacementArea(center: center, radius: radius, isBlocked: verdict.isBlocking)
        }
        if area != placementArea {
            placementArea = area
        }
        if recenter != canRecenterPin {
            canRecenterPin = recenter
        }
        if moved != isEditingPinMoved {
            isEditingPinMoved = moved
        }
        updateEditRange()

        guard verdict != placementVerdict else { return }
        let wasReady = placementVerdict == .ready
        placementVerdict = verdict
        if wasReady && verdict.isBlocking {
            blockedFeedback += 1
            announcePlacement(verdict, force: false, now: now)
        }
        // "Ben de gördüm" çevrenin dışındayken gösterilmez.
        updateDuplicateCandidate()
    }

    /// Halka ancak merkezi ya da yarıçapı 2 m kayınca yeniden çizilir.
    private static func placementAreaMoved(from shown: PlacementArea, center: Coordinate, radius: Double) -> Bool {
        shown.center.distance(to: center) >= placementAreaTolerance
            || abs(shown.radius - radius) >= placementAreaTolerance
    }

    /// Engellenen dokunuş: titreşim ve duyuru, her seferinde.
    private func signalBlocked(now: Date) {
        blockedFeedback += 1
        announcePlacement(placementVerdict, force: true, now: now)
    }

    /// Engel metni VoiceOver'a (başlıktaki satır kendiliğinden okunmaz).
    private func announcePlacement(_ verdict: PlacementVerdict, force: Bool, now: Date) {
        guard UIAccessibility.isVoiceOverRunning,
              let message = Messages.placementMessage(verdict, isEditing: isEditing)
        else { return }
        if !force, let last = lastBlockedAnnouncement,
           now.timeIntervalSince(last) < Self.blockedAnnouncementInterval {
            return
        }
        lastBlockedAnnouncement = now
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// İşaretlerken 2 sn'de bir: okuma eskidi mi, "hâlâ bulunamadı" zamanı geldi mi.
    private func startPlacementTicker() {
        placementTicker?.cancel()
        placementTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.placementTickInterval))
                guard !Task.isCancelled, let self else { return }
                self.updatePlacementVerdict(now: Date())
            }
        }
    }

    /// İşaretleme ya da düzeltme bitti: karar sıfırlanır, halka kalkar, zamanlayıcı durur.
    private func returnToBrowsing() {
        mode = .browsing
        resetPlacementState()
        requestNearbyEvaluation()
    }

    private func resetPlacementState() {
        placementTicker?.cancel()
        placementTicker = nil
        locatingSince = nil
        userMovedPin = false
        startedWithoutFix = false
        if placementVerdict != .ready {
            placementVerdict = .ready
        }
        if placementArea != nil {
            placementArea = nil
        }
        if canRecenterPin {
            canRecenterPin = false
        }
        if isEditingPinMoved {
            isEditingPinMoved = false
        }
        if isEditTargetTooFar {
            isEditTargetTooFar = false
        }
    }

    /// Kabul edilen her konum okumasında (gözlenmeyen geri çağrı).
    private func locationFixed() {
        let now = Date()
        if isPlacing {
            if startedWithoutFix, !userMovedPin, !isEditing, pendingReport == nil,
               let fix = location.gateFix(at: now), PlacementGate.isUsable(fix, at: now) {
                // İşaretleme konumsuz başladı: konum gelince iğne bir kez kişinin üstüne gelir.
                startedWithoutFix = false
                cameraTarget = fix.coordinate
                cameraRequest = CameraRequest(target: fix.coordinate, zoom: Self.placementZoom)
            }
            updatePlacementVerdict(now: now)
        }
        checkNearbyPromptRange(now: now)
        if let last = lastNearbyFixEvaluation, now.timeIntervalSince(last) < Self.nearbyFixEvaluationInterval {
            return
        }
        lastNearbyFixEvaluation = now
        evaluateNearbyPrompt(now: now)
    }

    /// İzin ya da Tam Konum değişti.
    private func locationAccessChanged() {
        if isPlacing {
            updatePlacementVerdict(now: Date())
        }
    }

    /// "İğneyi konumuma getir".
    func recenterPin() {
        let now = Date()
        guard isPlacing, let fix = location.gateFix(at: now), PlacementGate.isUsable(fix, at: now) else { return }
        startedWithoutFix = false
        cameraTarget = fix.coordinate
        cameraRequest = CameraRequest(target: fix.coordinate, zoom: Self.placementZoom)
        updatePlacementVerdict(now: now)
    }

    /// Düzeltmede "İğneyi eski yerine getir": iğne işaretin kayıtlı yerine döner (tür ve ihtiyaç her yerden
    /// düzeltilebilir).
    func restoreEditPin() {
        guard let report = editingReport else { return }
        cameraTarget = report.coordinate
        cameraRequest = CameraRequest(target: report.coordinate, zoom: Self.placementZoom)
        updatePlacementVerdict(now: Date())
    }

    func dismissLocationAlert() {
        locationAlert = false
        requestNearbyEvaluation()
    }

    private func createFailed(_ report: Report, error: Error) {
        watched.forget(report.id)
        device.forgetReport(id: report.id)
        let message: String
        if let quota = error as? CreateQuotaError {
            // Çevrimdışı konup ~24 saat sonra gönderilen işaret sınır yüzünden değil, gecikme yüzünden reddedilir.
            message = quota == .tooLate ? Messages.createTooLate : Messages.createRejected
            if quota == .rejected {
                checkBannedAfterDenial()
            }
        } else {
            message = "İşaret kaydedilemedi. Lütfen tekrar dene."
        }
        show(Toast(message: message))
    }

    /// Bildirimdeki "Geri al".
    func undo(_ toast: Toast) {
        guard let undo = toast.undo else { return }
        self.toast = nil
        switch undo {
        case .retract(let reportID):
            retract(reportID, failureMessage: "Geri alınamadı: başka biri de bu işaretle ilgilendi.")
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

    /// "Geri al" ve "İşareti sil": işaret takipten ve son 24 saatin sayısından çıkar; sunucu reddederse söylenir.
    private func retract(_ reportID: String, failureMessage: String) {
        watched.forget(reportID)
        device.forgetReport(id: reportID)
        repository.retract(reportID: reportID) { [weak self] error in
            self?.show(Toast(message: failureMessage))
            if (error as? RepositoryError) == .permissionDenied {
                self?.checkBannedAfterDenial()
            }
        }
    }

    // MARK: Düzeltme

    /// Karttaki "Düzenle": iğne işaretin üstünde, önce tür sonra ihtiyaç sorulur. Tür ve ihtiyaç her yerden
    /// düzeltilebilir; iğne yalnızca kişinin çevresine kaydırılabilir (`PlacementGate.editVerdict`).
    func startEditing(_ report: Report) {
        if isBanned {
            show(Toast(message: Messages.banned, duration: Self.longToastDuration))
            return
        }
        guard canEdit(report) else {
            show(Toast(message: ReportError.notEditable.errorDescription ?? "Bu işaret artık düzenlenemez."))
            return
        }
        let now = Date()
        endNearbyPrompt(.interrupted)
        selectReport(nil)
        toast = nil
        pendingReport = nil
        retractCandidateID = nil
        isEditTargetTooFar = false
        mode = .editing(reportID: report.id, species: nil)
        locatingSince = now
        userMovedPin = false
        startedWithoutFix = false
        cameraTarget = report.coordinate
        updateDuplicateCandidate()
        cameraRequest = CameraRequest(target: report.coordinate, zoom: Self.placementZoom)
        if let fix = location.gateFix(at: now), fix.age(at: now) > PlacementGate.refreshIfOlderThan {
            location.refresh()
        }
        updatePlacementVerdict(now: now)
        startPlacementTicker()
    }

    /// İğne işaretin şimdiki konumundan izin verilen kaymanın (~200 m) dışında mı?
    private func updateEditRange() {
        var tooFar = false
        if let report = editingReport, let target = cameraTarget {
            tooFar = !ReportLifecycle.isWithinEditRange(report, to: target)
        }
        if tooFar != isEditTargetTooFar {
            isEditTargetTooFar = tooFar
        }
    }

    /// İhtiyaca dokunuldu: tür, ihtiyaç ve iğnenin yeri tek bir düzeltme olarak kaydedilir. İğne kaydıysa önce
    /// ~200 m sınırı (kendi bildirimiyle), sonra yakınlık ve alan denetlenir.
    private func saveEdit(reportID: String, species: Species, need: Need) {
        guard !isSavingEdit, let userID = session.userID, let target = cameraTarget else { return }
        guard let report = activeReports.first(where: { $0.id == reportID }) else {
            finishEditing(select: nil, message: "Bu işaret artık haritada değil.")
            return
        }
        guard ReportLifecycle.canEdit(report, by: userID, at: Date()) else {
            finishEditing(select: reportID, message: ReportError.notEditable.errorDescription)
            return
        }
        let coordinate = target.distance(to: report.coordinate) < Self.editMoveThreshold ? report.coordinate : target
        guard ReportLifecycle.isWithinEditRange(report, to: coordinate) else {
            show(Toast(message: ReportError.editTooFar.errorDescription ?? "Konum en fazla 200 m kaydırılabilir."))
            return
        }
        if coordinate != report.coordinate {
            // Son söz bu andaki karar; kaydırılmayan iğne hiç denetlenmez.
            let now = Date()
            updatePlacementVerdict(now: now)
            guard placementVerdict == .ready else {
                signalBlocked(now: now)
                return
            }
        }
        if species == report.species && need == report.need && coordinate == report.coordinate {
            // Her kayıt bir düzeltme hakkı harcar; değişmeyen işaret yazılmaz.
            finishEditing(select: reportID, message: Messages.editUnchanged)
            return
        }
        isSavingEdit = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await self.repository.edit(
                    reportID: reportID,
                    species: species,
                    need: need,
                    coordinate: coordinate,
                    by: userID
                )
                self.isSavingEdit = false
                // Ömür değişmiş olabilir; takip süresi de uzasın.
                self.watched.watch(updated)
                // Dinleyici de bildirir; kart hemen yeni hâli göstersin.
                if let index = self.reports.firstIndex(where: { $0.id == updated.id }) {
                    self.reports[index] = updated
                }
                self.endSavedEdit(of: reportID, select: updated.id, message: Messages.reportEdited)
            } catch let error as ReportError {
                self.isSavingEdit = false
                let message = error.errorDescription ?? "Düzeltme kaydedilemedi."
                if error == .editTooFar {
                    self.show(Toast(message: message))
                } else {
                    self.endSavedEdit(of: reportID, select: reportID, message: message)
                }
            } catch RepositoryError.permissionDenied {
                self.isSavingEdit = false
                self.show(Toast(message: "Düzeltme kaydedilemedi."))
                self.checkBannedAfterDenial()
            } catch {
                self.isSavingEdit = false
                self.show(Toast(message: "Düzeltme kaydedilemedi. Bağlantını kontrol et."))
            }
        }
    }

    /// Kaydı biten düzeltme: kişi hâlâ o işareti düzeltiyorsa düzeltme biter ve kartı açılır. Bu arada panelden
    /// çıkıp başka bir şeye geçtiyse (ör. yeni işaret) o akış bozulmaz; yalnızca sonuç söylenir.
    private func endSavedEdit(of reportID: String, select selectID: String?, message: String) {
        if editingReportID == reportID {
            finishEditing(select: selectID, message: message)
        } else {
            show(Toast(message: message))
        }
    }

    /// Düzeltme biter; `reportID` verilirse (işaret hâlâ haritadaysa) kartı yeniden açılır.
    private func finishEditing(select reportID: String?, message: String?) {
        returnToBrowsing()
        pendingReport = nil
        retractCandidateID = nil
        updateDuplicateCandidate()
        if let reportID, let report = activeReports.first(where: { $0.id == reportID }) {
            selectReport(report.id)
            cameraRequest = CameraRequest(target: report.coordinate)
        }
        if let message {
            show(Toast(message: message))
        }
        showNextFollowUp()
    }

    /// Düzeltme panelindeki "İşareti sil": önce onay sorulur (`retractCandidate`).
    func requestRetract() {
        guard canRetractEditing, let editingReportID else { return }
        retractCandidateID = editingReportID
    }

    /// "Sil" onaylandı. İşaret, onay sorulduğu andaki hâliyle verilir.
    func confirmRetract(_ report: Report) {
        retractCandidateID = nil
        if editingReportID == report.id {
            returnToBrowsing()
            pendingReport = nil
            updateDuplicateCandidate()
        }
        if selectedReportID == report.id {
            selectReport(nil)
        }
        // Önce: sunucu reddederse hata bildirimi bunun yerine geçer.
        show(Toast(message: Messages.reportDeleted))
        retract(report.id, failureMessage: "Silinemedi: başka biri de bu işaretle ilgilendi.")
        showNextFollowUp()
    }

    func cancelRetract() {
        retractCandidateID = nil
    }

    // MARK: İşaret eylemleri

    /// Karttaki düğme ya da menü öğesi. "Hâlâ yardım gerekiyor" önce onay ister (`disputeCandidate`),
    /// "İlgileniyorum" gerekirse önce güvenliği hatırlatır (`nightReminder`); diğerleri hemen yapılır (mamada
    /// "Yardım gerekmiyor" ve "Artık yok" menüde ayrı öğelerdir).
    func handle(_ action: ReportAction, on report: Report) {
        if action == .dispute {
            disputeCandidateID = report.id
            return
        }
        if action == .claim, let kind = goReminderKind(for: report, at: Date()) {
            showReminder(NightReminder(kind: kind, report: report, pending: .claim))
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

    /// Bir eylemin sonucu (takip sorusu yeniden sorulacak mı diye).
    enum ActionResult {
        case done
        /// Başka bir eylem sürüyordu ya da oturum yok; hiçbir şey yazılmadı.
        case busy
        /// Sunucudaki güncel hâl eylemi artık kabul etmiyor (ör. öneri onaylandı, itiraz edildi, kapandı).
        case rejected
        /// Bağlantı ya da başka bir hata; sonra yeniden denenebilir.
        case failed
    }

    /// Eylemi yapar ve sonucu bildirir.
    @discardableResult
    func perform(_ action: ReportAction, on report: Report) async -> ActionResult {
        guard let userID = session.userID, busyAction == nil else { return .busy }
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
                    selectReport(nil)
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
                show(Toast(message: Messages.actionDone(
                    action,
                    outcome: outcome,
                    addsSeen: addsSeen,
                    userID: userID,
                    now: Date()
                )))
            }
            return .done
        } catch let error as ReportError {
            show(Toast(message: error.errorDescription ?? "İşlem tamamlanamadı."))
            return .rejected
        } catch RepositoryError.permissionDenied {
            show(Toast(message: "İşlem tamamlanamadı."))
            checkBannedAfterDenial()
            return .failed
        } catch {
            show(Toast(message: "İşlem tamamlanamadı. Bağlantını kontrol et."))
            return .failed
        }
    }

    /// A7: kişinin ilgilendiği işaretler takip edilir (koyduğu işaret `createReport`'ta eklenir).
    private func remember(_ action: ReportAction, _ report: Report) {
        switch action {
        case .claim, .confirmStillThere, .dispute:
            watched.watch(report)
        case .release, .resolve, .reportGone, .reportUnneeded, .confirmClosing, .undoClosing, .expire:
            break
        }
    }

    /// Apple Haritalar'da yürüyerek yol tarifi.
    func directionsURL(for report: Report) -> URL? {
        let destination = "\(report.coordinate.latitude),\(report.coordinate.longitude)"
        return URL(string: "https://maps.apple.com/?daddr=\(destination)&dirflg=w")
    }

    /// Karttaki "Yol tarifi": açılacak bağlantı. Güvenlik hatırlatması gösterilecekse `nil`; bağlantıyı
    /// "Devam et" döndürür (`continueAfterNightReminder`).
    func requestDirections(for report: Report) -> URL? {
        guard let url = directionsURL(for: report) else { return nil }
        if let kind = goReminderKind(for: report, at: Date()) {
            showReminder(NightReminder(kind: kind, report: report, pending: .directions(url)))
            return nil
        }
        return url
    }

    // MARK: Güvenlik hatırlatmaları

    /// "İlgileniyorum" ya da "Yol tarifi"nden önce gösterilecek hatırlatma: ikisi de uyuyorsa gece hatırlatması,
    /// yoksa bu cihazda bir kez "Yardıma gidiyorsun" (gece hatırlatması gösterildiyse o da sayılır). `-noNightReminder`
    /// ikisini de kapatır (arayüz testi; demo cihaz durumu her açılışta sıfırlanır).
    private func goReminderKind(for report: Report, at now: Date) -> NightReminder.Kind? {
        guard environment.nightReminderEnabled else { return nil }
        if needsNightReminder(for: report, at: now) { return .night }
        return device.goSafetyTipShown ? nil : .firstGo
    }

    /// Gece (yerel saatle 21.00–06.00) acil, yaralı ya da yavru işaretine gidilirken; kurulum başına haftada en
    /// fazla bir kez.
    private func needsNightReminder(for report: Report, at now: Date) -> Bool {
        guard environment.nightReminderEnabled, Self.nightReminderNeeds.contains(report.need) else { return false }
        let hour = Calendar.current.component(.hour, from: now)
        guard hour >= Self.nightStartHour || hour < Self.nightEndHour else { return false }
        guard let shownAt = device.nightReminderShownAt else { return true }
        // Saat geri alınmışsa da bir hafta beklenmez.
        return now.timeIntervalSince(shownAt) >= Self.nightReminderInterval || shownAt > now
    }

    private func showReminder(_ reminder: NightReminder) {
        switch reminder.kind {
        case .night:
            device.markNightReminderShown(at: Date())
            // Gece metni ilk gidişin kuralını da söylüyor: aynı yolculukta ikinci uyarı çıkmasın.
            device.markGoSafetyTipShown()
        case .firstGo:
            device.markGoSafetyTipShown()
        }
        nightReminder = reminder
    }

    /// "Devam et": bekleyen iş yapılır. Yol tarifiyse açılacak bağlantı döner. Hatırlatma, gösterildiği
    /// andaki hâliyle verilir.
    func continueAfterNightReminder(_ reminder: NightReminder) -> URL? {
        if nightReminder?.id == reminder.id {
            nightReminder = nil
        }
        switch reminder.pending {
        case .claim:
            Task { [weak self] in
                await self?.perform(.claim, on: reminder.report)
            }
            return nil
        case .directions(let url):
            return url
        }
    }

    func dismissNightReminder() {
        nightReminder = nil
    }

    // MARK: Bildirme ve gizleme

    /// "⋯ Diğer" → "Bu işareti bildir": önce neden sorulur (`flagCandidate`).
    func requestFlag(_ report: Report) {
        guard canFlag(report) else { return }
        flagCandidateID = report.id
    }

    /// Neden seçildi: bildirim gönderilir ve işaret bu kişinin haritasından kalkar. Aynı işaret daha önce
    /// bildirilmişse sunucu reddeder; bu da başarı sayılır.
    func flag(_ report: Report, reason: FlagReason) {
        flagCandidateID = nil
        guard let userID = session.userID else {
            show(Toast(message: "Bağlantı kuruluyor, birkaç saniye sonra tekrar dene."))
            return
        }
        if !isBanned {
            repository.flag(reportID: report.id, reason: reason, by: userID) { [weak self] in
                // Çoğunlukla ikinci bildirim; kimlik engellenmiş de olabilir.
                self?.checkBannedAfterDenial()
            }
        }
        removeFromMyMap(report)
        show(Toast(message: isBanned ? Messages.banned : Messages.flagSent, duration: Self.longToastDuration))
    }

    func cancelFlag() {
        flagCandidateID = nil
    }

    /// "⋯ Diğer" → "Bu işareti gizle": yalnızca bu kişinin haritasından kalkar.
    func hide(_ report: Report) {
        removeFromMyMap(report)
        show(Toast(message: Messages.reportHidden))
    }

    /// Haritadan, "yardım bekliyor" sayısından, "Aynı hayvan mı?" önerilerinden ve takip sorularından çıkar.
    private func removeFromMyMap(_ report: Report) {
        device.hide(report.id, at: Date())
        watched.forget(report.id)
        if selectedReportID == report.id {
            selectReport(nil)
        }
        updateDuplicateCandidate()
    }

    // MARK: Engel

    /// Bir yazım kurallarca reddedildi: kimlik engellenmiş olabilir. `banned/{me}` bir kez okunur (en fazla
    /// `bannedCheckInterval`'da bir); engelliyse söylenir ve üst etikette kalır.
    private func checkBannedAfterDenial() {
        guard !isBanned, let userID = session.userID else { return }
        let now = Date()
        if let lastBannedCheck, now.timeIntervalSince(lastBannedCheck) < Self.bannedCheckInterval { return }
        lastBannedCheck = now
        Task { [weak self] in
            guard let self, await self.refreshBanned(userID) else { return }
            self.show(Toast(message: Messages.banned, duration: Self.longToastDuration))
        }
    }

    /// `banned/{me}` okunur, sonuç cihazda da saklanır (sonraki açılışta yeniden bakılsın). Engelliyse `true`;
    /// okunamazsa bilinen durum değişmez.
    @discardableResult
    private func refreshBanned(_ userID: String) async -> Bool {
        guard let banned = await repository.isBanned(userID: userID) else { return isBanned }
        device.setKnownBanned(banned)
        isBanned = banned
        return banned
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

    /// `ClosingDisplay.isStakeholder` ile aynı ölçüt (`ReportLifecycle.canAnswerClosing`: "… dendi" ve bu kişi
    /// kapatan değil, onaylayabilir ya da itiraz edebilir). Yanıt veremeyene sorulmaz; işaret de onun
    /// haritasında yanıt beklemeden başkalarınınki gibi görünür. Kişinin gizlediği işaret sorulmaz.
    private func needsFollowUp(_ report: Report, userID: String, at now: Date) -> Bool {
        report.isActive(at: now)
            && !device.isHidden(report.id)
            && ReportLifecycle.canAnswerClosing(report, by: userID)
            && !watched.isAnswered(report)
    }

    /// Sıradaki soruyu gösterir; işaretleme sürerken, başka soru açıkken, kurallar kabul edilmemişken ya da
    /// güncelleme gerekiyorsa bekler.
    private func showNextFollowUp() {
        guard followUp == nil, mode == .browsing, !needsOnboarding, !requiresUpdate, let userID else { return }
        let now = Date()
        while !followUpQueue.isEmpty {
            let queued = followUpQueue.removeFirst()
            // Sıradayken değişmiş olabilir: haritadaki güncel hâline bakılır.
            let report = reports.first { $0.id == queued.id } ?? queued
            if needsFollowUp(report, userID: userID, at: now) {
                // Takip sorusu sayfası açılır: "Hâlâ orada mı?" kesilir.
                endNearbyPrompt(.interrupted)
                followUp = makeFollowUp(for: report, userID: userID, at: now)
                return
            }
        }
    }

    private func makeFollowUp(for report: Report, userID: String, at now: Date) -> FollowUp {
        var options: [FollowUp.Option] = []
        // "Doğru mu?" sorusu (onaylayabilen) → "Hayır, …"; "Hâlâ yardım gerekiyor mu?" sorusu → "Evet, …".
        let canConfirm = ReportLifecycle.canConfirmClosing(report, by: userID)
        if canConfirm {
            let reason = report.closing?.reason ?? .resolved
            options.append(FollowUp.Option(answer: .confirm, title: Messages.confirmClosingTitle(reason)))
        }
        if ReportLifecycle.canDispute(report, by: userID) {
            let title = canConfirm ? "Hayır, hâlâ yardım gerekiyor" : "Evet, hâlâ yardım gerekiyor"
            options.append(FollowUp.Option(answer: .dispute, title: title))
        }
        options.append(FollowUp.Option(answer: .dontKnow, title: canConfirm ? "Bilmiyorum" : "Hayır / bilmiyorum"))

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

    /// Takip sorusunun yanıtı. "Bilmiyorum" hemen "yanıtlandı" sayılır; "Evet" ve "Hâlâ yardım gerekiyor"
    /// ancak eylem yapılınca ya da sunucu soruyu geçersiz bulunca (öneri bu arada onaylandı, geri alındı…).
    /// Yapılamadıysa (başka eylem sürüyordu, bağlantı yoktu) soru sıranın sonuna döner ve sonra yeniden
    /// sorulur; bu arada işaret bu kişinin haritasında kalır.
    func answerFollowUp(_ answer: FollowUpAnswer) {
        guard let followUp else { return }
        self.followUp = nil
        requestNearbyEvaluation()
        let action: ReportAction
        switch answer {
        case .confirm:
            action = .confirmClosing
        case .dispute:
            action = .dispute
        case .dontKnow:
            watched.markAnswered(followUp.report)
            showNextFollowUp()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await self.perform(action, on: followUp.report)
            let answered: Bool
            switch result {
            case .done, .rejected:
                answered = true
            case .busy, .failed:
                answered = false
            }
            if answered {
                self.watched.markAnswered(followUp.report)
            }
            // Önce sıradaki başka soru; başarısız olan hemen yeniden açılıp hata bildirimini örtmesin.
            self.showNextFollowUp()
            if !answered {
                self.followUpQueue.append(followUp.report)
            }
        }
    }

    /// Sayfa kaydırılıp kapatıldı: "Bilmiyorum" gibi.
    func dismissFollowUp() {
        answerFollowUp(.dontKnow)
    }

    // MARK: Bildirim

    private func show(_ toast: Toast) {
        self.toast = toast
        // Bildirim ekranın altında belirir; VoiceOver onu kendiliğinden okumaz.
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: toast.message)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(toast.duration))
            if self?.toast?.id == toast.id {
                self?.toast = nil
                self?.requestNearbyEvaluation()
            }
        }
    }

    // MARK: "Hâlâ orada mı?"

    /// Yanından geçilen işaret için soru gösterilsin mi? Göz atarken, başka hiçbir şey açık değilken, sıklık
    /// sınırları izin veriyorsa (`NearbyPrompt.gate`), kişi hızlı gitmiyorsa ve 50 m içinde uygun bir işaret varsa
    /// (`NearbyPrompt.candidate`). Sıklık engeli yakında kalkacaksa o an için bir kez yeniden bakılır.
    func evaluateNearbyPrompt(now: Date = Date()) {
        guard environment.nearbyPromptEnabled,
              nearbyPrompt == nil,
              isSceneActive,
              !isLegendShown,
              mode == .browsing,
              selectedReportID == nil,
              followUp == nil,
              pendingReport == nil,
              toast == nil,
              busyAction == nil,
              !locationAlert,
              !isShowingPrompt,
              !needsOnboarding,
              !requiresUpdate,
              !isBanned,
              let userID,
              !isCameraMoving,
              !isZoomedTooFarOut
        else { return }
        let gate = NearbyPrompt.gate(
            log: device.nearbyPromptLog(at: now),
            activeSince: activeSince,
            lastOwnReportAt: lastOwnReportAt,
            at: now
        )
        switch gate {
        case .open:
            break
        case .wait(let until):
            scheduleNearbyRecheck(at: until, now: now)
            return
        }
        guard !location.isMovingFast,
              let fix = location.gateFix(at: now),
              let match = NearbyPrompt.candidate(
                in: activeReports,
                userID: userID,
                fix: fix,
                asked: device.nearbyAskedIDs(at: now),
                at: now
              )
        else { return }
        showNearbyPrompt(match.report, now: now)
    }

    /// Bu turdaki işler bitince bir kez değerlendirilir (ör. işaret konunca önce bildirim gösterilsin).
    private func requestNearbyEvaluation() {
        guard environment.nearbyPromptEnabled, !nearbyEvaluationPending else { return }
        nearbyEvaluationPending = true
        Task { [weak self] in
            guard let self else { return }
            self.nearbyEvaluationPending = false
            self.evaluateNearbyPrompt(now: Date())
        }
    }

    /// Sıklık engelinin kalktığı an (15 dk içindeyse) için tek bir yeniden bakış: açılış payı gibi süreler
    /// konum değişmese de dolunca soru gelsin.
    private func scheduleNearbyRecheck(at date: Date, now: Date) {
        let delay = date.timeIntervalSince(now)
        guard delay <= Self.nearbyRecheckHorizon else { return }
        if let nearbyRecheckAt, abs(nearbyRecheckAt.timeIntervalSince(date)) < 1 { return }
        nearbyRecheck?.cancel()
        nearbyRecheckAt = date
        nearbyRecheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 0) + 0.2))
            guard !Task.isCancelled, let self else { return }
            self.nearbyRecheckAt = nil
            self.evaluateNearbyPrompt(now: Date())
        }
    }

    private func showNearbyPrompt(_ report: Report, now: Date) {
        // Gösterildiği an sorulmuş sayılır: yanıtlanmasa da aynı işaret bir daha sorulmaz.
        device.markNearbyAsked(report.id, at: now)
        device.recordNearbyPrompt(.shown, at: now)
        nearbyPrompt = NearbyQuestion(report: report, step: .presence, shownAt: now, isArmed: false)
        nearbyPromptsShown += 1
        startNearbyStepTimers()
        announceNearbyPrompt()
    }

    /// Düğmeler 0,8 sn sonra açılır; soru 20 sn sonra yanıtsız kalkar. İkisi de her adımda yeniden başlar.
    private func startNearbyStepTimers() {
        nearbyStepToken += 1
        let token = nearbyStepToken
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(NearbyPrompt.armDelay))
            guard let self, self.nearbyStepToken == token, var prompt = self.nearbyPrompt else { return }
            prompt.isArmed = true
            self.nearbyPrompt = prompt
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(NearbyPrompt.visibleDuration))
            guard let self, self.nearbyStepToken == token, let prompt = self.nearbyPrompt else { return }
            self.endNearbyPrompt(NearbyPrompt.result(of: nil, at: prompt.step))
        }
    }

    private func announceNearbyPrompt() {
        guard UIAccessibility.isVoiceOverRunning, let prompt = nearbyPrompt else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: Messages.nearbyAnnouncement(prompt.step, report: prompt.report)
        )
    }

    /// Kişinin şu an yapabildiği eylemler (sorulan işaretin güncel hâliyle).
    func nearbyAvailableActions(for report: Report) -> [ReportAction] {
        guard let userID else { return [] }
        let current = activeReports.first { $0.id == report.id } ?? report
        return ReportLifecycle.availableActions(for: current, userID: userID, at: Date())
    }

    /// Şeritteki düğme (adımdaki sırasıyla). Yazım kartın eylemleriyle aynı yoldan gider (`perform`); dikkat
    /// isteyen ihtiyaçta "Evet" kartı da açar ki "İlgileniyorum" ve "Yol tarifi" bir dokunuş uzakta olsun.
    func answerNearbyPrompt(_ answer: NearbyPrompt.Answer) {
        guard let prompt = nearbyPrompt, prompt.isArmed, busyAction == nil, userID != nil else { return }
        let now = Date()
        let report = activeReports.first { $0.id == prompt.report.id } ?? prompt.report
        let outcome = NearbyPrompt.outcome(
            need: report.need,
            step: prompt.step,
            answer: answer,
            available: nearbyAvailableActions(for: report)
        )
        let result = NearbyPrompt.result(of: answer, at: prompt.step)
        switch outcome {
        case .next(let step):
            nearbyPrompt = NearbyQuestion(report: report, step: step, shownAt: now, isArmed: false)
            startNearbyStepTimers()
            announceNearbyPrompt()
        case .dismiss:
            endNearbyPrompt(result)
        case .perform(let action):
            endNearbyPrompt(.answered)
            if prompt.step == .presence && answer == .first && NearbyPrompt.isCareful(report.need) {
                selectReport(report.id)
                cameraRequest = CameraRequest(target: report.coordinate)
            }
            Task { [weak self] in
                await self?.perform(action, on: report)
            }
        }
    }

    /// Şeridin üst satırına dokunuldu: işaretin kartı açılır (soru kesilmiş sayılır).
    func nearbyPromptTapped() {
        guard let prompt = nearbyPrompt else { return }
        markerTapped(prompt.report.id)
    }

    /// Soru kalkar ve sonucu sayılır (yanıt, yanıtsız ya da kesilme; bkz. `NearbyPrompt.Result`).
    private func endNearbyPrompt(_ result: NearbyPrompt.Result) {
        guard nearbyPrompt != nil else { return }
        nearbyPrompt = nil
        nearbyStepToken += 1
        device.recordNearbyPrompt(result, at: Date())
        requestNearbyEvaluation()
    }

    /// Kişi sorulan işaretten 80 m uzaklaştı: soru yanıtsız kalkar.
    private func checkNearbyPromptRange(now: Date) {
        guard let prompt = nearbyPrompt, let fix = location.gateFix(at: now) else { return }
        let distance = fix.coordinate.distance(to: prompt.report.coordinate)
        if NearbyPrompt.isOutOfRange(distance: distance) {
            endNearbyPrompt(NearbyPrompt.result(of: nil, at: prompt.step))
        }
    }
}
