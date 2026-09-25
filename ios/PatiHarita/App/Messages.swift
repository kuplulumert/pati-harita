import AnimalKit
import Foundation

/// Saate, sayıya ve kişiye göre değişen Türkçe metinler: bildirimler, günlük sınır, takip sorusu.
enum Messages {
    // MARK: Düğmeler

    /// Eylemin bu kişi için başlığı: işareti koyanın başkasının sahipliğini kaldırması "İlgilenen gelmedi",
    /// "Artık yok dendi"yi onaylamak "Evet, artık yok"; diğerleri `ReportAction.title`.
    static func title(for action: ReportAction, on report: Report, userID: String?, now: Date) -> String {
        switch action {
        case .release:
            let isClaimer = report.activeClaim(at: now)?.userID == userID
            return report.reporterID == userID && !isClaimer ? "İlgilenen gelmedi" : action.title
        case .confirmClosing:
            return confirmClosingTitle(report.closing?.reason ?? .resolved)
        case .claim, .resolve, .confirmStillThere, .reportGone, .dispute, .undoClosing, .expire:
            return action.title
        }
    }

    static func confirmClosingTitle(_ reason: ClosedReason) -> String {
        reason == .gone ? "Evet, artık yok" : "Evet, çözüldü"
    }

    // MARK: Eylem bildirimleri

    /// Öneri başlatmayan eylemlerden sonra.
    static func actionDone(_ action: ReportAction, outcome: ActionOutcome, addsSeen: Bool) -> String {
        switch action {
        case .claim:
            return "Teşekkürler! İşaret \(Int(ReportLifecycle.claimDuration / 3600)) saat boyunca sende."
        case .release:
            return "İşaret yeniden yardım bekliyor."
        case .resolve, .confirmClosing:
            return "Harika! İşaret haritadan kaldırıldı."
        case .confirmStillThere:
            return addsSeen
                ? "Teşekkürler! Bu hayvanı artık \(outcome.report.seenCount) kişi bildirdi."
                : "Teşekkürler, işaret güncellendi."
        case .reportGone:
            if outcome.report.status == .closed { return "Teşekkürler! İşaret haritadan kaldırıldı." }
            return "Teşekkürler. \(ReportLifecycle.goneThreshold) kişi 'Artık yok' derse işaret 'Artık yok dendi' olarak işaretlenir."
        case .dispute:
            return "Teşekkürler, işaret yeniden yardım bekliyor."
        case .undoClosing:
            return "Geri alındı; işaret yeniden yardım bekliyor."
        case .expire:
            return "Bu işaretin süresi doldu."
        }
    }

    /// "Çözüldü" / "Artık yok" diyene: işaretin başkalarının haritasında ne olacağı (kanıtlılık ve moda göre).
    /// Hepsi "Teşekkürler! … kaydedildi." ile başlar.
    static func closerToast(
        for report: Report,
        by userID: String,
        credibility: CloseCredibility,
        mode: ClosingMode,
        now: Date
    ) -> String {
        let reason = report.closing?.reason ?? .resolved
        let thanks = reason == .gone ? "Teşekkürler! Bildirimin kaydedildi." : "Teşekkürler! Yardımın kaydedildi."
        // İşareti koyan kapattıysa onu hayvanı gören başka biri onaylar.
        let confirmer = report.reporterID == userID ? "hayvanı gören başka biri" : "koyan kişi"
        let unverified = "Bu işaret, \(confirmer) onaylayana kadar başkalarına 'doğrulanmadı' olarak görünecek."

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
                return "\(thanks) İşaret '\(saidLabel(reason))' olarak görünecek; \(confirmer) onaylayınca ya da süresi dolunca kalkacak."
            case .strict:
                return "\(thanks) \(unverified)"
            }
        case .newAccount:
            return "\(thanks) Uygulamanın ilk gününde '\(verb(reason))' başkalarına 'doğrulanmadı' olarak görünür; \(confirmer) onaylayınca kalkar."
        case .budgetUsed:
            return "\(thanks) Son 24 saatte çok işaret kapattın; bu işaret, \(confirmer) onaylayana kadar 'doğrulanmadı' olarak görünecek."
        case .disputed:
            return "\(thanks) Bu işarete daha önce itiraz edildiği için 'doğrulanmadı' olarak görünecek."
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

    /// Seçim panelinde: hak azaldıysa "Bugün 3 işaret hakkın kaldı", bittiyse ne zaman açılacağı; yoksa `nil`.
    static func createAllowance(_ record: UserRecord, lowThreshold: Int, now: Date) -> String? {
        let remaining = Budget.remainingCreates(record, at: now)
        if remaining == 0 {
            return Budget.nextCreateAt(record, at: now).map { "Yeni işaret hakkın \(atClock($0, now: now)) açılır" }
        }
        return remaining <= lowThreshold ? "Bugün \(remaining) işaret hakkın kaldı" : nil
    }

    // MARK: "… dendi" soruları

    /// 40 m önerisi bir "… dendi" işaretine denk geldi: "Burada 2 sa önce bir kedi için 'Çözüldü' dendi. …"
    static func duplicateClosingPrompt(_ report: Report, now: Date) -> String? {
        guard let closing = report.closing else { return nil }
        let ago = Formatting.timeAgo(closing.at, now: now)
        return "Burada \(ago) bir \(report.species.noun) için '\(verb(closing.reason))' dendi. Aynı hayvan mı, hâlâ yardım gerekiyor mu?"
    }

    /// A7 takip sorusu. `leavesAt`: işaretin başkalarının haritasından kalkacağı an (biliniyorsa).
    static func followUp(_ report: Report, viewer: String, leavesAt: Date?, now: Date) -> String {
        guard let closing = report.closing else { return "" }
        let animal = "\(report.species.noun) (\(report.need.title))"
        let ago = Formatting.timeAgo(closing.at, now: now)
        let said = "'\(verb(closing.reason))'"
        var text: String
        if report.reporterID == viewer {
            text = "Koyduğun \(report.species.noun) işareti (\(report.need.title)) için \(ago) \(said) dendi. Doğru mu?"
        } else if closing.userID == report.reporterID && report.seenBy.contains(viewer) {
            // İşareti koyanın önerisini hayvanı gören başka biri onaylayabilir.
            text = "İşareti koyan, gördüğün \(animal) için \(ago) \(said) dedi. Doğru mu?"
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

    /// "Çözüldü" / "Artık yok"
    static func verb(_ reason: ClosedReason) -> String {
        reason == .gone ? "Artık yok" : "Çözüldü"
    }

    /// "Çözüldü dendi" / "Artık yok dendi"
    static func saidLabel(_ reason: ClosedReason) -> String {
        "\(verb(reason)) dendi"
    }
}

extension Species {
    /// Cümle içinde: "bir kedi için", "koyduğun köpek işareti".
    var noun: String {
        switch self {
        case .cat: "kedi"
        case .dog: "köpek"
        case .bird: "kuş"
        case .other: "hayvan"
        }
    }
}
