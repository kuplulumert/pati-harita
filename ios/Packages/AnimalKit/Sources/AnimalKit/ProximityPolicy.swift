import Foundation

/// Uzaktan eylem kapısı: "Çözüldü" ve hayvanı gördüğünü söyleyen eylemler yalnızca hayvanın yanındaki ya da
/// yakın zamanda yanına uğramış kişiye açıktır.
///
/// - Yakın: kullanılabilir okuma (`PlacementGate.isUsable`) iğneye izin verilen çevrede
///   (`PlacementGate.allowedRadius`: 150 m + doğruluk kadar, en fazla 75 m). Dokunulduğu anki okumayla ölçülür.
/// - Uğradı: cihaz bu işaretin yakınında en son `lastNearAt` anında bulundu (kayıt cihazda, 24 sa tutulur).
/// - "Çözüldü": yakınken ya da son 12 saatte uğradıysa (hayvanı veterinere götüren orada da diyebilsin).
/// - "Hâlâ orada", "Artık yok", "Yardım gerekmiyor", "Hâlâ yardım gerekiyor": yakınken ya da son 1 saatte
///   uğradıysa. İşareti koyan "Hâlâ yardım gerekiyor"u her yerden diyebilir: itiraz hiçbir şeyi gizlemez.
/// - Kapısız: İlgileniyorum, Vazgeç, "Evet, çözüldü", Geri al, Düzenle (yeni konumu ayrıca denetlenir), bildir,
///   gizle, e-posta, Yol tarifi, Konumu paylaş.
///
/// Saf mantıktır ve yalnızca istemcide uygulanır: Firestore kuralları konumu denetleyemez. Konum cihazdan çıkmaz.
public enum ProximityPolicy {
    /// "Çözüldü": hayvanın yanından ayrıldıktan sonra bu kadar süre daha açık.
    public static let resolveWindow: TimeInterval = 12 * 3600
    /// Hayvanı gördüğünü söyleyen eylemler: yanından ayrıldıktan sonra bu kadar süre daha açık.
    public static let observationWindow: TimeInterval = 3600
    /// Uğranan işaretlerin kaydı bu kadar süre tutulur.
    public static let lastNearRetention: TimeInterval = 24 * 3600

    /// Kapısı olan eylemler (işareti koyanın itirazı dışında; bkz. `isGated`).
    public static let gatedActions: Set<ReportAction> = [
        .resolve, .confirmStillThere, .reportGone, .reportUnneeded, .dispute,
    ]

    /// Kişinin işarete göre yeri: şimdi yakında mı ve en son ne zaman yakınındaydı.
    public struct Presence: Equatable, Sendable {
        /// Dokunulduğu anki okumayla yakın (`ProximityPolicy.isNear`).
        public var isNear: Bool
        /// Cihazın bu işaretin yakınında en son bulunduğu an; kayıt yoksa `nil`.
        public var lastNearAt: Date?

        public init(isNear: Bool, lastNearAt: Date?) {
            self.isNear = isNear
            self.lastNearAt = lastNearAt
        }

        /// Hayvanın yanında: her eylem açık (önizlemeler için de).
        public static let near = Presence(isNear: true, lastNearAt: nil)
        /// Uzakta ve hiç uğramadı.
        public static let away = Presence(isNear: false, lastNearAt: nil)
    }

    // MARK: Hangi eylem

    /// Eylemin "uğradı" penceresi; kapısız eylemde `nil`.
    public static func window(for action: ReportAction) -> TimeInterval? {
        switch action {
        case .resolve:
            return resolveWindow
        case .confirmStillThere, .reportGone, .reportUnneeded, .dispute:
            return observationWindow
        case .claim, .release, .confirmClosing, .undoClosing, .expire:
            return nil
        }
    }

    /// Bu kişi için eylemin kapısı var mı? İşareti koyanın "Hâlâ yardım gerekiyor"u kapısızdır.
    public static func isGated(_ action: ReportAction, on report: Report, userID: String?) -> Bool {
        if action == .dispute, let userID, report.reporterID == userID { return false }
        return window(for: action) != nil
    }

    /// Eylem yakınlık açısından açık mı? Kapısız eylem hep açık; kapılı eylem yakınken ya da eylemin
    /// penceresi içinde uğradıysa. Eylemin kişiye açık olup olmadığına (`ReportLifecycle.availableActions`) bakmaz.
    public static func allowed(
        action: ReportAction,
        report: Report,
        userID: String?,
        isNear: Bool,
        lastNearAt: Date?,
        now: Date
    ) -> Bool {
        guard isGated(action, on: report, userID: userID), let limit = window(for: action) else { return true }
        return isNear || visited(lastNearAt: lastNearAt, within: limit, at: now)
    }

    /// Cihaz son `window` saniyede işaretin yakınında bulundu mu? Gelecekteki kayıt (saat geri alındı) sayılmaz.
    public static func visited(lastNearAt: Date?, within window: TimeInterval, at now: Date) -> Bool {
        guard let lastNearAt else { return false }
        return (0...window).contains(now.timeIntervalSince(lastNearAt))
    }

    // MARK: Yakınlık

    /// Nokta, okumanın izin verilen çevresinde mi? Okuma kullanılabilir olmalı (doğruluk 0...100 m, yaşı en fazla
    /// 120 sn); `rejectsSimulated` iken taklit konum yakın sayılmaz (işaretleme kapısındaki gibi).
    public static func isNear(_ point: Coordinate, fix: LocationFix?, rejectsSimulated: Bool, at now: Date) -> Bool {
        guard let fix = usableFix(fix, rejectsSimulated: rejectsSimulated, at: now) else { return false }
        return PlacementGate.isWithinAllowedRadius(point, of: fix)
    }

    private static func usableFix(_ fix: LocationFix?, rejectsSimulated: Bool, at now: Date) -> LocationFix? {
        guard PlacementGate.isUsable(fix, at: now), let fix else { return nil }
        return rejectsSimulated && fix.isSimulatedBySoftware ? nil : fix
    }

    // MARK: Uğranan işaretler

    /// Okumanın yakınındaki her işaret için uğrama anını (okumanın anı, en fazla `now`) yazar ve eski kayıtları atar
    /// (`prunedLastNear`). Okuma yakın değilse kayıtlar yalnızca budanır. Uygulama her kabul ettiği okumada ve
    /// kart açılırken çağırır; sonuç değişmediyse yazmasına gerek yok.
    public static func updatedLastNear(
        _ lastNear: [String: Date],
        reports: [Report],
        fix: LocationFix?,
        rejectsSimulated: Bool,
        at now: Date
    ) -> [String: Date] {
        var updated = prunedLastNear(lastNear, at: now)
        guard let fix = usableFix(fix, rejectsSimulated: rejectsSimulated, at: now) else { return updated }
        let stamp = min(fix.timestamp, now)
        for report in reports where PlacementGate.isWithinAllowedRadius(report.coordinate, of: fix) {
            // Gelecekteki kayıt (saat geri alındı) yenisiyle değişir; yoksa yalnızca ileri gider.
            if let previous = updated[report.id], previous <= now, previous >= stamp { continue }
            updated[report.id] = stamp
        }
        return updated
    }

    /// `lastNearRetention`dan eski kayıtlar atılır; saat ileri alınmışken yazılan kayıtlar da sonsuza kalmasın.
    public static func prunedLastNear(_ lastNear: [String: Date], at now: Date) -> [String: Date] {
        lastNear.filter { abs(now.timeIntervalSince($0.value)) < lastNearRetention }
    }
}
