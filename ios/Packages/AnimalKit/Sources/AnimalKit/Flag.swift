/// "Bu işareti bildir": neden sabit bir listeden seçilir, serbest metin yoktur.
///
/// `flags/{reportId}_{uid}` dokümanına yazılır; haritada hiçbir etkisi yoktur, sahibi konsoldan inceler.
/// Ham değerler shared/report-contract.json ve firestore.rules ile aynı olmalıdır.
public enum FlagReason: String, CaseIterable, Identifiable, Sendable {
    /// Burada yardım bekleyen hayvan yok.
    case fake
    /// Tehlikeli ya da şüpheli bir yer.
    case unsafe
    /// Hayvan dışında bir amaçla kullanılıyor.
    case misuse

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fake: "Burada yardım bekleyen hayvan yok (sahte işaret)"
        case .unsafe: "Tehlikeli ya da şüpheli bir yer"
        case .misuse: "Hayvan dışında bir amaçla kullanılıyor (buluşma, taciz, reklam…)"
        }
    }
}

/// Firestore koleksiyon adları (shared/report-contract.json).
public enum CollectionName {
    public static let reports = "reports"
    /// `users/{uid}`: hesap yaşı ve 24 saatlik haklar.
    public static let users = "users"
    /// `flags/{reportId}_{uid}`: yalnızca oluşturulur, kimse okuyamaz.
    public static let flags = "flags"
    /// `banned/{uid}`: yalnızca konsoldan yazılır; kişi yalnızca kendi kaydını okur.
    public static let banned = "banned"
    /// `config/public`: yalnızca konsoldan yazılan uzaktan ayarlar.
    public static let config = "config"

    /// Kişi başına işaret başına bir bildirim: kurallar doküman kimliğinin tam bu olmasını ister,
    /// böylece aynı işarete ikinci bildirim reddedilir.
    public static func flagDocumentID(reportID: String, userID: String) -> String {
        "\(reportID)_\(userID)"
    }
}
