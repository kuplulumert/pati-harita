import AnimalKit
import Foundation

/// Saate, sayıya ve kişiye göre değişen Türkçe metinler: kart, bildirimler, günlük sınır, takip sorusu,
/// "Yardıma ihtiyacı var mı?" kontrolü, nereye işaret konabileceği, "Hâlâ orada mı?", güvenlik.
enum Messages {
    // MARK: Kart

    /// Kartın başlığı, ihtiyaç ve tür birlikte: "Yaralı / hasta kedi", "Acil yardım gereken köpek",
    /// "Yavru kediler tehlikede". Haritadaki işaretin etiketi ("Yaralı / hasta, Kedi") değişmez.
    static func cardTitle(_ report: Report) -> String {
        let noun = report.species.noun
        switch report.need {
        case .food, .injured, .shelter:
            return "\(report.need.title) \(noun)"
        case .emergency:
            return "Acil yardım gereken \(noun)"
        case .vet:
            return "Veteriner desteği gereken \(noun)"
        case .babies:
            return "Yavru \(report.species.pluralNoun) tehlikede"
        }
    }

    /// Kartın bilgi satırı: "140 m · az önce görüldü · 4 kişi bildirdi". Sığmazsa `twoLines`: sayı alt satırda.
    /// Biri "Hâlâ orada" dediyse "görüldü", yoksa "işaretlendi"; tek kişi bildirdiyse sayı yok, konum yoksa uzaklık yok.
    static func cardMeta(_ report: Report, distance: Double?, now: Date) -> (oneLine: String, twoLines: String) {
        var parts: [String] = []
        if let distance {
            parts.append(Formatting.distance(meters: distance))
        }
        if report.lastSeenAt > report.createdAt {
            parts.append("\(Formatting.timeAgo(report.lastSeenAt, now: now)) görüldü")
        } else {
            parts.append("\(Formatting.timeAgo(report.createdAt, now: now)) işaretlendi")
        }
        let first = parts.joined(separator: " · ")
        guard let seen = Formatting.seenCount(report.seenCount) else { return (first, first) }
        return ("\(first) · \(seen)", "\(first)\n\(seen)")
    }

    // MARK: Düğmeler

    /// Eylemin bu kişi için başlığı: işareti koyanın başkasının sahipliğini kaldırması "İlgilenen gelmedi",
    /// ilgilenenin bırakması "İlgilenmeyi bırak" (menüde yalın "Vazgeç" iptal gibi okunur), "Artık yok dendi"yi
    /// onaylamak "Evet, artık yok"; mama işaretinde "Hâlâ yardım lazım" ve "Yardım gerekmiyor"; diğerleri
    /// `ReportAction.title`.
    static func title(for action: ReportAction, on report: Report, userID: String?, now: Date) -> String {
        switch action {
        case .release:
            let isClaimer = report.activeClaim(at: now)?.userID == userID
            return report.reporterID == userID && !isClaimer ? "İlgilenen gelmedi" : "İlgilenmeyi bırak"
        case .confirmClosing:
            return confirmClosingTitle(report.closing?.reason ?? .resolved)
        case .confirmStillThere:
            // Hafif ihtiyaçta hayvanın orada olması yetmez; ağır ihtiyaçta orada olması ihtiyacın kendisidir.
            return report.need.allowsUnneeded ? "Hâlâ yardım lazım" : action.title
        case .reportUnneeded:
            // Ne görüldüğü alt satırda: "Hayvan orada ama iyi görünüyor" (`menuSubtitle`).
            return "Yardım gerekmiyor"
        case .claim, .resolve, .reportGone, .dispute, .undoClosing, .expire:
            return action.title
        }
    }

    /// Kartın "⋯ Diğer" menüsünde eylemin alt satırı; yoksa `nil`. İşareti koyan tek tanıksa kapatan eylemler
    /// "işaret hemen kalkar" der (geri alınamaz); daha önce itiraz edilen işarette "Çözüldü" bunu hatırlatır.
    static func menuSubtitle(for action: ReportAction, on report: Report, userID: String?) -> String? {
        let alone = userID.map { ReportLifecycle.reporterAlone(report, userID: $0) } ?? false
        let closesNow = " · işaret hemen kalkar"
        switch action {
        case .reportUnneeded:
            return "Hayvan orada ama iyi görünüyor" + (alone ? closesNow : "")
        case .reportGone:
            return "Hayvan artık orada değil" + (alone ? closesNow : "")
        case .resolve:
            if alone { return "İşaret hemen kalkar" }
            return report.disputed.isEmpty ? nil : "Daha önce itiraz edildi"
        case .release:
            return "İşaret yeniden yardım bekler"
        case .claim, .confirmStillThere, .dispute, .confirmClosing, .undoClosing, .expire:
            return nil
        }
    }

    static func confirmClosingTitle(_ reason: ClosedReason) -> String {
        switch reason {
        case .gone: "Evet, artık yok"
        case .unneeded: "Evet, ihtiyacı yoktu"
        case .resolved, .expired: "Evet, çözüldü"
        }
    }

    // MARK: Eylem bildirimleri

    /// Öneri başlatmayan eylemlerden sonra (öneri başlatanlar için `closerToast`).
    static func actionDone(
        _ action: ReportAction,
        outcome: ActionOutcome,
        addsSeen: Bool,
        userID: String,
        now: Date
    ) -> String {
        let report = outcome.report
        switch action {
        case .claim:
            let thanks = "Teşekkürler! İşaret \(Int(ReportLifecycle.claimDuration / 3600)) saat boyunca sende."
            return goTogetherNeeds.contains(report.need) ? "\(thanks) \(goTogether)" : thanks
        case .release:
            return "İşaret yeniden yardım bekliyor."
        case .resolve:
            return "Harika! İşaret haritadan kaldırıldı."
        case .confirmClosing:
            return report.closedReason == .unneeded
                ? "Teşekkürler! İşaret haritadan kaldırıldı."
                : "Harika! İşaret haritadan kaldırıldı."
        case .reportUnneeded:
            // Öneri başlattıysa buraya gelinmez; işareti koyan tek başınaydı ve işaret hemen kalktı.
            return "\(unneededThanks) İşaret haritadan kaldırıldı."
        case .confirmStillThere:
            return addsSeen
                ? "Teşekkürler! Bu hayvanı artık \(report.seenCount) kişi bildirdi."
                : "Teşekkürler, işaret güncellendi."
        case .reportGone:
            // Oy öneri başlattıysa buraya gelinmez ("… dendi" bildirimi `closerToast`ta).
            if report.status == .closed { return "Teşekkürler! İşaret haritadan kaldırıldı." }
            if let claim = report.activeClaim(at: now), claim.userID != userID {
                // Oylar başkasının canlı sahipliği üstüne öneri başlatamaz; yalnızca sayılır.
                return "Teşekkürler, kaydedildi. Biri bu hayvanla ilgilendiği için işaret yerinde kalıyor."
            }
            if report.goneReports.count >= ReportLifecycle.goneThreshold {
                // Eşik aşıldı ama bu kişi öneremiyor (ör. önceki kapatma önerisine itiraz edildi).
                return "Teşekkürler, kaydedildi."
            }
            return "Teşekkürler, kaydedildi. \(ReportLifecycle.goneThreshold) kişi 'Artık yok' deyince haritada 'Artık yok dendi' olarak görünür."
        case .dispute:
            return "Teşekkürler, işaret yeniden yardım bekliyor."
        case .undoClosing:
            // Geçerli sahiplik "Geri al"da kalır (kurallardaki isUndo).
            guard let claim = report.activeClaim(at: now) else {
                return "Geri alındı; işaret yeniden yardım bekliyor."
            }
            return claim.userID == userID
                ? "Geri alındı; bu hayvanla hâlâ sen ilgileniyorsun."
                : "Geri alındı; biri hâlâ bu hayvanla ilgileniyor."
        case .expire:
            return "Bu işaretin süresi doldu."
        }
    }

    /// "Yardım gerekmiyor" (hayvan orada ama iyi görünüyor) diyene.
    static let unneededThanks = "Teşekkürler! Harita gerçekten yardım bekleyenler için daha temiz."

    /// "Çözüldü" / "Artık yok" / "Yardım gerekmiyor" diyene: işaretin başkalarının haritasında ne olacağı
    /// (kanıtlılık ve moda göre). Hepsi bir teşekkürle başlar.
    static func closerToast(
        for report: Report,
        by userID: String,
        credibility: CloseCredibility,
        mode: ClosingMode,
        now: Date
    ) -> String {
        let reason = report.closing?.reason ?? .resolved
        let thanks: String
        switch reason {
        case .gone: thanks = "Teşekkürler! Bildirimin kaydedildi."
        case .unneeded: thanks = unneededThanks
        case .resolved, .expired: thanks = "Teşekkürler! Yardımın kaydedildi."
        }
        // İşareti koyan kapattıysa onu hayvanı gören başka biri onaylar.
        let confirmer = report.reporterID == userID ? "hayvanı gören başka biri" : "işareti koyan kişi"
        let unverified = "Başkalarına 'doğrulanmadı' olarak görünecek; \(confirmer) onaylayınca kalkacak."

        switch credibility {
        case .credible:
            switch mode {
            case .demote:
                let closingAt = report.closing?.at ?? now
                let leavesAt = ClosingDisplay.demoteAt(closingAt: closingAt, need: report.need)
                let daytime = TimeInterval(report.need.demoteMinutes * 60)
                // Gece saatleri sayılmaz: süre gece yarısını aşıyorsa kalkış saati söylenir.
                if leavesAt.timeIntervalSince(closingAt) <= daytime + 60 {
                    return "\(thanks) İşaret yaklaşık \(report.need.demoteMinutes / 60) saat sonra başkalarının haritasından da kalkacak."
                }
                return "\(thanks) İşaret \(clockPhrase(leavesAt, now: now)) civarında başkalarının haritasından da kalkacak."
            case .label:
                return "\(thanks) İşaret başkalarına '\(saidLabel(reason))' olarak görünecek; \(confirmer) onaylayınca ya da süresi dolunca kalkacak."
            case .strict:
                return "\(thanks) \(unverified)"
            }
        case .newAccount:
            return "\(thanks) İlk gününde '\(verb(reason))' dediğin işaretler başkalarına 'doğrulanmadı' olarak görünür; \(confirmer) onaylayınca kalkar."
        case .budgetUsed:
            return "\(thanks) Son 24 saatte çok işaret kapattın; bu işaret başkalarına 'doğrulanmadı' olarak görünecek, \(confirmer) onaylayınca kalkacak."
        case .disputed:
            return "\(thanks) Bu işarete daha önce itiraz edildiği için başkalarına 'doğrulanmadı' olarak görünecek."
        case .noRecord:
            return "\(thanks) \(unverified)"
        }
    }

    // MARK: Yeni işaret hakkı

    /// Hak bitti: "Son 24 saatte 10 işaret koydun. Yeni işaret hakkın saat 14.20'de açılır. …"
    static func createLimit(limit: Int, nextCreateAt: Date?, now: Date) -> String {
        var sentences = ["Son 24 saatte \(limit) işaret koydun."]
        if let nextCreateAt {
            sentences.append("Yeni işaret hakkın \(atClock(nextCreateAt, now: now)) açılır.")
        }
        sentences.append("Yakındaki bir işaret aynı hayvansa 'Ben de gördüm' diyebilirsin.")
        return sentences.joined(separator: " ")
    }

    /// Çevrimdışı konan işaret sonradan gönderilince sunucu günlük sınır yüzünden reddetti.
    static let createRejected = "Bu işaret günlük sınır nedeniyle kaydedilemedi."

    /// Çevrimdışı konan işaret ancak ~24 saat sonra gönderilebildi; kurallar bu kadar eskisini kabul etmez.
    static let createTooLate = "İşaret çok geç gönderilebildiği için kaydedilemedi."

    /// Seçim panelinde: hak azaldıysa "3 yeni işaret hakkın kaldı", bittiyse ne zaman açılacağı; yoksa `nil`.
    static func createAllowance(_ record: UserRecord, lowThreshold: Int, now: Date) -> String? {
        let remaining = Budget.remainingCreates(record, at: now)
        if remaining == 0 {
            return Budget.nextCreateAt(record, at: now).map { "Yeni işaret hakkın \(atClock($0, now: now)) açılır" }
        }
        return remaining <= lowThreshold ? "\(remaining) yeni işaret hakkın kaldı" : nil
    }

    // MARK: "… dendi" soruları

    /// 40 m önerisi bir "… dendi" işaretine denk geldi: "Burada 2 sa önce bir kedi için 'Çözüldü' dendi. …"
    static func duplicateClosingPrompt(_ report: Report, now: Date) -> String? {
        guard let closing = report.closing else { return nil }
        let ago = Formatting.timeAgo(closing.at, now: now)
        return "Burada \(ago) bir \(report.species.noun) için '\(verb(closing))' dendi. Aynı hayvan mı, hâlâ yardım gerekiyor mu?"
    }

    /// A7 takip sorusu. `leavesAt`: işaretin başkalarının haritasından kalkacağı an (biliniyorsa).
    static func followUp(_ report: Report, viewer: String, leavesAt: Date?, now: Date) -> String {
        guard let closing = report.closing else { return "" }
        let animal = "\(report.species.noun) (\(report.need.title))"
        let ago = Formatting.timeAgo(closing.at, now: now)
        let said = "'\(verb(closing))'"
        // Tanınmayan nedenli öneri bu sürümde onaylanamaz; yalnızca itiraz sorulur.
        let question = closing.unrecognizedReason == nil ? "Doğru mu?" : "Hâlâ yardım gerekiyor mu?"
        var text: String
        if report.reporterID == viewer {
            // "Koyduğun Aç ve zayıf kedi işareti için 20 dk önce 'Yardım gerekmiyor' dendi. Doğru mu?"
            text = "Koyduğun \(report.need.title) \(report.species.noun) işareti için \(ago) \(said) dendi. \(question)"
        } else if closing.userID == report.reporterID && report.seenBy.contains(viewer) {
            // İşareti koyanın önerisini hayvanı gören başka biri onaylayabilir.
            text = "İşareti koyan, gördüğün \(animal) için \(ago) \(said) dedi. \(question)"
        } else if report.seenBy.contains(viewer) {
            text = "Gördüğün \(animal) için \(ago) \(said) dendi. Hâlâ yardım gerekiyor mu?"
        } else {
            text = "İlgilendiğin \(animal) için \(ago) \(said) dendi. Hâlâ yardım gerekiyor mu?"
        }
        if let leavesAt, leavesAt > now {
            text += " (Haritadan kalkış: \(Formatting.clock(leavesAt, now: now)))"
        }
        return text
    }

    // MARK: Üst etiket

    /// Ağır ihtiyaçlar önce, hafifler (mama) ayrı: "3 hayvan yardım bekliyor · 5 düşük öncelikli",
    /// "Yakında acil ihtiyaç yok · 5 düşük öncelikli", "Yakında yardım bekleyen yok".
    static func waitingHeadline(_ counts: WaitingCounts) -> String {
        let light = counts.light > 0 ? " · \(counts.light) düşük öncelikli" : ""
        if counts.serious > 0 {
            return "\(counts.serious) hayvan yardım bekliyor\(light)"
        }
        return counts.light > 0 ? "Yakında acil ihtiyaç yok\(light)" : "Yakında yardım bekleyen yok"
    }

    /// Engellenen kimlik: bildirimde ve üst etikette kalıcı. Adres varsa itiraz için eklenir.
    static var banned: String {
        let text = "Bu kimlikle işaret koyma kapatıldı."
        guard !AppInfo.supportEmail.isEmpty else { return text }
        return "\(text) Hata olduğunu düşünüyorsan: \(AppInfo.supportEmail)"
    }

    // MARK: Yeni işaretten önceki sorular

    static let gentleCheckTitle = "Yardıma ihtiyacı var mı?"
    static let gentleCheckConfirmTitle = "Yardıma ihtiyacı var, işaretle"
    static let gentleCheckCancelTitle = "Sağlıklı görünüyor, vazgeç"
    static let gentleCheckCancelled = "Teşekkürler! Harita yalnızca yardım bekleyen hayvanlar için; böylece gönüllüler boşuna yola çıkmaz."

    /// "Yardıma ihtiyacı var mı?" metni; `recentCount` verilirse "Son 24 saatte N işaret koydun." ile başlar.
    static func gentleCheck(need: Need, recentCount: Int?) -> String {
        let text: String
        switch need {
        case .food:
            text = "Sokakta yaşayan, beslenen ve sağlıklı görünen hayvanlar işaretlenmez. Çok zayıfsa, günlerdir beslenmiyorsa ya da su bulamıyorsa işaretle."
        case .shelter:
            text = "Sokakta yaşayan sağlıklı hayvanlar için değil. Terk edilmiş, çok yaşlı ya da engelli bir hayvansa işaretle."
        case .emergency, .injured, .babies, .vet:
            text = "Yalnızca yardıma ihtiyacı varsa işaretle. Sağlıklı sokak hayvanları işaretlenmez."
        }
        guard let recentCount else { return text }
        return "Son 24 saatte \(recentCount) işaret koydun. \(text)"
    }

    // MARK: Nereye işaret konabilir

    /// Kurallar sayfasında ve açıklama ekranında aynı cümle.
    static let placementRule = "Hayvanın yanındayken işaretle: işaret yalnızca bulunduğun yerin çevresine konabilir. Güvenlik için şimdilik orman, yerleşim yeri dışı ve deniz ya da göl üstü işaretlenemez."

    /// Seçim panelinin başlığının altındaki tek satır; `ready`de `nil`. Düzeltmede "çevrenin dışında" yerine
    /// türün ve ihtiyacın yine de düzeltilebildiği söylenir.
    static func placementMessage(_ verdict: PlacementVerdict, isEditing: Bool) -> String? {
        switch verdict {
        case .ready:
            return nil
        case .needsPermission:
            return "Konum izni kapalı. İşaret koymak için konum izni gerekiyor."
        case .approximateOnly:
            return "Tam Konum kapalı. İşaret koymak için Tam Konum gerekiyor."
        case .simulatedLocation:
            return "Konum taklit ediliyor gibi görünüyor. İşaret koymak için gerçek konum gerekiyor."
        case .locating(let slow):
            return slow
                ? "Konumun hâlâ bulunamadı. Açık bir alana çıkmayı ya da biraz beklemeyi dene."
                : "Konumun bulunuyor… İşaret, konumun belli olunca konabilir."
        case .tooFar:
            return isEditing
                ? "Konumu yalnızca bulunduğun yerin 150 m çevresine taşıyabilirsin. Türü ve ihtiyacı konumu değiştirmeden düzeltebilirsin."
                : "İğne çevrenin dışında. İşaret yalnızca bulunduğun yerin 150 m çevresine konabilir."
        case .water:
            return "Denizin ya da gölün üstüne işaret konamaz."
        case .forest:
            return "Gönüllülerin güvenliği için ormanlık alanlara şimdilik işaret konamaz."
        case .remote:
            return "Gönüllülerin güvenliği için yerleşim yeri dışına şimdilik işaret konamaz."
        }
    }

    /// Haritada çevrenin dışına uzun basıldı: işaretleme başlamaz.
    static let farLongPress = "Uzun bastığın yer bulunduğun yerden uzakta. İşaret yalnızca bulunduğun yerin 150 m çevresine konabilir; hayvanın yanındaysan 'Yardım gereken hayvan'a dokun."

    static let recenterPinTitle = "İğneyi konumuma getir"
    static let restorePinTitle = "İğneyi eski yerine getir"
    static let openSettingsTitle = "Ayarlar'ı aç"
    static let reportWrongBlockTitle = "Yanlış mı? Bize yaz"

    /// Konum izni kapalıyken "Yardım gereken hayvan".
    static let locationAlertTitle = "Konum izni gerekiyor"
    static let locationAlertMessage = "İşaret yalnızca bulunduğun yerin 150 m çevresine konabilir. Bunun için Ayarlar'dan konum iznini aç."
    static let locationAlertCancelTitle = "Vazgeç"

    /// "Yanlış mı? Bize yaz" e-postası. Yer ~1 km'ye yuvarlanır; kişi Mail'de göndermeden hiçbir şey gitmez.
    static let reportWrongBlockMailSubject = "Pati Harita: yanlış işaret engeli"

    static func reportWrongBlockMailBody(_ verdict: PlacementVerdict, dataVersion: String?, pin: Coordinate) -> String {
        let block: String
        switch verdict {
        case .forest: block = "Orman"
        case .remote: block = "Yerleşim yeri dışı"
        case .water: block = "Deniz ya da göl"
        case .ready, .needsPermission, .approximateOnly, .simulatedLocation, .locating, .tooFar: block = "-"
        }
        let lat = String(format: "%.2f", pin.latitude)
        let lon = String(format: "%.2f", pin.longitude)
        return "Engel: \(block)\nVeri sürümü: \(dataVersion ?? "-")\nYaklaşık yer (~1 km): https://maps.apple.com/?ll=\(lat),\(lon)\n\nBurada ne var? (ör. köy, site, park):\n"
    }

    /// Açıklama ekranında: alan verisinin kaynakları (ODbL gereği) ve sürümü.
    static func areaDataCredit(dataVersion: String) -> String {
        "Yerleşim ve orman verisi: © OpenStreetMap katkıcıları (ODbL) · Su: Natural Earth · Veri sürümü \(dataVersion)"
    }

    // MARK: "Hâlâ orada mı?"

    /// "Yakınındaki kedi hâlâ orada mı?", "Yardıma ihtiyacı var mı?", "Artık orada değil mi?"
    static func nearbyQuestion(_ step: NearbyPrompt.Step, report: Report) -> String {
        switch step {
        case .presence:
            let animal = report.species.title.lowercased(with: Locale(identifier: "tr_TR"))
            return "Yakınındaki \(animal) hâlâ orada mı?"
        case .needsHelp:
            return "Yardıma ihtiyacı var mı?"
        case .confirmGone:
            return "Artık orada değil mi?"
        }
    }

    /// Sorunun altındaki satır: "Yaralı / hasta · 30 m".
    static func nearbyDetail(_ step: NearbyPrompt.Step, report: Report, distance: Double?) -> String {
        switch step {
        case .presence:
            guard let distance else { return report.need.title }
            return "\(report.need.title) · \(Formatting.distance(meters: distance))"
        case .needsHelp:
            return "Aç ve zayıf olarak işaretlendi"
        case .confirmGone:
            return "Yaralı ya da korkmuş hayvanlar kolayca gözden kaçar. Yalnızca çevreye iyice baktıysan söyle."
        }
    }

    /// Soru belirince VoiceOver'a.
    static func nearbyAnnouncement(_ step: NearbyPrompt.Step, report: Report) -> String {
        "Yakınında bir işaret var. " + nearbyQuestion(step, report: report)
    }

    static let nearbyYesTitle = "Evet"
    static let nearbyNoTitle = "Hayır"
    static let nearbyDontKnowTitle = "Bilmiyorum"
    static let nearbyStillNeedsTitle = "Hâlâ yardım lazım"
    static let nearbyUnneededTitle = "Yardım gerekmiyor"
    static let nearbyGoneTitle = "Artık yok"
    static let nearbyUnsureTitle = "Emin değilim"

    // MARK: Düzeltme, bildirme, gizleme

    static let reportEdited = "İşaret güncellendi."
    static let editUnchanged = "Değişiklik yapılmadı."
    static let reportDeleted = "İşaret silindi."
    static let reportHidden = "İşaret senin haritandan kaldırıldı."
    static let flagSent = "Teşekkürler, bildirimin bize ulaştı. İşaret senin haritandan kaldırıldı."
    static let flagMailSubject = "Pati Harita işaret bildirimi"

    static func flagMailBody(reportID: String) -> String {
        "İşaret: \(reportID)\n\nNe gördüğünü kısaca yaz:\n"
    }

    /// "Konumu paylaş": "Pati Harita'dan bir hayvana yardıma gidiyorum: <Apple Haritalar bağlantısı>".
    static func shareLocation(_ coordinate: Coordinate) -> String {
        "Pati Harita'dan bir hayvana yardıma gidiyorum: https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=Pati%20Harita"
    }

    // MARK: Güvenlik

    /// Kurallar sayfasında ve ilk gidişteki uyarıda aynı cümleler.
    static let safetyRule = "Yalnız gitme, kimseyle tartışmaya girme, özel mülke girme. Hayati tehlike varsa 112'yi ara."
    /// Bu cihazda ilk "İlgileniyorum" ya da "Yol tarifi"nde bir kez (gece hatırlatması öncelikli); ileti `safetyRule`.
    static let goSafetyTitle = "Yardıma gidiyorsun"
    /// Bu ihtiyaçlarda "İlgileniyorum" bildirimine `goTogether` eklenir (gece hatırlatmasıyla aynı ihtiyaçlar).
    static let goTogetherNeeds: Set<Need> = [.emergency, .injured, .babies]
    static let goTogether = "Mümkünse biriyle git."

    // MARK: Güncelleme

    static let updateRequiredTitle = "Güncelleme gerekli"
    static let updateRequiredMessage = "Bu sürüm artık desteklenmiyor. TestFlight'tan güncelle."

    // MARK: Saat

    /// "saat 14.20" / "yarın saat 08.00" / "23 Eylül saat 08.00" (Türkiye saati).
    static func clockPhrase(_ date: Date, now: Date) -> String {
        let text = Formatting.clock(date, now: now)
        // `Formatting.clock` her zaman "SS.DD" ile biter; önündeki gün ("yarın ", "23 Eylül ") korunur.
        let time = String(text.suffix(5))
        let day = String(text.dropLast(5))
        return "\(day)saat \(time)"
    }

    /// "saat 14.20'de", "saat 09.00'da", "saat 14.40'ta": okunuşun son kelimesine göre bulunma eki.
    static func atClock(_ date: Date, now: Date) -> String {
        let phrase = clockPhrase(date, now: now)
        let time = phrase.suffix(5)
        let hour = Int(time.prefix(2)) ?? 0
        let minute = Int(time.suffix(2)) ?? 0
        return "\(phrase)'\(locativeSuffix(hour: hour, minute: minute))"
    }

    /// Dakika sıfırsa saat, değilse dakika okunur ("on dört yirmi" → -de, "dokuz" → -da, "kırk" → -ta).
    static func locativeSuffix(hour: Int, minute: Int) -> String {
        let number = minute != 0 ? minute : hour
        // Okunan son kelime: birler basamağı, o sıfırsa onlar ("otuz"), sayı sıfırsa "sıfır".
        let lastWord = number % 10 != 0 ? number % 10 : number
        switch lastWord {
        case 3, 4, 5: return "te"              // üç, dört, beş
        case 40: return "ta"                   // kırk
        case 1, 2, 7, 8, 20, 50: return "de"   // bir, iki, yedi, sekiz, yirmi, elli
        default: return "da"                   // sıfır, altı, dokuz, on, otuz
        }
    }

    // MARK: Yardımcılar

    /// "Çözüldü" / "Artık yok" / "Yardım gerekmiyor"
    static func verb(_ reason: ClosedReason) -> String {
        switch reason {
        case .resolved: "Çözüldü"
        case .gone: "Artık yok"
        case .unneeded: "Yardım gerekmiyor"
        case .expired: "Süresi doldu"
        }
    }

    /// Önerinin fiili; daha yeni bir sürümün tanımadığımız nedeni genel "…" olur ("… dendi").
    static func verb(_ closing: Closing) -> String {
        closing.unrecognizedReason == nil ? verb(closing.reason) : "…"
    }

    /// "Çözüldü dendi" / "Artık yok dendi" / "Yardım gerekmiyor dendi"
    static func saidLabel(_ reason: ClosedReason) -> String {
        "\(verb(reason)) dendi"
    }

    /// `saidLabel(_:)` gibi; tanınmayan neden "… dendi".
    static func saidLabel(_ closing: Closing) -> String {
        "\(verb(closing)) dendi"
    }

    /// Kapanan işaretin başlığı: "Çözüldü", "Artık orada değil", "Süresi doldu", "Yanlış alarmdı".
    static func closedTitle(_ reason: ClosedReason) -> String {
        switch reason {
        case .resolved: "Çözüldü"
        case .gone: "Artık orada değil"
        case .expired: "Süresi doldu"
        case .unneeded: "Yanlış alarmdı"
        }
    }
}

extension Species {
    /// Cümle içinde: "bir kedi için", "koyduğun köpek işareti".
    var noun: String {
        switch self {
        case .cat: "kedi"
        case .dog: "köpek"
        }
    }

    /// "Yavru kediler tehlikede".
    var pluralNoun: String {
        switch self {
        case .cat: "kediler"
        case .dog: "köpekler"
        }
    }
}
