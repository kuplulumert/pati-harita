import Foundation

/// "Yardıma ihtiyacı var mı?" kontrolü ve "İğne bulunduğun yerden … uzakta" sorusu: ne zaman sorulacakları.
///
/// Hiçbiri işaretlemeyi engellemez. Gereksiz işaretlerin çoğu iyi niyetli insanlardan gelir (her sokak
/// kedisi aç görünür); doğru anda tek bir cümle yeter. Sayaçları uygulama cihazda tutar.
public enum GentleCheck {
    /// Bu cihazın ilk bu kadar hafif işaretinde (`Need.needsGentleCheck`) kontrol her zaman gösterilir.
    public static let introReports = 3
    /// Sonra yalnızca cihaz son `recentWindow` içinde en az bu kadar acil olmayan işaret koyduysa.
    public static let recentReportsThreshold = 2
    public static let recentWindow: TimeInterval = 24 * 3600
    /// Uzaklık sorusu yalnızca en fazla bu kadar eski konumla sorulur.
    public static let maxFixAge: TimeInterval = 2 * 60
    /// ... ve konumun doğruluğu bu kadar metre ya da daha iyiyse.
    public static let maxFixAccuracy: Double = 100
    /// İğne konumdan bu kadar metreden uzaksa sorulur.
    public static let farDistance: Double = 1000

    /// Kontrol neden gösteriliyor.
    public enum Reason: Hashable, Sendable {
        /// Cihazın ilk hafif işaretlerinden biri.
        case intro
        /// Son 24 saatte `count` acil olmayan işaret kondu: kontrol "Son 24 saatte N işaret koydun." ile başlar.
        case recent(count: Int)
    }

    /// Kontrol gösterilecekse nedeni, gösterilmeyecekse `nil`.
    ///
    /// - `lightReportsSoFar`: bu cihazın şimdiye kadar koyduğu hafif işaret sayısı.
    /// - `recentReports`: bu cihazın son `recentWindow` içinde koyduğu acil olmayan işaret sayısı (bu işaret hariç).
    public static func reason(for need: Need, lightReportsSoFar: Int, recentReports: Int) -> Reason? {
        guard need.needsGentleCheck else { return nil }
        if recentReports >= recentReportsThreshold { return .recent(count: recentReports) }
        return lightReportsSoFar < introReports ? Reason.intro : nil
    }

    /// Bu an, "son 24 saatte konan işaret" sayısına girer mi?
    public static func isRecent(_ reportedAt: Date, at now: Date) -> Bool {
        now.timeIntervalSince(reportedAt) < recentWindow
    }

    /// Uzaklık sorusu sorulacaksa iğnenin konuma uzaklığı (metre), yoksa `nil`. Acil yardımda hiç sorulmaz;
    /// konum eski ya da kaba ise de sorulmaz: yanlış bir soru sormaktansa hiç sormamak iyidir.
    ///
    /// `horizontalAccuracy`: CoreLocation'daki gibi metre; geçersiz konumda negatif.
    public static func distanceToAsk(
        need: Need,
        pin: Coordinate,
        fix: Coordinate,
        fixAt: Date,
        horizontalAccuracy: Double,
        at now: Date
    ) -> Double? {
        guard need != .emergency else { return nil }
        guard now.timeIntervalSince(fixAt) <= maxFixAge else { return nil }
        guard horizontalAccuracy >= 0, horizontalAccuracy <= maxFixAccuracy else { return nil }
        let distance = fix.distance(to: pin)
        return distance > farDistance ? distance : nil
    }
}
