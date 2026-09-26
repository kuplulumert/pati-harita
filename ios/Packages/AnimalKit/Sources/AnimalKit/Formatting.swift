import Foundation

/// Kısa, taranabilir Türkçe metinler: "az önce", "12 dk önce", "350 m", "1,2 km".
public enum Formatting {
    public static func timeAgo(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "az önce"
        case ..<3600: return "\(Int(seconds / 60)) dk önce"
        case ..<86400: return "\(Int(seconds / 3600)) sa önce"
        default: return "\(Int(seconds / 86400)) gün önce"
        }
    }

    /// Kalan süre: "2 sa 15 dk", "40 dk", "1 dk".
    public static func remaining(until date: Date, now: Date) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(minutes) dk" }
        return rest == 0 ? "\(hours) sa" : "\(hours) sa \(rest) dk"
    }

    public static func distance(meters: Double) -> String {
        let roundedMeters = Int((meters / 10).rounded()) * 10
        if roundedMeters < 1000 {
            return "\(max(10, roundedMeters)) m"
        }
        let kilometers = meters / 1000
        if kilometers < 10 {
            return String(format: "%.1f km", kilometers).replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int(kilometers.rounded())) km"
    }

    /// Haritadaki işaretin köşesindeki "kaç kişi bildirdi" rozeti: "2" … "99", sonra "99+".
    /// Yalnızca işareti koyan bildirdiyse (1) rozet yoktur.
    public static func seenCountBadge(_ count: Int) -> String? {
        switch count {
        case ..<2: return nil
        case ..<100: return "\(count)"
        default: return "99+"
        }
    }

    /// Kartta ve öneride gösterilen "3 kişi bildirdi"; tek kişi bildirdiyse `nil`.
    public static func seenCount(_ count: Int) -> String? {
        count < 2 ? nil : "\(count) kişi bildirdi"
    }

    /// Türkiye saatiyle saat: bugünse "14.20", yarınsa "yarın 08.00", dünse "dün 23.10",
    /// daha uzaksa "23 Eylül 08.00". Cihazın saat diliminden bağımsızdır (kurallar Türkiye günüyle sayar).
    public static func clock(_ date: Date, now: Date) -> String {
        let calendar = turkeyCalendar
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let time = "\(twoDigits(parts.hour ?? 0)).\(twoDigits(parts.minute ?? 0))"
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case 0: return time
        case 1: return "yarın \(time)"
        case -1: return "dün \(time)"
        default:
            let month = min(max(parts.month ?? 1, 1), 12)
            return "\(parts.day ?? 1) \(monthNames[month - 1]) \(time)"
        }
    }

    private static let turkeyCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? TimeZone(secondsFromGMT: 3 * 3600) ?? .current
        return calendar
    }()

    private static let monthNames = [
        "Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
        "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık",
    ]

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
