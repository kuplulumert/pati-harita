import Foundation

/// `config/public.closingMode`: kanıtlı "Çözüldü dendi" işaretinin başkalarının haritasında nasıl göründüğü.
///
/// Sahip konsoldan değiştirir. Hiçbir işaret erken kapanmadığı için mod değişince gizlenen her işaret geri gelir.
public enum ClosingMode: String, CaseIterable, Sendable {
    /// Kanıtlı öneri, `Need.demoteMinutes` gündüz dakikası sonra başkalarının haritasından kalkar.
    case demote
    /// Kanıtlı öneri soluk ve "?" rozetli kalır; onaylanınca ya da süresi dolunca kalkar.
    case label
    /// Her öneri yalnızca "?" (doğrulanmadı) olarak görünür.
    case strict

    /// Doküman yoksa ya da değer tanınmıyorsa.
    public static let fallback: ClosingMode = .label
}

/// "… dendi" işaretinin bir kişinin haritasındaki görünüşü.
public enum ClosingLook: Equatable, Sendable {
    /// Normal renk ve boyut, "?" rozeti; hâlâ yardım bekleyenler arasında sayılır.
    case unverified
    /// "?" rozeti, hafif ihtiyaçlarda soluk; sayılmaz. `leavesAt`: haritadan kalkış (label modunda `nil`).
    case fading(leavesAt: Date?)
    /// Çizilmez; yalnızca sokak yakınlığında gri nokta (bkz. `ClosingDisplay.streetDotMaxRadius`).
    case hidden
}

/// "Çözüldü dendi" işaretinin kimin haritasında, ne zamana kadar ve nasıl görüneceği.
///
/// Yalnızca gösterimdir: doküman ikinci kişi onaylayana, itiraz edilene, geri alınana
/// ya da süresi dolana kadar `closing` kalır.
public enum ClosingDisplay {
    /// Gündüz saati 07:00–24:00 (Türkiye, sabit UTC+3); gece yarısından 07:00'ye kadar süre işlemez.
    public static let dayStartHour = 7
    public static let dayEndHour = 24
    public static let utcOffsetHours = 3
    /// Gizlenen işaretin gri noktası yalnızca görünen yarıçap bu kadar (metre) ya da daha küçükken çizilir.
    public static let streetDotMaxRadius: Double = 600
    /// Kapatanın "Geri al" düğmeli bildiriminin ekranda kalma süresi.
    public static let closerUndoToastDuration: TimeInterval = 10

    /// Kanıtlı önerinin başkalarının haritasından kalkacağı an: `need.demoteMinutes`,
    /// yalnızca gündüz (07:00–24:00, sabit UTC+3) sayılarak. Ör. 23.30'da mama → 07.30, 02.00'de yavru → 09.00.
    public static func demoteAt(closingAt: Date, need: Need) -> Date {
        let day: TimeInterval = 24 * 3600
        let dayStart = TimeInterval(dayStartHour) * 3600
        let dayEnd = TimeInterval(dayEndHour) * 3600
        let offset = TimeInterval(utcOffsetHours) * 3600

        let local = closingAt.timeIntervalSince1970 + offset
        // Yerel gece yarısı ve o günün içindeki saniye; tekrar tekrar toplama yapmadan gün gün ilerlenir.
        var midnight = (local / day).rounded(.down) * day
        var cursor = max(local - midnight, dayStart)
        var remaining = TimeInterval(need.demoteMinutes) * 60
        while true {
            let available = dayEnd - cursor
            if remaining <= available {
                return Date(timeIntervalSince1970: midnight + cursor + remaining - offset)
            }
            remaining -= max(0, available)
            midnight += day
            cursor = dayStart
        }
    }

    /// İşareti koyan ya da hayvanı gördüğünü söyleyen (kapatan hariç) ve öneriye hâlâ yanıt verebilen kişi
    /// (`ReportLifecycle.canAnswerClosing`). Yanıt veremeyen (ör. bu işarete daha önce itiraz etmiş) kişiye
    /// soru sorulmaz; işaret onun haritasından da başkalarınınkiyle birlikte kalkar.
    public static func isStakeholder(_ report: Report, viewer: String?) -> Bool {
        guard let viewer, report.closing?.userID != viewer else { return false }
        guard report.reporterID == viewer || report.seenBy.contains(viewer) else { return false }
        return ReportLifecycle.canAnswerClosing(report, by: viewer)
    }

    /// `viewer` için "… dendi" görünüşü; işaret `closing` değilse `nil`.
    ///
    /// `answered`: bu kişi takip sorusunu ("Doğru mu?") bu işaret için yanıtladı mı.
    /// Yanıtlamayan paydaş, işaret başkalarından kalksa da görmeye devam eder.
    public static func look(of report: Report, mode: ClosingMode, viewer: String?, answered: Bool, at now: Date) -> ClosingLook? {
        guard report.status == .closing, let closing = report.closing else { return nil }
        // Kapatanın haritasından hemen kalkar; sokak yakınlığındaki nokta "Geri al"a izin verir.
        if let viewer, closing.userID == viewer { return .hidden }
        guard closing.credible, mode != .strict else { return .unverified }
        guard mode == .demote else { return .fading(leavesAt: nil) }
        let leavesAt = demoteAt(closingAt: closing.at, need: report.need)
        if now < leavesAt || (isStakeholder(report, viewer: viewer) && !answered) {
            return .fading(leavesAt: leavesAt)
        }
        return .hidden
    }

    /// "N hayvan yardım bekliyor" sayısına girer mi? Bekleyen işaret, başkasının 45 dk'yı geçen sahipliği
    /// ve doğrulanmamış ("?") öneri sayılır. Kapatanın kendi önerisi, onun haritasında olmadığı için sayılmaz.
    public static func countsAsWaiting(_ report: Report, viewer: String?, mode: ClosingMode, at now: Date) -> Bool {
        switch report.phase(for: viewer, at: now) {
        case .waiting:
            return true
        case .helpedByOther:
            return report.isClaimStale(at: now)
        case .helpedByMe, .closed:
            return false
        case .closing:
            return look(of: report, mode: mode, viewer: viewer, answered: true, at: now) == .unverified
        }
    }

    /// Başlığın sayıları: `countsAsWaiting` olan işaretler, ağır ihtiyaçlar ve hafifler (`Need.isSerious`) ayrı.
    /// "3 hayvan yardım bekliyor · 5 düşük öncelikli".
    public static func waitingCounts<S: Sequence>(
        _ reports: S,
        viewer: String?,
        mode: ClosingMode,
        at now: Date
    ) -> WaitingCounts where S.Element == Report {
        var counts = WaitingCounts()
        for report in reports where countsAsWaiting(report, viewer: viewer, mode: mode, at: now) {
            if report.need.isSerious {
                counts.serious += 1
            } else {
                counts.light += 1
            }
        }
        return counts
    }
}

/// Haritadaki "yardım bekliyor" sayısı: ağır ihtiyaçlar önce, hafifler (mama) "düşük öncelikli" olarak ayrı.
public struct WaitingCounts: Hashable, Sendable {
    public var serious: Int
    public var light: Int

    public init(serious: Int = 0, light: Int = 0) {
        self.serious = serious
        self.light = light
    }

    public var total: Int { serious + light }
}
