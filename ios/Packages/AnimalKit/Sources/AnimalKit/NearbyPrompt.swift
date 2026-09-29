import Foundation

/// Yanından geçilen işaret için "Yakınındaki kedi hâlâ orada mı?" sorusu: ne zaman, hangi işaret için
/// sorulacağı ve yanıtın ne yapacağı.
///
/// Saf mantıktır: konumu, işaretleri, cihazdaki kaydı (`Log`, sorulan işaretler) ve saati uygulama verir.
/// Kayıt cihazdan çıkmaz; yalnızca yanıt, kartın eylemleri gibi işarete yazılır.
public enum NearbyPrompt {
    /// Soru, bu kadar metre yakındaki işaret için sorulur ...
    public static let triggerRadius: Double = 50
    /// ... ve kişi bundan uzaklaşınca kalkar (yanıtsız sayılır).
    public static let dismissRadius: Double = 80
    /// Konumun doğruluğu en fazla bu kadar metre ...
    public static let maxAccuracy: Double = 35
    /// ... ve yaşı en fazla bu kadar saniye olmalı.
    public static let maxFixAge: TimeInterval = 60
    /// Bundan hızlı giden kişiye (ör. araçta) sorulmaz (m/s).
    public static let fastSpeed: Double = 2.5
    /// Bundan hızlı okuma ışınlanmadır (simülatör, konum sıçraması); yok sayılır (m/s).
    public static let maxPlausibleSpeed: Double = 60
    /// "Hızlı gidiyor" için iki hızlı okuma en az bu kadar saniye arayla gelmeli.
    public static let fastSampleSpacing: TimeInterval = 2
    /// Uygulamanın tuttuğu son hız okuması sayısı.
    public static let speedSampleCount = 5
    /// Soru bu kadar saniye görünür; her adımda yeniden başlar.
    public static let visibleDuration: TimeInterval = 20
    /// Düğmeler gösterildikten (ya da adım değiştikten) bu kadar saniye sonra açılır: yanlışlıkla basılmasın.
    public static let armDelay: TimeInterval = 0.8
    /// Gösterilen her sorudan sonra bu kadar süre sorulmaz.
    public static let cooldown: TimeInterval = 10 * 60
    /// Kayan `dailyWindow` içinde en fazla bu kadar soru.
    public static let dailyLimit = 5
    public static let dailyWindow: TimeInterval = 24 * 3600
    /// Üst üste bu kadar soru yanıtsız kalırsa ...
    public static let quietAfterUnanswered = 3
    /// ... bu kadar süre sorulmaz.
    public static let quietDuration: TimeInterval = 7 * 24 * 3600
    /// Harita etkin olduktan (açılış, uygulamaya dönüş, kuralların kabulü) bu kadar saniye sonra sorulabilir.
    public static let startupGrace: TimeInterval = 15
    /// Kişi kendi işaretini koyduktan bu kadar saniye sonra sorulabilir.
    public static let afterOwnReportGrace: TimeInterval = 60
    /// Sorulan işaretin kaydı bu kadar süre tutulur: hiçbir işaret bundan uzun yaşamaz.
    public static let askedRetention: TimeInterval = ReportLifecycle.maxAge + 24 * 3600
    /// Bu ihtiyaçlarda "Hayır" hemen "Artık yok" demez; önce bir kez daha sorulur. "Evet"te kart da açılır.
    public static let carefulGoneNeeds: Set<Need> = [.emergency, .injured, .babies]
    /// Bu kadar metreden az farkla eşit uzaklıktaki işaretlerden daha öncelikli ihtiyaç seçilir.
    public static let tieTolerance: Double = 1

    // MARK: Hız

    /// Bir konum okumasındaki hız.
    public struct SpeedSample: Equatable, Sendable {
        public var at: Date
        /// m/s; bilinmiyorsa negatif.
        public var speed: Double
        /// `speedAccuracy`; geçersizse negatif.
        public var accuracy: Double

        public init(at: Date, speed: Double, accuracy: Double) {
            self.at = at
            self.speed = speed
            self.accuracy = accuracy
        }

        /// Hız doğruluğu geçerli ve hız 0...60 m/s (daha hızlısı ışınlanma).
        public var isValid: Bool {
            accuracy >= 0 && (0...NearbyPrompt.maxPlausibleSpeed).contains(speed)
        }

        public var isFast: Bool { isValid && speed > NearbyPrompt.fastSpeed }
    }

    /// Kişi hızlı mı gidiyor? En az 2 sn arayla iki geçerli okuma 2,5 m/s'yi aşmalı ve son geçerli okuma
    /// da hızlı olmalı: kişi durduysa (ör. araçtan indi) soru yeniden sorulabilir.
    public static func isMovingFast(_ samples: [SpeedSample]) -> Bool {
        let valid = samples.filter(\.isValid)
        guard let latest = valid.max(by: { $0.at < $1.at }), latest.isFast else { return false }
        return valid.contains { $0.isFast && latest.at.timeIntervalSince($0.at) >= fastSampleSpacing }
    }

    // MARK: Sıklık

    /// Bir sorunun sonucu, sıklık sayımı için.
    public enum Result: Equatable, Sendable {
        /// Soru gösterildi.
        case shown
        /// Evet, Hayır, "Emin değilim" ya da bir yazım. Yanıtsız serisini sıfırlar.
        case answered
        /// "Bilmiyorum", 20 sn dolması ya da 80 m'den uzaklaşma.
        case unanswered
        /// Kesildi (işaretleme, kart, takip sorusu, uygulama arka plana geçti, harita elle kaydırıldı,
        /// işaret artık beklemiyor, meşgul): sayılmaz.
        case interrupted
    }

    /// Cihazdaki soru kaydı: son 24 saatte gösterilen sorular ve yanıtsız serisi.
    public struct Log: Codable, Equatable, Sendable {
        /// Son `dailyWindow` içinde gösterilen soruların anları.
        public var shownAt: [Date]
        /// Üst üste yanıtsız kalan soru sayısı.
        public var unansweredStreak: Int
        /// Bu ana kadar hiç sorulmaz.
        public var quietUntil: Date?

        public init(shownAt: [Date] = [], unansweredStreak: Int = 0, quietUntil: Date? = nil) {
            self.shownAt = shownAt
            self.unansweredStreak = unansweredStreak
            self.quietUntil = quietUntil
        }

        public mutating func record(_ result: Result, at now: Date) {
            switch result {
            case .shown:
                shownAt.append(now)
            case .answered:
                unansweredStreak = 0
            case .unanswered:
                unansweredStreak += 1
                if unansweredStreak >= NearbyPrompt.quietAfterUnanswered {
                    quietUntil = now.addingTimeInterval(NearbyPrompt.quietDuration)
                    unansweredStreak = 0
                }
            case .interrupted:
                break
            }
            self = pruned(at: now)
        }

        /// 24 saatten eski gösterimler ve geçmiş sessizlik atılır.
        public func pruned(at now: Date) -> Log {
            var log = self
            log.shownAt = shownAt.filter { now.timeIntervalSince($0) < NearbyPrompt.dailyWindow }
            if let quietUntil, quietUntil <= now { log.quietUntil = nil }
            return log
        }
    }

    /// Şimdi sorulabilir mi, yoksa en erken ne zaman?
    public enum Gate: Equatable, Sendable {
        case open
        case wait(until: Date)
    }

    /// Sessizlik, açılış payı, kendi işaretinden sonraki pay, 10 dk ara ve günlük sınır. Birden çok engel
    /// varsa hepsinin kalktığı an döner; uygulama o an için bir kez yeniden bakabilir.
    ///
    /// `activeSince`: haritanın etkin olduğu an. `lastOwnReportAt`: kişinin son kendi işareti.
    public static func gate(log: Log, activeSince: Date, lastOwnReportAt: Date?, at now: Date) -> Gate {
        let recent = log.pruned(at: now).shownAt.sorted()
        var until: [Date] = []
        if let quietUntil = log.quietUntil { until.append(quietUntil) }
        until.append(activeSince.addingTimeInterval(startupGrace))
        if let lastOwnReportAt { until.append(lastOwnReportAt.addingTimeInterval(afterOwnReportGrace)) }
        if let last = recent.last { until.append(last.addingTimeInterval(cooldown)) }
        if recent.count >= dailyLimit {
            // Pencereden yeterince gösterim düşünce sınırın altına inilir.
            until.append(recent[recent.count - dailyLimit].addingTimeInterval(dailyWindow))
        }
        guard let latest = until.max(), latest > now else { return .open }
        return .wait(until: latest)
    }

    /// Sorulan işaretler kaydından `askedRetention`dan eski olanlar atılır.
    public static func prunedAsked(_ asked: [String: Date], at now: Date) -> [String: Date] {
        asked.filter { now.timeIntervalSince($0.value) < askedRetention }
    }

    // MARK: Hangi işaret

    /// Okuma soru için yeterince iyi mi: doğruluk 0...35 m ve yaşı en fazla 60 sn.
    public static func isUsable(_ fix: LocationFix?, at now: Date) -> Bool {
        guard let fix else { return false }
        return fix.coordinate.latitude.isFinite
            && fix.coordinate.longitude.isFinite
            && (0...maxAccuracy).contains(fix.horizontalAccuracy)
            && fix.age(at: now) <= maxFixAge
    }

    /// Kişi soru gösterilen işaretten uzaklaştı mı (80 m)?
    public static func isOutOfRange(distance: Double) -> Bool {
        !(distance <= dismissRadius)
    }

    /// Sorulacak işaret: 50 m içindeki en yakın uygun işaret; 1 m'den az farkla eşitse daha öncelikli ihtiyaç.
    ///
    /// Uygun işaret: yardım bekliyor ya da başkası ilgileniyor ("… dendi" olanlar şimdilik değil), kişinin
    /// kendi işareti değil, kişi daha önce görmedi, "Artık yok" demedi, daha önce sorulmadı ve kişi
    /// "Hâlâ orada" diyebiliyor.
    public static func candidate(
        in reports: [Report],
        userID: String,
        fix: LocationFix,
        asked: Set<String>,
        at now: Date
    ) -> (report: Report, distance: Double)? {
        guard isUsable(fix, at: now) else { return nil }
        var matches: [(report: Report, distance: Double)] = []
        for report in reports {
            guard report.isWaiting(at: now),
                  report.reporterID != userID,
                  !report.seenBy.contains(userID),
                  !report.goneReports.contains(userID),
                  !asked.contains(report.id)
            else { continue }
            switch report.phase(for: userID, at: now) {
            case .waiting, .helpedByOther:
                break
            case .helpedByMe, .closing, .closed:
                continue
            }
            guard ReportLifecycle.availableActions(for: report, userID: userID, at: now)
                .contains(.confirmStillThere)
            else { continue }
            let distance = fix.coordinate.distance(to: report.coordinate)
            guard distance <= triggerRadius else { continue }
            matches.append((report: report, distance: distance))
        }
        guard let nearest = matches.map({ $0.distance }).min() else { return nil }
        let tied = matches.filter { $0.distance <= nearest + tieTolerance }
        // Önce öncelik, sonra uzaklık, en son kimlik: sonuç her seferinde aynı olsun.
        return tied.min { lhs, rhs in
            if lhs.report.need.priority != rhs.report.need.priority {
                return lhs.report.need.priority > rhs.report.need.priority
            }
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            return lhs.report.id < rhs.report.id
        }
    }

    // MARK: Yanıtlar

    /// Sorunun adımı.
    public enum Step: Equatable, Sendable {
        /// "Yakınındaki kedi hâlâ orada mı?": Evet · Hayır · Bilmiyorum
        case presence
        /// Mama: "Yardıma ihtiyacı var mı?": Hâlâ yardım lazım · Yardım gerekmiyor · Bilmiyorum
        case needsHelp
        /// Dikkat isteyen ihtiyaç: "Artık orada değil mi?": Artık yok · Emin değilim
        case confirmGone
    }

    /// Düğmenin adımdaki yeri (yukarıdaki sırayla). Gizlenen düğme yer değiştirmez:
    /// "Bilmiyorum" her zaman `third`dür.
    public enum Answer: Equatable, Sendable {
        case first
        case second
        case third
    }

    /// Yanıtın sonucu.
    public enum Outcome: Equatable, Sendable {
        /// Bu eylemi uygula (kartın eylemi gibi; sonuç bildirimi de aynı).
        case perform(ReportAction)
        /// Sonraki adımı sor.
        case next(Step)
        /// Hiçbir şey yazmadan kapat.
        case dismiss
    }

    /// Bu ihtiyaçta "Hayır" önce bir kez daha sorulur ve "Evet"te kart da açılır.
    public static func isCareful(_ need: Need) -> Bool {
        carefulGoneNeeds.contains(need)
    }

    /// Yanıt ne yapar? `available`: kişinin şu anki eylemleri (`ReportLifecycle.availableActions`);
    /// açık olmayan eylem hiç istenmez, o zaman soru yazmadan kapanır.
    ///
    /// - presence + Evet: mamada "Yardım gerekmiyor" açıksa `needsHelp`; yoksa "Hâlâ orada".
    /// - presence + Hayır: "Artık yok" açıksa dikkat isteyen ihtiyaçta `confirmGone`, diğerlerinde
    ///   "Artık yok" (tek oy; tek kişi işareti kapatmaz).
    /// - needsHelp: "Hâlâ yardım lazım" → "Hâlâ orada"; "Yardım gerekmiyor" → `reportUnneeded`.
    /// - confirmGone: "Artık yok" → `reportGone`; "Emin değilim" → kapat.
    /// - Bilmiyorum: kapat.
    public static func outcome(need: Need, step: Step, answer: Answer, available: [ReportAction]) -> Outcome {
        func performIfAvailable(_ action: ReportAction) -> Outcome {
            available.contains(action) ? .perform(action) : .dismiss
        }
        switch step {
        case .presence:
            switch answer {
            case .first:
                if need == .food && available.contains(.reportUnneeded) { return .next(.needsHelp) }
                return performIfAvailable(.confirmStillThere)
            case .second:
                guard available.contains(.reportGone) else { return .dismiss }
                return isCareful(need) ? .next(.confirmGone) : .perform(.reportGone)
            case .third:
                return .dismiss
            }
        case .needsHelp:
            switch answer {
            case .first:
                return performIfAvailable(.confirmStillThere)
            case .second:
                return performIfAvailable(.reportUnneeded)
            case .third:
                return .dismiss
            }
        case .confirmGone:
            switch answer {
            case .first:
                return performIfAvailable(.reportGone)
            case .second, .third:
                return .dismiss
            }
        }
    }

    /// Sona eren sorunun sayımı. `answer`: son basılan düğme; süre dolduysa ya da kişi uzaklaştıysa `nil`.
    /// İlk adımda Evet ya da Hayır diyen kişi yanıtlamış sayılır: sonraki adımda "Bilmiyorum" dese de.
    public static func result(of answer: Answer?, at step: Step) -> Result {
        guard step == .presence else { return .answered }
        switch answer {
        case .some(.first), .some(.second):
            return .answered
        case .some(.third), .none:
            return .unanswered
        }
    }
}
