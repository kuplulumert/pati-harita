import AnimalKit
import Foundation

/// "… dendi" işaretinin kartta, takip sorusunda ve sesli okumada söylenen metinleri. Hüküm vermez, olgu söyler
/// (kim, ne zaman, kaç kişi); görünüş (`ClosingLook`) kişiye ve moda göre değişir.
///
/// Metinler nedeni `Closing`ten okur: daha yeni bir sürümün yazdığı, bu sürümün tanımadığı neden genel
/// "… dendi" olur (`Messages.verb(_: Closing)`).
enum ClosingText {
    /// Kartın durum satırı: "Çözüldü dendi · 20 dk önce · doğrulanmadı", "… · Haritadan kalkış: 14.20",
    /// "… · haritadan kalktı". Öneriyi yapana: "'Çözüldü' dedin · 2 dk önce".
    static func status(of closing: Closing, viewer: String?, look: ClosingLook?, now: Date) -> String {
        let ago = Formatting.timeAgo(closing.at, now: now)
        if let viewer, closing.userID == viewer {
            return "'\(Messages.verb(closing))' dedin · \(ago)"
        }
        var parts = [Messages.saidLabel(closing), ago]
        if let look {
            switch look {
            case .unverified:
                parts.append("doğrulanmadı")
            case .fading(let leavesAt):
                // label modunda kalkış anı yoktur. Yanıtlamamış paydaş, başkalarından kalktıktan sonra da görür.
                if let leavesAt {
                    parts.append(leavesAt > now
                        ? "Haritadan kalkış: \(Formatting.clock(leavesAt, now: now))"
                        : "başkalarının haritasından kalktı")
                }
            case .hidden:
                parts.append("haritadan kalktı")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Öneriyi kimin yaptığı: "İşareti koyan 'Çözüldü' dedi." / "İlgilenmeye başlayan kişi 40 dk sonra 'Çözüldü' dedi." /
    /// "'İlgileniyorum' demeyen biri 'Yardım gerekmiyor' dedi."
    static func proposer(of report: Report, closing: Closing) -> String {
        let said = "'\(Messages.verb(closing))'"
        if closing.userID == report.reporterID {
            return "İşareti koyan \(said) dedi."
        }
        // Sahiplik alanları öneri sırasında da dokümanda kalır (zaman çizelgesi için).
        if let claim = report.claim, claim.userID == closing.userID, claim.claimedAt <= closing.at {
            let after = Formatting.remaining(until: closing.at, now: claim.claimedAt)
            return "İlgilenmeye başlayan kişi \(after) sonra \(said) dedi."
        }
        return "'İlgileniyorum' demeyen biri \(said) dedi."
    }

    /// "3 kişi 'Artık yok' dedi."; oy yoksa `nil`.
    static func goneVotes(_ report: Report) -> String? {
        report.goneReports.isEmpty ? nil : "\(report.goneReports.count) kişi 'Artık yok' dedi."
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
