import Foundation

/// Hayvanın neye ihtiyacı olduğu. Haritadaki işaretin rengi ve simgesi buradan gelir.
///
/// Ham değerler Firestore'a yazılır ve kurallarda geçer; başlık ve tanım yalnızca gösterimdir.
/// `lifetimeHours`: kimse "Hâlâ orada" demezse işaretin haritada kalacağı süre.
/// `lifetimeHours` ve `closeCost` shared/report-contract.json ve firestore.rules ile,
/// `demoteMinutes`, `needsGentleCheck` ve `allowsUnneeded` sözleşmeyle aynı olmalıdır.
public enum Need: String, CaseIterable, Identifiable, Sendable {
    case food
    case injured
    case shelter
    case babies
    case vet
    case emergency

    public var id: String { rawValue }

    /// Başlıklar sağlıklı sokak hayvanını değil, yardım ihtiyacını anlatır ("Mama / su" her kediye uyardı).
    public var title: String {
        switch self {
        case .food: "Aç ve zayıf"
        case .injured: "Yaralı / hasta"
        case .shelter: "Terk edilmiş / bakıma muhtaç"
        case .babies: "Yavrular tehlikede"
        case .vet: "Veteriner desteği"
        case .emergency: "Acil yardım"
        }
    }

    /// Lejantta başlığın altındaki tek satır: bu ihtiyaç ne zaman işaretlenir.
    public var definition: String {
        switch self {
        case .emergency: "Hayati tehlike: ağır yaralı, sıkışmış, zehirlenmiş"
        case .injured: "Yaralı, topallıyor ya da belirgin şekilde hasta"
        case .babies: "Annesiz, soğukta ya da yol kenarında yavrular"
        case .vet: "Tedavisi ya da kontrolü gereken hayvan"
        case .food: "Çok zayıf, günlerdir beslenmiyor ya da su bulamıyor"
        case .shelter: "Sahipliyken bırakılmış, çok yaşlı ya da engelli"
        }
    }

    /// SF Symbol adı.
    public var symbolName: String {
        switch self {
        case .food: "fork.knife"
        case .injured: "bandage.fill"
        case .shelter: "house.fill"
        case .babies: "teddybear.fill"
        case .vet: "stethoscope"
        case .emergency: "exclamationmark"
        }
    }

    public var lifetimeHours: Int {
        switch self {
        case .emergency: 12
        case .injured: 24
        case .babies: 72
        case .vet: 48
        case .food: 12
        case .shelter: 72
        }
    }

    public var lifetime: TimeInterval { TimeInterval(lifetimeHours) * 3600 }

    /// İşaretler üst üste bindiğinde daha yüksek öncelik üstte çizilir; hafif ihtiyaç (mama) her ağır
    /// ihtiyacın altında kalır.
    public var priority: Int {
        switch self {
        case .emergency: 6
        case .injured: 5
        case .babies: 4
        case .vet: 3
        case .shelter: 2
        case .food: 1
        }
    }

    public var isUrgent: Bool { self == .emergency }

    /// Ağır ihtiyaçlar: "Çözüldü dendi" iken solmaz, kapatma bütçesinden 2 puan düşer
    /// ve başkalarının haritasından daha geç kalkar. Yalnızca mama ("Aç ve zayıf") hafiftir:
    /// haritada küçük ve alta çizilir, başlıkta "düşük öncelikli" olarak ayrı sayılır.
    public var isSerious: Bool {
        switch self {
        case .emergency, .injured, .babies, .vet, .shelter: true
        case .food: false
        }
    }

    /// Kanıtlı "Çözüldü"nün günlük kapatma bütçesinden düşen puanı (kurallardaki `closeCost()`).
    public var closeCost: Int { isSerious ? 2 : 1 }

    /// Kanıtlı "Çözüldü"den sonra işaretin başkalarının haritasında kalacağı gündüz dakikası
    /// (bkz. `ClosingDisplay.demoteAt`).
    public var demoteMinutes: Int { isSerious ? 120 : 60 }

    /// Seçilince "Yardıma ihtiyacı var mı?" kontrolü gösterilebilir (bkz. `GentleCheck`). Sağlıklı sokak
    /// hayvanıyla en kolay karışan ihtiyaçlar; hayati olanlarda hiç sorulmaz.
    public var needsGentleCheck: Bool {
        switch self {
        case .food, .shelter: true
        case .emergency, .injured, .babies, .vet: false
        }
    }

    /// "Yardım gerekmiyor" → "Hayvan orada ama iyi görünüyor" (`ReportAction.reportUnneeded`) açık mı?
    /// Ağır ihtiyaçlarda yok: "… dendi" işareti itiraz edilene kadar "İlgileniyorum"u kapatır.
    public var allowsUnneeded: Bool {
        switch self {
        case .food: true
        case .emergency, .injured, .babies, .vet, .shelter: false
        }
    }
}
