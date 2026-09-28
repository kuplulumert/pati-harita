/// Hayvan türü. Bilerek kısa tutuldu: işaretleme birkaç saniye sürmeli. Şimdilik yalnızca kedi ve köpek;
/// ham değerler shared/report-contract.json ve firestore.rules ile aynı olmalıdır.
public enum Species: String, CaseIterable, Identifiable, Sendable {
    case cat
    case dog

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cat: "Kedi"
        case .dog: "Köpek"
        }
    }

    public var emoji: String {
        switch self {
        case .cat: "🐈"
        case .dog: "🐕"
        }
    }
}
