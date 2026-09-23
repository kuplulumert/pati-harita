/// Hayvan türü. Bilerek kısa tutuldu: işaretleme birkaç saniye sürmeli.
public enum Species: String, CaseIterable, Identifiable, Sendable {
    case cat
    case dog
    case bird
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cat: "Kedi"
        case .dog: "Köpek"
        case .bird: "Kuş"
        case .other: "Diğer"
        }
    }

    public var emoji: String {
        switch self {
        case .cat: "🐈"
        case .dog: "🐕"
        case .bird: "🐦"
        case .other: "🐾"
        }
    }
}
