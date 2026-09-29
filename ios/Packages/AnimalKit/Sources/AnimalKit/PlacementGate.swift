import Foundation

/// Konum izni, CoreLocation'dan bağımsız.
public enum LocationAccess: Equatable, Sendable {
    /// Henüz sorulmadı.
    case notDetermined
    /// Reddedildi ya da kısıtlı.
    case denied
    /// İzin var ama Tam Konum kapalı.
    case approximate
    /// İzin ve Tam Konum var.
    case full
}

/// Yeni işaretin (ya da düzeltilen işaretin yeni yerinin) şimdi kaydedilip kaydedilemeyeceği.
/// Tek bir başlık satırını ve ihtiyaç düğmelerinin açık olup olmadığını belirler.
public enum PlacementVerdict: Equatable, Sendable {
    case ready
    /// Konum izni kapalı.
    case needsPermission
    /// Tam Konum kapalı.
    case approximateOnly
    /// Konum yazılımla taklit ediliyor.
    case simulatedLocation
    /// Kullanılabilir konum yok; `slow`: `PlacementGate.slowLocatingAfter` geçti.
    case locating(slow: Bool)
    /// İğne izin verilen çevrenin dışında.
    case tooFar
    /// İğne denizin ya da gölün üstünde.
    case water
    /// İğne ormanlık alanda.
    case forest
    /// İğne yerleşim yeri dışında.
    case remote

    /// İhtiyaç düğmeleri kapalı mı? Her `ready` dışı karar kaydı engeller.
    public var isBlocking: Bool { self != .ready }

    /// Engel iğnenin yerinden mi geliyor (orman, yerleşim dışı, su)?
    public var isAreaBlock: Bool {
        switch self {
        case .water, .forest, .remote: true
        case .ready, .needsPermission, .approximateOnly, .simulatedLocation, .locating, .tooFar: false
        }
    }
}

/// Yakınlık kapısı: işaret yalnızca bulunulan yerin çevresine, orman, yerleşim dışı ve su dışına konabilir.
/// Saf mantıktır: konumu, izni ve iğnenin alan sınıfını uygulama verir. Konum hiçbir yere gönderilmez.
public enum PlacementGate {
    /// Kullanıcının gördüğü ve metnin söylediği çevre (metre).
    public static let radius: Double = 150
    /// Konum doğruluğu kadar ek pay, en fazla bu kadar metre: izin verilen en büyük çevre 225 m.
    public static let maxAccuracyAllowance: Double = 75
    /// Bundan kaba okuma kullanılmaz (kapı "konum bulunuyor"da kalır).
    public static let maxAccuracy: Double = 100
    /// Bundan eski okuma kullanılmaz. Kartın "yakın" ölçüsü de bunu kullanır (`CardLayout.isNear`).
    public static let maxFixAge: TimeInterval = 2 * 60
    /// Konum bu kadar saniyedir bulunamıyorsa "hâlâ bulunamadı" metni gösterilir.
    public static let slowLocatingAfter: TimeInterval = 20
    /// İşaretleme başlarken konum bundan eskiyse güncellemeler yeniden başlatılır.
    public static let refreshIfOlderThan: TimeInterval = 30
    /// Düzeltmede iğne bundan az kaydıysa "kaydırılmadı" sayılır (metre).
    public static let unmovedTolerance: Double = 1

    /// İzin verilen en büyük çevre (metre): `radius + maxAccuracyAllowance`.
    public static var maxAllowedRadius: Double { radius + maxAccuracyAllowance }

    /// Bu doğruluktaki okumayla izin verilen çevre: `radius + min(max(doğruluk, 0), 75)`.
    public static func allowedRadius(accuracy: Double) -> Double {
        // NaN ek pay vermez.
        let allowance = accuracy.isNaN ? 0 : min(max(accuracy, 0), maxAccuracyAllowance)
        return radius + allowance
    }

    /// Okuma kapı için kullanılabilir mi: doğruluk 0...100 m ve yaşı en fazla 120 sn.
    public static func isUsable(_ fix: LocationFix?, at now: Date) -> Bool {
        guard let fix else { return false }
        return fix.coordinate.latitude.isFinite
            && fix.coordinate.longitude.isFinite
            && (0...maxAccuracy).contains(fix.horizontalAccuracy)
            && fix.age(at: now) <= maxFixAge
    }

    /// Nokta, okumanın izin verilen çevresinin içinde mi? Ölçülemeyen uzaklık (NaN) dışarıda sayılır.
    public static func isWithinAllowedRadius(_ point: Coordinate, of fix: LocationFix) -> Bool {
        point.distance(to: fix.coordinate) <= allowedRadius(accuracy: fix.horizontalAccuracy)
    }

    /// Uzun basılan yerden işaretleme başlasın mı? Yalnızca kullanılabilir konum varken ve nokta
    /// çevrenin dışındaysa `false`: konum yoksa panel açılır ve "konum bulunuyor"da bekler.
    public static func acceptsLongPress(at point: Coordinate, fix: LocationFix?, at now: Date) -> Bool {
        guard isUsable(fix, at: now), let fix else { return true }
        return isWithinAllowedRadius(point, of: fix)
    }

    /// Alan sınıfının kararı. Bilinmeyen alan (kutunun dışı, ızgara yok) serbesttir.
    public static func areaVerdict(_ area: AreaClass?) -> PlacementVerdict {
        switch area {
        case .some(.water):
            return .water
        case .some(.forest):
            return .forest
        case .some(.remote):
            return .remote
        case .some(.allowed), .none:
            return .ready
        }
    }

    /// Yeni işaretin kararı; ilk uyan kural kazanır:
    ///
    /// 1. izin kapalı → `needsPermission`
    /// 2. Tam Konum kapalı → `approximateOnly`
    /// 3. `rejectsSimulated` iken taklit konum → `simulatedLocation`
    /// 4. izin henüz sorulmadı ya da kullanılabilir okuma yok → `locating`
    /// 5. iğne çevrenin dışında → `tooFar`
    /// 6. iğnenin alanı (`area`) su, orman ya da yerleşim dışı → `water`, `forest`, `remote`
    /// 7. `ready`
    ///
    /// `area`: iğnenin (kullanıcının değil) alan sınıfı. `locatingSince`: konum beklemenin başladığı an.
    public static func verdict(
        pin: Coordinate,
        fix: LocationFix?,
        access: LocationAccess,
        rejectsSimulated: Bool,
        area: AreaClass?,
        locatingSince: Date,
        at now: Date
    ) -> PlacementVerdict {
        switch access {
        case .denied:
            return .needsPermission
        case .approximate:
            return .approximateOnly
        case .notDetermined, .full:
            break
        }
        if rejectsSimulated && fix?.isSimulatedBySoftware == true {
            return .simulatedLocation
        }
        guard access == .full, isUsable(fix, at: now), let fix else {
            return .locating(slow: now.timeIntervalSince(locatingSince) >= slowLocatingAfter)
        }
        guard isWithinAllowedRadius(pin, of: fix) else { return .tooFar }
        return areaVerdict(area)
    }

    /// Düzeltmenin kararı. İğne işaretin kayıtlı yerinden 1 m'den az kaydıysa konum ve alan hiç
    /// denetlenmez (tür ve ihtiyaç her yerden düzeltilebilir); yoksa `verdict` ile aynıdır.
    public static func editVerdict(
        original: Coordinate,
        pin: Coordinate,
        fix: LocationFix?,
        access: LocationAccess,
        rejectsSimulated: Bool,
        area: AreaClass?,
        locatingSince: Date,
        at now: Date
    ) -> PlacementVerdict {
        if original.distance(to: pin) < unmovedTolerance { return .ready }
        return verdict(
            pin: pin,
            fix: fix,
            access: access,
            rejectsSimulated: rejectsSimulated,
            area: area,
            locatingSince: locatingSince,
            at: now
        )
    }
}
