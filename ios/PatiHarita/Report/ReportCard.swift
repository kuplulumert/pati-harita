import AnimalKit
import SwiftUI

/// İşarete dokununca açılan kart: ihtiyaç, tür, ne zaman işaretlendiği, mevcut durum, olgular
/// ("'İlgileniyorum' demeyen biri 'Çözüldü' dedi.") ve yapılabilecek eylemler. Hüküm vermez; ne olduğunu söyler.
struct ReportCard: View {
    let report: Report
    let userID: String?
    let now: Date
    let distance: Double?
    /// "… dendi" işaretinin bu kişinin haritasındaki görünüşü; işaret `closing` değilse `nil`.
    let look: ClosingLook?
    /// Öneriyi yapana işaretin başkalarında nasıl göründüğünü söylemek için.
    let closingMode: ClosingMode
    /// Düğmeler (`MapViewModel.cardActions`); ilki birincil olabilir. Mamada "Yardım gerekmiyor" tek düğmedir.
    let actions: [ReportAction]
    let busyAction: ReportAction?
    /// İşareti koyan kimse dokunmadan düzeltebilir: başlıkta "Düzenle".
    let canEdit: Bool
    /// Başlıktaki "⋯" menüsü (bildir, gizle); işareti koyana gösterilmez.
    let canFlag: Bool
    /// Menüde "E-postayla ayrıntı gönder"; iletişim adresi yoksa `nil`.
    let flagMailURL: URL?
    /// "Konumu paylaş" ile gönderilecek metin; yalnızca acil, yaralı ve yavru işaretlerinde.
    let shareLocationText: String?
    let onAction: (ReportAction) -> Void
    let onEdit: () -> Void
    let onFlag: () -> Void
    let onHide: () -> Void
    let onDirections: () -> Void
    let onClose: () -> Void

    /// Durum satırının altındaki bir olgu ya da ipucu.
    private struct Fact: Hashable {
        let symbol: String
        let text: String
        /// Ne yapılabileceğini söyler; olgudan soluk yazılır.
        var isHint = false
    }

    private var phase: ReportPhase {
        report.phase(for: userID, at: now)
    }

    /// İlk eylem İlgileniyorum, Çözüldü, Evet, çözüldü ya da Geri al ise büyük düğme olarak öne çıkar.
    /// "Hâlâ yardım gerekiyor" bilerek ikincildir (ayrıca onay sorulur): yanlış itirazlar azalsın.
    /// "Yardım gerekmiyor" da ikincildir: önce ne görüldüğü sorulur.
    private var primaryAction: ReportAction? {
        guard let first = actions.first else { return nil }
        switch first {
        case .claim, .resolve, .confirmClosing, .undoClosing:
            return first
        case .release, .confirmStillThere, .reportGone, .reportUnneeded, .dispute, .expire:
            return nil
        }
    }

    private var secondaryActions: [ReportAction] {
        actions.filter { $0 != primaryAction }
    }

    /// Başkasının sahipliği 45 dk'yı geçti ve haber yok: işaret yeniden bekleyenlerden sayılır.
    private var isClaimStale: Bool {
        if case .helpedByOther = phase {
            return report.isClaimStale(at: now)
        }
        return false
    }

    var body: some View {
        let facts = self.facts
        VStack(alignment: .leading, spacing: 14) {
            header
            statusLine
            if !facts.isEmpty {
                factList(facts)
            }
            if let primaryAction {
                primaryButton(primaryAction)
            }
            secondaryRow
            safetyLine
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            NeedBadge(need: report.need, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(report.need.title)
                    .font(.title3.weight(.semibold))
                // İki ayrı satır: tek metin " · " ile kaydırılınca satır sonunda "·", alt satırda yalnızca uzaklık kalıyordu.
                Group {
                    Text(speciesLine)
                    Text("\(Formatting.timeAgo(report.createdAt, now: now)) işaretlendi")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let seen = Formatting.seenCount(report.seenCount) {
                    // "Hâlâ orada" diyen herkes sayılır; tek başına işareti koyan bildirdiyse gösterilmez.
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(report.need.color)
                            .accessibilityHidden(true)
                        Text(seen)
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
            Spacer(minLength: 0)
            if canEdit {
                editButton
            }
            if canFlag {
                cardMenu
            }
            CircleButton(systemImage: "xmark", accessibilityLabel: "Kapat", action: onClose)
        }
    }

    /// "Düzenle": yalnızca işareti koyana, kimse dokunmadan ve ilk 30 dakikada. Eylem satırı zaten dolu
    /// olduğundan başlıkta küçük bir düğmedir.
    private var editButton: some View {
        Button(action: onEdit) {
            Label(MapViewModel.editButtonTitle, systemImage: "pencil")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busyAction != nil)
        .accessibilityIdentifier("action-edit")
    }

    /// "⋯": bildir, gizle ve (adres varsa) e-postayla ayrıntı. Birincil eylem değildir; bilerek küçük.
    private var cardMenu: some View {
        Menu {
            Button(MapViewModel.flagMenuTitle, systemImage: "flag", action: onFlag)
                .accessibilityIdentifier("menu-flag")
            Button(MapViewModel.hideMenuTitle, systemImage: "eye.slash", action: onHide)
                .accessibilityIdentifier("menu-hide")
            if let flagMailURL {
                Link(destination: flagMailURL) {
                    Label(MapViewModel.flagMailMenuTitle, systemImage: "envelope")
                }
                .accessibilityIdentifier("menu-mail")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .accessibilityLabel("İşaret seçenekleri")
        .accessibilityIdentifier("card-menu")
    }

    /// "🐈 Kedi · 140 m" (konum yoksa yalnızca tür).
    private var speciesLine: String {
        let species = "\(report.species.emoji) \(report.species.title)"
        guard let distance else { return species }
        return "\(species) · \(Formatting.distance(meters: distance))"
    }

    // MARK: Durum

    private var statusColor: Color {
        isClaimStale ? .gray : phase.color
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .accessibilityIdentifier("report-status")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusText: String {
        switch phase {
        case .waiting:
            guard report.lastSeenAt > report.createdAt else { return phase.title }
            return "\(phase.title) · \(Formatting.timeAgo(report.lastSeenAt, now: now)) görüldü"
        case .helpedByMe(let until):
            return "\(phase.title) · \(Formatting.remaining(until: until, now: now)) kaldı"
        case .helpedByOther(let since):
            // 45 dk'dan sonra ayrıntısı olgu satırında ("Biri 1 sa önce ilgilenmeye başladı, …").
            if isClaimStale {
                return "\(phase.title) · haber yok"
            }
            return "\(phase.title) · \(Formatting.timeAgo(since, now: now))"
        case .closing:
            guard let closing = report.closing else { return phase.title }
            return ClosingText.status(of: closing, viewer: userID, look: look, now: now)
        case .closed:
            return phase.title
        }
    }

    // MARK: Olgular

    private var facts: [Fact] {
        var facts: [Fact] = []
        switch phase {
        case .closing(_, _, let byMe, _):
            guard let closing = report.closing else { break }
            if byMe {
                if let others = othersText(closing) {
                    facts.append(Fact(symbol: "person.2.fill", text: others))
                }
            } else {
                facts.append(Fact(symbol: "person.fill", text: ClosingText.proposer(of: report, closing: closing)))
            }
            if let votes = ClosingText.goneVotes(report) {
                facts.append(Fact(symbol: "eye.slash", text: votes))
            }
            if !byMe, let hint = closingHint {
                facts.append(Fact(symbol: "info.circle", text: hint, isHint: true))
            }
        case .helpedByOther(let since):
            if isClaimStale {
                let started = Formatting.timeAgo(since, now: now)
                facts.append(Fact(
                    symbol: "clock.badge.questionmark",
                    text: "Biri \(started) ilgilenmeye başladı, o zamandan beri haber yok. Sen de gidebilirsin."
                ))
            }
            facts += waitingFacts
        case .waiting, .helpedByMe:
            facts += waitingFacts
        case .closed:
            break
        }
        return facts
    }

    /// Bekleyen işarette: "Artık yok" oyları ve önceki itirazlar.
    private var waitingFacts: [Fact] {
        var facts: [Fact] = []
        if let votes = ClosingText.goneVotes(report) {
            facts.append(Fact(symbol: "eye.slash", text: votes))
        }
        if !report.disputed.isEmpty {
            let count = report.disputed.count
            facts.append(Fact(
                symbol: "arrow.uturn.backward.circle",
                text: count == 1
                    ? "Daha önce 'Hâlâ yardım gerekiyor' diye itiraz edildi."
                    : "Daha önce \(count) kez 'Hâlâ yardım gerekiyor' diye itiraz edildi."
            ))
        }
        // "İlgileniyorum" ve "Çözüldü" bu kişiye gösterilmez; nedenini bilsin.
        if let userID, report.disputed.contains(userID) {
            facts.append(Fact(
                symbol: "info.circle",
                text: "Bu işaret için dediğine itiraz edildi; artık 'İlgileniyorum' ya da 'Çözüldü' diyemezsin.",
                isHint: true
            ))
        }
        return facts
    }

    /// Başkasının "… dendi" önerisinde ne yapılabileceği; görünüşe göre.
    private var closingHint: String? {
        guard let look else { return nil }
        let canDispute = userID.map { ReportLifecycle.canDispute(report, by: $0) } ?? false
        let alreadyObjected = userID.map { report.objectors.contains($0) } ?? false
        let objected: String? = alreadyObjected ? "Bu işarete daha önce itiraz ettin." : nil
        switch look {
        case .unverified:
            let counted = "Doğrulanmadığı için hâlâ yardım bekleyenler arasında sayılıyor."
            return canDispute ? "\(counted) Hayvanı şimdi gördüysen ve hâlâ yardıma ihtiyacı varsa bildir." : counted
        case .fading:
            return canDispute ? "Hayvanı görürsen ve hâlâ yardıma ihtiyacı varsa bildir." : objected
        case .hidden:
            return canDispute ? "Hayvanı şimdi gördüysen ve hâlâ yardıma ihtiyacı varsa bildir." : objected
        }
    }

    /// Öneriyi yapana: işaret başkalarının haritasında ne durumda (kanıtlılığa ve moda göre).
    private func othersText(_ closing: Closing) -> String? {
        guard let others = ClosingDisplay.look(of: report, mode: closingMode, viewer: nil, answered: true, at: now) else {
            return nil
        }
        // İşareti koyan önerdiyse onu hayvanı gören başka biri onaylar.
        let confirmer = closing.userID == report.reporterID ? "hayvanı gören başka biri" : "işareti koyan"
        switch others {
        case .unverified:
            return "Başkalarına 'doğrulanmadı' olarak görünüyor; \(confirmer) onaylayınca ya da süresi dolunca kalkar."
        case .fading(let leavesAt):
            guard let leavesAt, leavesAt > now else {
                return "Başkalarına '\(Messages.saidLabel(closing))' olarak görünüyor; \(confirmer) onaylayınca ya da süresi dolunca kalkar."
            }
            return "Başkalarının haritasından kalkış: \(Formatting.clock(leavesAt, now: now))"
        case .hidden:
            return "Başkalarının haritasından da kalktı."
        }
    }

    private func factList(_ facts: [Fact]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(facts, id: \.self) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: fact.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(fact.text)
                        .font(.footnote)
                        .foregroundStyle(fact.isHint ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Eylemler

    /// "İlgilenen gelmedi", "Evet, artık yok" gibi kişiye ve öneriye göre başlık.
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
                }
                Text(title(for: action))
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(primaryColor(action), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(busyAction != nil)
        // Arayüz testi düğmeyi başlığı yerine bununla bulur (başlık kişiye göre değişir).
        .accessibilityIdentifier("action-\(action.rawValue)")
    }

    private var secondaryRow: some View {
        HStack(spacing: 8) {
            ForEach(secondaryActions) { action in
                SecondaryButton(
                    title: title(for: action),
                    systemImage: action.symbolName,
                    identifier: "action-\(action.rawValue)",
                    isBusy: busyAction == action
                ) {
                    onAction(action)
                }
                .disabled(busyAction != nil)
            }
            SecondaryButton(
                title: "Yol tarifi",
                systemImage: "figure.walk",
                identifier: "action-directions",
                isBusy: false,
                action: onDirections
            )
        }
    }

    /// Sahte ya da tuzak işaretlere karşı (işaret 7 güne kadar kalabilir): küçük ve ikincil. Acil, yaralı ve yavru
    /// kartlarında gidilen yer bir yakına tek dokunuşla gönderilebilir.
    private var safetyLine: some View {
        HStack(alignment: .center, spacing: 8) {
            Label("Yalnız gitme, kimseyle tartışmaya girme, özel mülke girme.", systemImage: "shield.lefthalf.filled")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let shareLocationText {
                ShareLink(item: shareLocationText) {
                    Label(MapViewModel.shareLocationTitle, systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .fixedSize()
                .accessibilityIdentifier("share-location")
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct SecondaryButton: View {
    let title: String
    let systemImage: String
    /// Arayüz testi düğmeyi başlığı yerine bununla bulur (başlık kişiye göre değişir).
    let identifier: String
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if isBusy {
                    ProgressView().frame(height: 20)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(height: 20)
                }
                // Dört düğme yan yana gelebilir ("İlgilenen gelmedi"); sığmazsa iki satır.
                Text(title)
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier(identifier)
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
    return ReportCard(
        report: report,
        userID: "me",
        now: now,
        distance: 240,
        look: nil,
        closingMode: .demote,
        actions: MapViewModel.cardActions(for: report, userID: "me", at: now),
        busyAction: nil,
        canEdit: false,
        canFlag: true,
        flagMailURL: nil,
        shareLocationText: Messages.shareLocation(report.coordinate),
        onAction: { _ in },
        onEdit: {},
        onFlag: {},
        onHide: {},
        onDirections: {},
        onClose: {}
    )
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
    // "Hâlâ yardım lazım", "Yardım gerekmiyor" ve başlıkta "Düzenle".
    return ReportCard(
        report: report,
        userID: "me",
        now: now,
        distance: 12,
        look: nil,
        closingMode: .demote,
        actions: MapViewModel.cardActions(for: report, userID: "me", at: now),
        busyAction: nil,
        canEdit: ReportLifecycle.canEdit(report, by: "me", at: now),
        canFlag: false,
        flagMailURL: nil,
        shareLocationText: nil,
        onAction: { _ in },
        onEdit: {},
        onFlag: {},
        onHide: {},
        onDirections: {},
        onClose: {}
    )
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
    return ReportCard(
        report: report,
        userID: "me",
        now: now,
        distance: 180,
        look: .unverified,
        closingMode: .demote,
        actions: MapViewModel.cardActions(for: report, userID: "me", at: now),
        busyAction: nil,
        canEdit: false,
        canFlag: true,
        flagMailURL: nil,
        shareLocationText: Messages.shareLocation(report.coordinate),
        onAction: { _ in },
        onEdit: {},
        onFlag: {},
        onHide: {},
        onDirections: {},
        onClose: {}
    )
    .padding()
}
