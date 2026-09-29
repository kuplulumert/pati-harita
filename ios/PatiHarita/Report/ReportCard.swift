import AnimalKit
import SwiftUI

/// İşarete dokununca açılan kart. Başlık ihtiyacı ve türü, bilgi satırı uzaklığı, tazeliği ve kaç kişinin
/// bildirdiğini söyler; durum bloğu yalnızca varsayılandan ("yardım bekliyor") farklı durumlarda çıkar.
/// En fazla üç düğme görünür: birincil, kart açılırken ölçülen yakınlığa göre bir döşeme (ilgilenene acil, yaralı
/// ve yavruda iki) ve "⋯ Diğer" menüsü. Hangi öğenin nerede duracağını `CardLayout.plan` seçer; her öğe tam bir
/// kez yer alır. Hüküm vermez; ne olduğunu söyler.
struct ReportCard: View {
    let report: Report
    let userID: String?
    let now: Date
    let distance: Double?
    /// "… dendi" işaretinin bu kişinin haritasındaki görünüşü; işaret `closing` değilse `nil`.
    let look: ClosingLook?
    /// Öneriyi yapana işaretin başkalarında nasıl göründüğünü söylemek için.
    let closingMode: ClosingMode
    /// Birincil düğme, döşemeler ve menü bölümleri (`MapViewModel.cardPlan`).
    let plan: CardPlan
    let busyAction: ReportAction?
    /// Menüde "E-postayla ayrıntı gönder"; iletişim adresi yoksa `nil` (planda da yoktur).
    let flagMailURL: URL?
    /// Başlığın altındaki bölüm bundan uzunsa kayar (büyük yazı boyutları); başlık hep görünür.
    let maxContentHeight: CGFloat
    let onAction: (ReportAction) -> Void
    let onEdit: () -> Void
    let onFlag: () -> Void
    let onHide: () -> Void
    let onDirections: () -> Void
    let onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static let directionsTitle = "Yol tarifi"
    static let menuTitle = "Diğer"
    static let observeSectionTitle = "Hayvanı şimdi gördüysen"
    /// Bekleyen işarette, kapatma önerisine itiraz edilen kişiye: birincil düğme neden yok.
    static let disputedHint = "Bu işaret için dediğine itiraz edildi; artık 'İlgileniyorum' ya da 'Çözüldü' diyemezsin."

    private var phase: ReportPhase {
        report.phase(for: userID, at: now)
    }

    /// Başkasının sahipliği 45 dk'yı geçti ve haber yok: işaret yeniden bekleyenlerden sayılır.
    private var isClaimStale: Bool {
        if case .helpedByOther = phase {
            return report.isClaimStale(at: now)
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            CappedScroll(maxHeight: maxContentHeight) {
                VStack(alignment: .leading, spacing: 12) {
                    if let status {
                        statusBlock(status)
                    }
                    if let primary = plan.primary {
                        primaryButton(primary)
                    }
                    actionRow
                }
            }
        }
        .padding(16)
        // Kart doğal boyunu alır; başlığın altındaki bölümün üst sınırı `maxContentHeight`.
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
    }

    // MARK: Başlık

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            NeedBadge(need: report.need, size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(Messages.cardTitle(report))
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    // Varsayılan durumda durum bloğu yok; sesli okuma yine "Yardım bekliyor" desin.
                    .accessibilityValue(phaseSummary)
                metaLine
            }
            Spacer(minLength: 0)
            CircleButton(systemImage: "xmark", accessibilityLabel: "Kapat", action: onClose)
        }
    }

    /// "140 m · az önce görüldü · 4 kişi bildirdi". Tek `Text`: arayüz testi "N kişi bildirdi"yi bu metnin
    /// etiketinde arar. Sığmazsa sayı alt satıra iner.
    private var metaLine: some View {
        let meta = Messages.cardMeta(report, distance: distance, now: now)
        return ViewThatFits(in: .horizontal) {
            Text(meta.oneLine)
                .lineLimit(1)
            Text(meta.twoLines)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    /// Başlığın sesli okunan değeri: "Yardım bekliyor", "Sen ilgileniyorsun, 2 sa 59 dk kaldı",
    /// "Çözüldü dendi, doğrulanmadı".
    private var phaseSummary: String {
        switch phase {
        case .waiting, .closed:
            return phase.title
        case .helpedByMe(let until):
            return "\(phase.title), \(Formatting.remaining(until: until, now: now)) kaldı"
        case .helpedByOther(let since):
            return isClaimStale ? "\(phase.title), haber yok" : "\(phase.title), \(Formatting.timeAgo(since, now: now))"
        case .closing:
            guard let closing = report.closing else { return phase.title }
            if let userID, closing.userID == userID {
                return "'\(Messages.verb(closing))' dedin"
            }
            return look.map { ClosingText.accessibilityValue($0, closing: closing, now: now) } ?? Messages.saidLabel(closing)
        }
    }

    // MARK: Durum

    private struct Status {
        /// Dolu nokta (sen ya da biri ilgileniyor), halka (haber yok, oylar, "… dendi"), bilgi.
        enum Marker {
            case dot
            case ring
            case info
        }

        let marker: Marker
        let color: Color
        let line1: String
        var line2: String? = nil
    }

    /// Yalnızca varsayılan dışındaki durumlarda: "Sen ilgileniyorsun · 2 sa 59 dk kaldı",
    /// "Biri ilgileniyor · 1 sa önce, haber yok", "… 'Çözüldü' dedi" (`ClosingText.cardStatus`),
    /// "2 kişi 'Artık yok' dedi".
    private var status: Status? {
        let votes = ClosingText.goneVoteLine(report)
        switch phase {
        case .waiting:
            // "İlgileniyorum" ve "Çözüldü" bu kişiye gösterilmez; nedenini bilsin.
            if let userID, report.disputed.contains(userID) {
                return Status(marker: .info, color: .gray, line1: Self.disputedHint, line2: votes)
            }
            guard let votes else { return nil }
            return Status(marker: .ring, color: .gray, line1: votes)
        case .helpedByMe(let until):
            let remaining = Formatting.remaining(until: until, now: now)
            return Status(marker: .dot, color: phase.color, line1: "\(phase.title) · \(remaining) kaldı", line2: votes)
        case .helpedByOther(let since):
            let ago = Formatting.timeAgo(since, now: now)
            if isClaimStale {
                return Status(marker: .ring, color: .gray, line1: "\(phase.title) · \(ago), haber yok", line2: votes)
            }
            return Status(marker: .dot, color: phase.color, line1: "\(phase.title) · \(ago)", line2: votes)
        case .closing:
            guard let closing = report.closing else { return nil }
            let canConfirm = userID.map { ReportLifecycle.canConfirmClosing(report, by: $0) } ?? false
            let text = ClosingText.cardStatus(
                report: report,
                closing: closing,
                viewer: userID,
                look: look,
                canConfirm: canConfirm,
                closingMode: closingMode,
                now: now
            )
            return Status(marker: .ring, color: phase.color, line1: text.line1, line2: text.line2)
        case .closed:
            return nil
        }
    }

    private func statusBlock(_ status: Status) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            statusMarker(status)
                .accessibilityHidden(true)
            statusText(status)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("report-status")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func statusMarker(_ status: Status) -> some View {
        switch status.marker {
        case .dot:
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
        case .ring:
            Circle()
                .strokeBorder(status.color, lineWidth: 1.5)
                .frame(width: 8, height: 8)
        case .info:
            Image(systemName: "info.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(status.color)
        }
    }

    /// Tek `Text`, ikinci satır soluk: arayüz testi iki satırı birlikte arar.
    private func statusText(_ status: Status) -> Text {
        guard let line2 = status.line2 else { return Text(status.line1) }
        return Text(status.line1) + Text("\n" + line2).font(.subheadline).foregroundColor(.secondary)
    }

    // MARK: Eylemler

    /// "İlgilenen gelmedi", "İlgilenmeyi bırak", "Evet, artık yok" gibi kişiye ve öneriye göre başlık.
    private func title(for action: ReportAction) -> String {
        Messages.title(for: action, on: report, userID: userID, now: now)
    }

    private func primaryColor(_ action: ReportAction) -> Color {
        switch action {
        case .resolve, .confirmClosing: Color(red: 0.13, green: 0.55, blue: 0.27)  // #218C45: beyaz yazı dışarıda da okunsun (~4.3:1)
        case .undoClosing: Color(.systemGray)
        case .claim, .release, .confirmStillThere, .reportGone, .reportUnneeded, .dispute, .expire: report.need.color
        }
    }

    private func primaryButton(_ action: ReportAction) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 8) {
                if busyAction == action {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: action.symbolName)
                        .accessibilityHidden(true)
                }
                Text(title(for: action))
                    .multilineTextAlignment(.center)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(primaryColor(action), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(busyAction != nil)
        // Arayüz testi düğmeyi başlığı yerine bununla bulur (başlık kişiye göre değişir).
        .accessibilityIdentifier("action-\(action.rawValue)")
    }

    /// Döşemeler ve "⋯ Diğer" yan yana; erişilebilirlik yazı boyutlarında tam genişlikte alt alta.
    private var actionRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(plan.tiles, id: \.self) { item in
                tile(item)
            }
            if !plan.menuItems.isEmpty {
                menu
            }
        }
    }

    @ViewBuilder
    private func tile(_ item: CardItem) -> some View {
        switch item {
        case .action(let action):
            Button {
                onAction(action)
            } label: {
                TileLabel(title: title(for: action), systemImage: action.symbolName, isBusy: busyAction == action)
            }
            .buttonStyle(PressableStyle())
            .disabled(busyAction != nil)
            .accessibilityIdentifier("action-\(action.rawValue)")
        case .directions:
            Button(action: onDirections) {
                TileLabel(title: Self.directionsTitle, systemImage: "figure.walk", isBusy: false)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("action-directions")
        case .edit:
            Button(action: onEdit) {
                TileLabel(title: MapViewModel.editButtonTitle, systemImage: "pencil", isBusy: false)
            }
            .buttonStyle(PressableStyle())
            .disabled(busyAction != nil)
            .accessibilityIdentifier("action-edit")
        case .shareLocation:
            // Gidilen yer bir yakına tek dokunuşla gönderilir.
            ShareLink(item: shareLocationText) {
                TileLabel(title: MapViewModel.shareLocationTitle, systemImage: "square.and.arrow.up", isBusy: false)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("share-location")
        case .flag, .hide, .mail:
            // `CardLayout` bunları hep menüye koyar.
            EmptyView()
        }
    }

    // MARK: "⋯ Diğer"

    /// Kartta görünmeyen her şey, üç bölümde: "Hayvanı şimdi gördüysen", diğer eylemler, bildir ve gizle.
    /// Sıra sabit: menü ekranın altında açılınca ters dönmesin.
    private var menu: some View {
        Menu {
            if !plan.observe.isEmpty {
                Section(Self.observeSectionTitle) {
                    ForEach(plan.observe, id: \.self) { item in
                        menuItem(item)
                    }
                }
            }
            if !plan.more.isEmpty {
                Section {
                    ForEach(plan.more, id: \.self) { item in
                        menuItem(item)
                    }
                }
            }
            if !plan.moderation.isEmpty {
                Section {
                    ForEach(plan.moderation, id: \.self) { item in
                        menuItem(item)
                    }
                }
            }
        } label: {
            TileLabel(title: Self.menuTitle, systemImage: "ellipsis", isBusy: false)
        }
        .menuOrder(.fixed)
        .disabled(busyAction != nil)
        .accessibilityLabel("Diğer seçenekler")
        .accessibilityHint(menuHint)
        .accessibilityIdentifier("card-menu")
    }

    /// Alt satırlı öğeler ne olacağını söyler ("Hayvan orada ama iyi görünüyor", "işaret hemen kalkar").
    @ViewBuilder
    private func menuItem(_ item: CardItem) -> some View {
        switch item {
        case .action(let action):
            Button {
                onAction(action)
            } label: {
                Label(title(for: action), systemImage: action.symbolName)
                if let subtitle = Messages.menuSubtitle(for: action, on: report, userID: userID) {
                    Text(subtitle)
                }
            }
            // "Yardım gerekmiyor" eski seçim düğmesinin kimliğini korur.
            .accessibilityIdentifier(action == .reportUnneeded ? "unneeded-fine" : "action-\(action.rawValue)")
        case .directions:
            Button(Self.directionsTitle, systemImage: "figure.walk", action: onDirections)
                .accessibilityIdentifier("action-directions")
        case .edit:
            Button(MapViewModel.editButtonTitle, systemImage: "pencil", action: onEdit)
                .accessibilityIdentifier("action-edit")
        case .shareLocation:
            ShareLink(item: shareLocationText) {
                Label(MapViewModel.shareLocationTitle, systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("share-location")
        case .flag:
            Button(MapViewModel.flagMenuTitle, systemImage: "flag", action: onFlag)
                .accessibilityIdentifier("menu-flag")
        case .hide:
            Button(MapViewModel.hideMenuTitle, systemImage: "eye.slash", action: onHide)
                .accessibilityIdentifier("menu-hide")
        case .mail:
            if let flagMailURL {
                Link(destination: flagMailURL) {
                    Label(MapViewModel.flagMailMenuTitle, systemImage: "envelope")
                }
                .accessibilityIdentifier("menu-mail")
            }
        }
    }

    private func menuTitle(for item: CardItem) -> String {
        switch item {
        case .action(let action): title(for: action)
        case .directions: Self.directionsTitle
        case .edit: MapViewModel.editButtonTitle
        case .shareLocation: MapViewModel.shareLocationTitle
        case .flag: MapViewModel.flagMenuTitle
        case .hide: MapViewModel.hideMenuTitle
        case .mail: MapViewModel.flagMailMenuTitle
        }
    }

    /// Menüde ne olduğu, açmadan: "Hâlâ orada, Artık yok, Çözüldü ve diğerleri".
    private var menuHint: String {
        let items = plan.menuItems
        let names = items.prefix(3).map { menuTitle(for: $0) }.joined(separator: ", ")
        return items.count > 3 ? "\(names) ve diğerleri" : names
    }

    /// "Konumu paylaş" ile gönderilen metin (yalnızca planda varsa gösterilir).
    private var shareLocationText: String {
        Messages.shareLocation(report.coordinate)
    }
}

/// Döşemenin görünüşü: simge üstte, başlık altta. Düğme, paylaşım bağlantısı ve "⋯ Diğer" aynı görünür.
private struct TileLabel: View {
    let title: String
    let systemImage: String
    let isBusy: Bool

    var body: some View {
        VStack(spacing: 4) {
            if isBusy {
                ProgressView().frame(height: 20)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)
                    .accessibilityHidden(true)
            }
            // Üç döşeme yan yana gelebilir ("Hâlâ yardım gerekiyor"); sığmazsa iki satır.
            Text(title)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 58)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// İçerik `maxHeight`e sığıyorsa olduğu gibi, sığmıyorsa o yükseklikte kayan bir alanda.
private struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        HeightCap(maxHeight: maxHeight) {
            ViewThatFits(in: .vertical) {
                content()
                ScrollView {
                    content()
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }
}

/// Çocuğuna en fazla `maxHeight` yükseklik önerir ve onun boyunu alır (esnek `frame(maxHeight:)` gibi
/// önerilen yüksekliğe büyümez).
private struct HeightCap: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        return child.sizeThatFits(capped(proposal))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }

    private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width, height: min(proposal.height ?? maxHeight, maxHeight))
    }
}

// MARK: Önizlemeler

private extension ReportCard {
    /// Önizlemeler için: "me" kullanıcısı, düzen `CardLayout.plan` ile.
    init(preview report: Report, now: Date, distance: Double?, look: ClosingLook? = nil, isNear: Bool = false) {
        self.init(
            report: report,
            userID: "me",
            now: now,
            distance: distance,
            look: look,
            closingMode: .demote,
            plan: CardLayout.plan(
                for: report,
                userID: "me",
                at: now,
                isNear: isNear,
                canEdit: ReportLifecycle.canEdit(report, by: "me", at: now),
                canShare: MapViewModel.shareLocationNeeds.contains(report.need),
                canFlag: report.reporterID != "me",
                hasMail: false
            ),
            busyAction: nil,
            flagMailURL: nil,
            maxContentHeight: 480,
            onAction: { _ in },
            onEdit: {},
            onFlag: {},
            onHide: {},
            onDirections: {},
            onClose: {}
        )
    }
}

#Preview("Bekliyor") {
    let now = Date()
    var report = ReportLifecycle.makeReport(
        id: "preview",
        species: .cat,
        need: .injured,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "someone",
        now: now.addingTimeInterval(-12 * 60)
    )
    // İki kişi daha "Hâlâ orada" dedi: kartta "3 kişi bildirdi".
    for passerBy in ["passer-by", "neighbour"] {
        report = (try? ReportLifecycle.apply(.confirmStillThere, to: report, by: passerBy, at: now)) ?? report
    }
    return ReportCard(preview: report, now: now, distance: 240)
        .padding()
}

#Preview("Sen ilgileniyorsun, yakında") {
    let now = Date()
    var report = ReportLifecycle.makeReport(
        id: "preview-helper",
        species: .cat,
        need: .injured,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "someone",
        now: now.addingTimeInterval(-30 * 60)
    )
    report = (try? ReportLifecycle.apply(.claim, to: report, by: "me", at: now.addingTimeInterval(-60))) ?? report
    // Döşemeler "Artık yok" ve "Konumu paylaş"; "İlgilenmeyi bırak" menüde.
    return ReportCard(preview: report, now: now, distance: 30, isNear: true)
        .padding()
}

#Preview("Aç ve zayıf, işareti koyan") {
    let now = Date()
    let report = ReportLifecycle.makeReport(
        id: "preview-food",
        species: .cat,
        need: .food,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "me",
        now: now.addingTimeInterval(-3 * 60)
    )
    // "İlgileniyorum", "Düzenle"; menüde "Hâlâ yardım lazım", "Yardım gerekmiyor", "Artık yok".
    return ReportCard(preview: report, now: now, distance: 12)
        .padding()
}

#Preview("Çözüldü dendi") {
    let now = Date()
    var report = ReportLifecycle.makeReport(
        id: "preview-closing",
        species: .dog,
        need: .injured,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "someone",
        now: now.addingTimeInterval(-90 * 60)
    )
    report = (try? ReportLifecycle.apply(.confirmStillThere, to: report, by: "passer-by", at: now.addingTimeInterval(-60 * 60))) ?? report
    // Yoldan geçen biri, bütçesi olmadan: başkalarına "doğrulanmadı".
    report = (try? ReportLifecycle.apply(.resolve, to: report, by: "another", at: now.addingTimeInterval(-20 * 60))) ?? report
    return ReportCard(preview: report, now: now, distance: 180, look: .unverified)
        .padding()
}
