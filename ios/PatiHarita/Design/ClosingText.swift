import AnimalKit
import Foundation

/// "… dendi" işaretinin kartta, takip sorusunda ve sesli okumada söylenen metinleri. Hüküm vermez, olgu söyler
/// (kim, ne zaman, kaç kişi); görünüş (`ClosingLook`) kişiye ve moda göre değişir.
///
/// Metinler nedeni `Closing`ten okur: daha yeni bir sürümün yazdığı, bu sürümün tanımadığı neden genel
/// "… dendi" olur (`Messages.verb(_: Closing)`).
enum ClosingText {
    /// Kartın iki satırlık durum bloğu. Başkasının önerisinde kim ne dedi, sonra ne zaman ve nasıl göründüğü:
    /// "'İlgileniyorum' demeyen biri 'Çözüldü' dedi" / "20 dk önce · doğrulanmadı". Onaylayabilene "… dedi. Doğru mu?",
    /// daha önce itiraz etmiş olana "… · itiraz ettin". Öneriyi yapana: "'Çözüldü' dedin · 2 dk önce" /
    /// "Başkalarına 'doğrulanmadı' görünüyor".
    static func cardStatus(
        report: Report,
        closing: Closing,
        viewer: String?,
        look: ClosingLook?,
        canConfirm: Bool,
        closingMode: ClosingMode,
        now: Date
    ) -> (line1: String, line2: String?) {
        let ago = Formatting.timeAgo(closing.at, now: now)
        if let viewer, closing.userID == viewer {
            return ("'\(Messages.verb(closing))' dedin · \(ago)", othersLine(report, closing: closing, mode: closingMode, now: now))
        }
        var line1 = subject(of: report, closing: closing, countsVotes: true)
        if canConfirm {
            line1 += ". Doğru mu?"
        }
        var parts = [ago]
        if let look, let suffix = lookSuffix(look, now: now) {
            parts.append(suffix)
        }
        // İşareti koyan dışındakiler bir kez itiraz edebilir: düğme neden yok, bilsin.
        if let viewer, report.objectors.contains(viewer) {
            parts.append("itiraz ettin")
        }
        return (line1, parts.joined(separator: " · "))
    }

    /// "doğrulanmadı", "Haritadan kalkış: 14.20", "başkalarının haritasından kalktı", "haritadan kalktı".
    private static func lookSuffix(_ look: ClosingLook, now: Date) -> String? {
        switch look {
        case .unverified:
            return "doğrulanmadı"
        case .fading(let leavesAt):
            // label modunda kalkış anı yoktur. Yanıtlamamış paydaş, başkalarından kalktıktan sonra da görür.
            guard let leavesAt else { return nil }
            return leavesAt > now
                ? "Haritadan kalkış: \(Formatting.clock(leavesAt, now: now))"
                : "başkalarının haritasından kalktı"
        case .hidden:
            return "haritadan kalktı"
        }
    }

    /// Öneriyi yapana: işaret başkalarının haritasında ne durumda (kanıtlılığa ve moda göre). Ayrıntısı
    /// öneri anındaki bildirimdeydi; burada kısa.
    private static func othersLine(_ report: Report, closing: Closing, mode: ClosingMode, now: Date) -> String? {
        guard let others = ClosingDisplay.look(of: report, mode: mode, viewer: nil, answered: true, at: now) else {
            return nil
        }
        switch others {
        case .unverified:
            return "Başkalarına 'doğrulanmadı' görünüyor"
        case .fading(let leavesAt):
            guard let leavesAt else { return "Başkalarına '\(Messages.saidLabel(closing))' görünüyor" }
            return leavesAt > now
                ? "Başkalarının haritasından \(Messages.atClock(leavesAt, now: now)) kalkacak"
                : "Başkalarının haritasından da kalktı"
        case .hidden:
            return "Başkalarının haritasından da kalktı"
        }
    }

    /// Öneriyi kimin yaptığı: "İşareti koyan 'Çözüldü' dedi." / "İlgilenmeye başlayan kişi 40 dk sonra 'Çözüldü' dedi." /
    /// "'İlgileniyorum' demeyen biri 'Yardım gerekmiyor' dedi."
    static func proposer(of report: Report, closing: Closing) -> String {
        "\(subject(of: report, closing: closing, countsVotes: false))."
    }

    /// `proposer` noktasız. `countsVotes`: oylarla başlayan "Artık yok" önerisi "3 kişi 'Artık yok' dedi" olur
    /// (kartta; takip sorusu oyları ayrı satırda söyler).
    private static func subject(of report: Report, closing: Closing, countsVotes: Bool) -> String {
        let said = "'\(Messages.verb(closing))'"
        if closing.userID == report.reporterID {
            return "İşareti koyan \(said) dedi"
        }
        // Sahiplik alanları öneri sırasında da dokümanda kalır (zaman çizelgesi için).
        if let claim = report.claim, claim.userID == closing.userID, claim.claimedAt <= closing.at {
            let after = Formatting.remaining(until: closing.at, now: claim.claimedAt)
            return "İlgilenmeye başlayan kişi \(after) sonra \(said) dedi"
        }
        if countsVotes, closing.reason == .gone, closing.unrecognizedReason == nil, report.goneReports.count >= 2 {
            return "\(report.goneReports.count) kişi \(said) dedi"
        }
        return "'İlgileniyorum' demeyen biri \(said) dedi"
    }

    /// "3 kişi 'Artık yok' dedi."; oy yoksa `nil`.
    static func goneVotes(_ report: Report) -> String? {
        goneVoteLine(report).map { "\($0)." }
    }

    /// `goneVotes` noktasız (kartın durum satırı).
    static func goneVoteLine(_ report: Report) -> String? {
        report.goneReports.isEmpty ? nil : "\(report.goneReports.count) kişi 'Artık yok' dedi"
    }

    /// Haritadaki işaretin sesli okunan değerine eklenir: "Çözüldü dendi, doğrulanmadı" /
    /// "Yardım gerekmiyor dendi, birazdan kalkacak" / "Çözüldü dendi, haritadan kalktı".
    static func accessibilityValue(_ look: ClosingLook, closing: Closing, now: Date) -> String {
        let said = Messages.saidLabel(closing)
        switch look {
        case .unverified:
            return "\(said), doğrulanmadı"
        case .fading(let leavesAt):
            // label modunda kalkış anı yoktur: onaylanana ya da süresi dolana kadar kalır.
            guard let leavesAt else { return said }
            return leavesAt > now ? "\(said), birazdan kalkacak" : "\(said), başkalarının haritasından kalktı"
        case .hidden:
            return "\(said), haritadan kalktı"
        }
    }
}
