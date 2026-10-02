import Foundation

/// Açılışta harita, kişinin konumu bulunana kadar varsayılan şehir merkezini gösterir. O yerin işaretlerini yüklemek
/// gereksizdir: konum birazdan gelir ve harita oraya gider. Bu kapı, ilk aboneliğin ne zaman açılacağına karar verir.
/// Saf mantıktır: konum erişimini, haritanın durumunu ve saati uygulama verir.
public enum InitialAreaGate {
    /// İzin var ama ilk konum okuması gelmediyse bu kadar saniye beklenir; sonra görünen alana abone olunur.
    public static let fixTimeout: TimeInterval = 8

    /// Kapının kararı.
    public enum Verdict: Equatable, Sendable {
        /// İlk alan belli: görünen alana abone olunur.
        case open
        /// İzin sorusu ekranda ve yanıtlanmadı: yanıtlanana kadar süresiz beklenir.
        case waitingForPermission
        /// İzin var, ilk okuma bekleniyor: `remaining` saniye sonra görünen alana abone olunur.
        case waitingForFix(remaining: TimeInterval)

        public var isOpen: Bool { self == .open }
    }

    /// Kapı şu koşullardan biri sağlanınca açılır; hiçbiri yoksa beklenir:
    ///
    /// 1. ilk konum okuması kamerayı kişiye götürdü (`centeredOnUser`)
    /// 2. kişi haritayı kendisi oynattı (`movedByPerson`); izin sorusu sürerken de
    /// 3. başka bir kamera isteği haritayı varsayılan şehir merkezinden başka yere götürdü (`redirected`): kart vb.
    /// 4. konum erişimi yok (`denied`: reddedildi ya da kısıtlı): kişi varsayılan şehir merkeziyle de harita görür
    /// 5. izin var (`approximate`, `full`) ama ilk okuma `fixTimeout` içinde gelmedi
    ///
    /// İzin henüz sorulmadıysa (`notDetermined`) yalnızca 1–3 açar; soru ekrandayken süre sayılmaz.
    ///
    /// `accessAvailableSince`: erişimin kullanılabilir olduğu an (izin verildi ya da uygulama zaten izinliydi);
    /// `nil` ise şimdi sayılır. Saat geriye giderse bekleme baştan başlar.
    public static func verdict(
        centeredOnUser: Bool,
        movedByPerson: Bool,
        redirected: Bool,
        access: LocationAccess,
        accessAvailableSince: Date?,
        at now: Date
    ) -> Verdict {
        if centeredOnUser || movedByPerson || redirected {
            return .open
        }
        switch access {
        case .denied:
            return .open
        case .notDetermined:
            return .waitingForPermission
        case .approximate, .full:
            let waited: TimeInterval = accessAvailableSince.map { max(now.timeIntervalSince($0), 0) } ?? 0
            guard waited < fixTimeout else { return .open }
            return .waitingForFix(remaining: fixTimeout - waited)
        }
    }
}
