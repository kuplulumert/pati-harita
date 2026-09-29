import Foundation

/// Kartta yer alabilen bir öğe: işaret eylemi ya da işaretin durumunu değiştirmeyen düğmeler.
public enum CardItem: Hashable, Sendable {
    /// `ReportLifecycle.availableActions`taki bir eylem (`expire` hiç gösterilmez).
    case action(ReportAction)
    /// "Yol tarifi": her kartta vardır.
    case directions
    /// "Düzenle": işareti koyana, `ReportLifecycle.canEdit` iken.
    case edit
    /// "Konumu paylaş" (hangi ihtiyaçlarda sunulacağını uygulama seçer).
    case shareLocation
    /// "Bu işareti bildir"
    case flag
    /// "Bu işareti gizle"
    case hide
    /// "E-postayla ayrıntı gönder"
    case mail
}

/// Kartın düzeni: en fazla bir birincil düğme, en fazla iki döşeme ve "⋯ Diğer" menüsünün üç bölümü.
/// Her öğe tam bir kez yer alır (bkz. `CardLayout.plan`).
public struct CardPlan: Equatable, Sendable {
    /// Dolu, büyük düğme: kişinin sıradaki adımı.
    public var primary: ReportAction?
    /// "⋯ Diğer"in yanındaki döşemeler (en fazla 2).
    public var tiles: [CardItem]
    /// Menünün ilk bölümü, "Hayvanı şimdi gördüysen".
    public var observe: [CardItem]
    /// Menünün ikinci bölümü: diğer eylemler.
    public var more: [CardItem]
    /// Menünün son bölümü: bildir, gizle, e-posta. İşareti koyana boş kalır.
    public var moderation: [CardItem]

    public init(
        primary: ReportAction? = nil,
        tiles: [CardItem] = [],
        observe: [CardItem] = [],
        more: [CardItem] = [],
        moderation: [CardItem] = []
    ) {
        self.primary = primary
        self.tiles = tiles
        self.observe = observe
        self.more = more
        self.moderation = moderation
    }

    /// Menüdeki bütün öğeler, bölüm sırasıyla.
    public var menuItems: [CardItem] { observe + more + moderation }
}

/// Kartta hangi öğenin nerede duracağı. Saf mantıktır: yakınlığı ve izinleri uygulama verir.
///
/// - Birincil: ilk eylem İlgileniyorum, Çözüldü, Evet, çözüldü ya da Geri al ise.
/// - Döşemeler (ilk uyan kural):
///   1. düzenlenebilir işaret: Düzenle
///   2. "… dendi": Hâlâ yardım gerekiyor (açıksa)
///   3. sen ilgileniyorsun: yakında Artık yok, uzakta Yol tarifi; ardından Konumu paylaş
///   4. biri ilgileniyor: bayat sahiplikte işareti koyana İlgilenen gelmedi; yoksa yakında Hâlâ orada,
///      uzakta Yol tarifi (yalnızca sahiplik bayatsa ya da birincil düğme varsa)
///   5. yardım bekliyor: yakında Hâlâ orada, uzakta Yol tarifi
/// - Kalan her şey "⋯ Diğer" menüsüne. Mama işaretinde "Yardım gerekmiyor" ile "Artık yok" ayrı durur.
///
/// Değişmez kural: `expire` dışındaki her açık eylem, Yol tarifi ve izin verilen Düzenle, Konumu paylaş,
/// bildir, gizle ve e-posta kartta tam bir kez yer alır.
public enum CardLayout {
    /// "Yakın": hayvana en fazla bu kadar metre ...
    public static let nearRadius: Double = 100
    /// ... konumun doğruluğu bu kadar metre ya da daha iyiyse ve konum `PlacementGate.maxFixAge`den eski değilse.
    public static let nearMaxAccuracy: Double = 50

    /// Birincil düğme olabilen eylemler. "Hâlâ yardım gerekiyor" bilerek ikincildir (ayrıca onay sorulur).
    static let primaryActions: Set<ReportAction> = [.claim, .resolve, .confirmClosing, .undoClosing]
    /// "Hayvanı şimdi gördüysen" bölümü, bu sırayla.
    static let observeOrder: [ReportAction] = [.confirmStillThere, .reportUnneeded, .reportGone]
    /// Menünün ikinci bölümü bu sırayla başlar; beklenmeyen eylemler sona eklenir.
    static let moreOrder: [CardItem] = [.action(.resolve), .action(.release), .directions, .shareLocation]

    /// Kart açılırken bir kez ölçülür; konum yoksa uygulama `false` kullanır ("uzak").
    ///
    /// `accuracy`: CoreLocation'daki gibi metre; geçersiz konumda negatif. `fixAge`: konumun yaşı (saniye).
    public static func isNear(distance: Double, accuracy: Double, fixAge: TimeInterval) -> Bool {
        (0...nearRadius).contains(distance)
            && (0...nearMaxAccuracy).contains(accuracy)
            && fixAge <= PlacementGate.maxFixAge
    }

    /// Kartın düzeni. `userID` yoksa hiçbir eylem sunulmaz; Yol tarifi yine vardır.
    ///
    /// - `isNear`: kart açılırken ölçülen yakınlık (`isNear(distance:accuracy:fixAge:)`).
    /// - `canEdit`: `ReportLifecycle.canEdit`. `canShare`: Konumu paylaş sunulsun mu.
    /// - `canFlag`: bildir ve gizle (işareti koyana hiç). `hasMail`: e-posta adresi var mı (yalnızca `canFlag` iken).
    public static func plan(
        for report: Report,
        userID: String?,
        at now: Date,
        isNear: Bool,
        canEdit: Bool,
        canShare: Bool,
        canFlag: Bool,
        hasMail: Bool
    ) -> CardPlan {
        let offered = userID.map { ReportLifecycle.availableActions(for: report, userID: $0, at: now) } ?? []
        let available = offered.filter { $0 != .expire }

        var primary: ReportAction? = nil
        if let first = available.first, primaryActions.contains(first) {
            primary = first
        }

        let tiles = pickTiles(
            for: report,
            phase: report.phase(for: userID, at: now),
            available: available,
            hasPrimary: primary != nil,
            at: now,
            isNear: isNear,
            canEdit: canEdit,
            canShare: canShare
        )

        var rest = available.filter { $0 != primary }.map(CardItem.action)
        rest.append(.directions)
        if canEdit { rest.append(.edit) }
        if canShare { rest.append(.shareLocation) }
        rest.removeAll { tiles.contains($0) }

        let observe = observeOrder.map(CardItem.action).filter { rest.contains($0) }
        let others = rest.filter { !observe.contains($0) }
        let more = moreOrder.filter { others.contains($0) } + others.filter { !moreOrder.contains($0) }

        var moderation: [CardItem] = []
        if canFlag {
            moderation = hasMail ? [.flag, .hide, .mail] : [.flag, .hide]
        }
        return CardPlan(primary: primary, tiles: tiles, observe: observe, more: more, moderation: moderation)
    }

    /// Döşemeler: yalnızca `available`daki eylemler ve izin verilen öğeler, en fazla iki.
    private static func pickTiles(
        for report: Report,
        phase: ReportPhase,
        available: [ReportAction],
        hasPrimary: Bool,
        at now: Date,
        isNear: Bool,
        canEdit: Bool,
        canShare: Bool
    ) -> [CardItem] {
        if canEdit { return [.edit] }
        switch phase {
        case .closed:
            return []
        case .closing:
            // "Evet, çözüldü" birincil satırda, itiraz bir alt satırda: yanlışlıkla "Evet"e basılmasın.
            return available.contains(.dispute) ? [.action(.dispute)] : []
        case .helpedByMe:
            let observed: CardItem = isNear && available.contains(.reportGone) ? .action(.reportGone) : .directions
            return canShare ? [observed, .shareLocation] : [observed]
        case .helpedByOther:
            // "İlgilenen gelmedi" yalnızca işareti koyana, sahiplik bayatken açıktır.
            if available.contains(.release) { return [.action(.release)] }
            if isNear && available.contains(.confirmStillThere) { return [.action(.confirmStillThere)] }
            // Biri tazece ilgileniyorsa kart uzaktaki ikinci kişiyi yola çıkmaya yöneltmez.
            return (report.isClaimStale(at: now) || hasPrimary) ? [.directions] : []
        case .waiting:
            return (isNear && available.contains(.confirmStillThere)) ? [.action(.confirmStillThere)] : [.directions]
        }
    }
}
