import Foundation

/// Hayvanın neye ihtiyacı olduğu. Haritadaki işaretin rengi ve simgesi buradan gelir.
///
/// `lifetimeHours`: kimse "Hâlâ orada" demezse işaretin haritada kalacağı süre.
/// Değerler shared/report-contract.json ve firestore.rules ile aynı olmalıdır.
public enum Need: String, CaseIterable, Identifiable, Sendable {
    case food
    case injured
    case shelter
    case babies
    case vet
    case emergency
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .food: "Mama / su"
        case .injured: "Yaralı / hasta"
        case .shelter: "Barınak ihtiyacı"
        case .babies: "Yavruları var"
        case .vet: "Veteriner desteği"
        case .emergency: "Acil yardım"
        case .other: "Diğer"
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
        case .other: "ellipsis"
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
        case .other: 24
        }
    }

    public var lifetime: TimeInterval { TimeInterval(lifetimeHours) * 3600 }

    /// İşaretler üst üste bindiğinde daha yüksek öncelik üstte çizilir.
    public var priority: Int {
        switch self {
        case .emergency: 6
        case .injured: 5
        case .babies: 4
        case .vet: 3
        case .food: 2
        case .shelter: 1
        case .other: 0
        }
    }

    public var isUrgent: Bool { self == .emergency }
}
