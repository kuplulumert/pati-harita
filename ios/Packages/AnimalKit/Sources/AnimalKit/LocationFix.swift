import Foundation

/// CoreLocation'a bağımlı olmayan bir konum okuması. Uygulama `CLLocation`dan doldurur.
public struct LocationFix: Equatable, Sendable {
    public var coordinate: Coordinate
    public var timestamp: Date
    /// Metre; CoreLocation'daki gibi geçersiz okumada negatif.
    public var horizontalAccuracy: Double
    /// m/s; bilinmiyorsa negatif.
    public var speed: Double
    /// m/s; hız geçersizse negatif.
    public var speedAccuracy: Double
    /// `CLLocationSourceInformation.isSimulatedBySoftware` (konum taklit ediliyor).
    public var isSimulatedBySoftware: Bool

    public init(
        coordinate: Coordinate,
        timestamp: Date,
        horizontalAccuracy: Double,
        speed: Double = -1,
        speedAccuracy: Double = -1,
        isSimulatedBySoftware: Bool = false
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.isSimulatedBySoftware = isSimulatedBySoftware
    }

    /// Okumanın yaşı (saniye). Cihaz saati okumadan gerideyse negatif olabilir.
    public func age(at now: Date) -> TimeInterval {
        now.timeIntervalSince(timestamp)
    }

    /// Yeni okuma, eldekinden en fazla bu kadar metre daha kaba olsa da alınır.
    public static let replaceAccuracySlack: Double = 20
    /// Yeni okuma eldekinden bu kadar saniyeden daha yeniyse doğruluğuna bakılmadan alınır.
    public static let replaceAfter: TimeInterval = 15

    /// "En iyi yakın okuma": yeni okuma eldekinin yerini almalı mı?
    ///
    /// - Negatif doğruluklu (geçersiz) okuma hiç alınmaz.
    /// - Eldekinden eski okuma alınmaz: yeniden başlatınca önce önbellekteki eski konum gelir.
    /// - Doğruluğu eldekinden en fazla 20 m kötüyse ya da eldekinden 15 sn'den daha yeniyse alınır;
    ///   yoksa tek bir kaba okuma iyi konumu silmesin diye eldeki kalır.
    public static func shouldReplace(current: LocationFix?, with new: LocationFix) -> Bool {
        // NaN da burada elenir.
        guard new.horizontalAccuracy >= 0 else { return false }
        guard let current else { return true }
        guard new.timestamp >= current.timestamp else { return false }
        if new.horizontalAccuracy <= current.horizontalAccuracy + replaceAccuracySlack { return true }
        return new.timestamp.timeIntervalSince(current.timestamp) > replaceAfter
    }
}
