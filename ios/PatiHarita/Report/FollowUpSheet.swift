import AnimalKit
import SwiftUI

/// A7 takip sorusu: kişinin koyduğu, gördüğü ya da ilgilendiği işaret için başkası "Çözüldü" / "Artık yok" /
/// "Yardım gerekmiyor" dedi. Zaman çizelgesi gösterilir ve "Bilmiyorum" varsayılandır: tanımadığı birinin sözüyle
/// "Evet" denmesin.
/// "Bilmiyorum" (ve sayfayı kaydırıp kapatmak) hemen "yanıtlandı" sayılır; diğer yanıtlar eylem yapılınca.
struct FollowUpSheet: View {
    let followUp: MapViewModel.FollowUp
    let now: Date
    /// Başka bir eylem sürüyor: "Evet" / "Hâlâ yardım gerekiyor" o bitene kadar kapalı (yoksa yapılmadan kaybolurdu).
    let isBusy: Bool
    /// Yakınlık kapısından geçmeyen yanıtlar (`MapViewModel.followUpDisabledAnswers`): görünür, kapalı ve altında
    /// nedeni. "Bilmiyorum" hiç kapanmaz.
    var disabledAnswers: Set<MapViewModel.FollowUpAnswer> = []
    let onAnswer: (MapViewModel.FollowUpAnswer) -> Void

    /// Zaman çizelgesinin bir satırı.
    private struct Step: Hashable {
        let symbol: String
        let text: String
    }

    private var report: Report {
        followUp.report
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Text(followUp.message)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("follow-up-message")
                timeline
                VStack(spacing: 10) {
                    ForEach(followUp.options) { option in
                        optionButton(option)
                    }
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            NeedBadge(need: report.need, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.need.title)
                    .font(.headline)
                Text("\(report.species.emoji) \(report.species.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Olanlar sırasıyla: işaretlendi, (biri ilgilendi), "… dendi" ve kim dedi.
    private var steps: [Step] {
        var steps = [
            Step(symbol: "mappin.circle.fill", text: "İşaretlendi · \(Formatting.timeAgo(report.createdAt, now: now))"),
        ]
        guard let closing = report.closing else { return steps }
        if let claim = report.claim, claim.claimedAt <= closing.at {
            steps.append(Step(
                symbol: "figure.walk.circle.fill",
                text: "Biri ilgilenmeye başladı · \(Formatting.timeAgo(claim.claimedAt, now: now))"
            ))
        }
        steps.append(Step(
            symbol: "questionmark.circle.fill",
            text: "\(Messages.saidLabel(closing)) · \(Formatting.timeAgo(closing.at, now: now))"
        ))
        steps.append(Step(symbol: "person.fill", text: ClosingText.proposer(of: report, closing: closing)))
        if let votes = ClosingText.goneVotes(report) {
            steps.append(Step(symbol: "eye.slash", text: votes))
        }
        return steps
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(steps, id: \.self) { step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: step.symbol)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(step.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// "Bilmiyorum" (varsayılan) dolu, diğerleri eşit ağırlıkta sade düğmelerdir. Hayvanın yanında olmayı isteyen
    /// yanıt kapalıdır ve altında "Hayvanın yanındayken (150 m)" yazar; kimliği aynı kalır, neden değer olarak okunur.
    private func optionButton(_ option: MapViewModel.FollowUp.Option) -> some View {
        let isDefault = option.answer == .dontKnow
        let needsNear = !isDefault && disabledAnswers.contains(option.answer)
        let isDisabled = (isBusy && !isDefault) || needsNear
        return Button {
            onAnswer(option.answer)
        } label: {
            VStack(spacing: 2) {
                Text(option.title)
                    .font(.headline)
                if needsNear {
                    Text(Messages.nearOnlySubtitle)
                        .font(.footnote)
                        .accessibilityHidden(true)
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(isDefault ? Color(.systemBackground) : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(
                isDefault ? Color.accentColor : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityValue(needsNear ? Messages.nearOnlySubtitle : "")
        .accessibilityIdentifier("follow-up-\(option.answer.rawValue)")
    }
}

#Preview {
    let now = Date()
    var report = ReportLifecycle.makeReport(
        id: "preview",
        species: .cat,
        need: .injured,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "me",
        now: now.addingTimeInterval(-2 * 3600)
    )
    report = (try? ReportLifecycle.apply(.confirmStillThere, to: report, by: "passer-by", at: now.addingTimeInterval(-90 * 60))) ?? report
    report = (try? ReportLifecycle.apply(.resolve, to: report, by: "passer-by", at: now.addingTimeInterval(-20 * 60))) ?? report
    let followUp = MapViewModel.FollowUp(
        report: report,
        message: Messages.followUp(report, viewer: "me", leavesAt: nil, now: now),
        options: [
            MapViewModel.FollowUp.Option(answer: .confirm, title: Messages.confirmClosingTitle(.resolved)),
            MapViewModel.FollowUp.Option(answer: .dispute, title: "Hayır, hâlâ yardım gerekiyor"),
            MapViewModel.FollowUp.Option(answer: .dontKnow, title: "Bilmiyorum"),
        ]
    )
    return FollowUpSheet(followUp: followUp, now: now, isBusy: false) { _ in }
}

#Preview("Yardım gerekmiyor dendi") {
    let now = Date()
    var report = ReportLifecycle.makeReport(
        id: "preview-food",
        species: .cat,
        need: .food,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "me",
        now: now.addingTimeInterval(-3 * 3600)
    )
    report = (try? ReportLifecycle.apply(.confirmStillThere, to: report, by: "passer-by", at: now.addingTimeInterval(-2 * 3600))) ?? report
    report = (try? ReportLifecycle.apply(.reportUnneeded, to: report, by: "passer-by", at: now.addingTimeInterval(-20 * 60))) ?? report
    let followUp = MapViewModel.FollowUp(
        report: report,
        message: Messages.followUp(report, viewer: "me", leavesAt: nil, now: now),
        options: [
            MapViewModel.FollowUp.Option(answer: .confirm, title: Messages.confirmClosingTitle(.unneeded)),
            MapViewModel.FollowUp.Option(answer: .dispute, title: "Hayır, hâlâ yardım gerekiyor"),
            MapViewModel.FollowUp.Option(answer: .dontKnow, title: "Bilmiyorum"),
        ]
    )
    return FollowUpSheet(followUp: followUp, now: now, isBusy: false) { _ in }
}

#Preview("Gördüğün işaret, uzaktayken") {
    let now = Date()
    var report = ReportLifecycle.makeReport(
        id: "preview-far",
        species: .dog,
        need: .injured,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "someone",
        now: now.addingTimeInterval(-4 * 3600)
    )
    report = (try? ReportLifecycle.apply(.confirmStillThere, to: report, by: "me", at: now.addingTimeInterval(-3 * 3600))) ?? report
    report = (try? ReportLifecycle.apply(.resolve, to: report, by: "passer-by", at: now.addingTimeInterval(-20 * 60))) ?? report
    let followUp = MapViewModel.FollowUp(
        report: report,
        message: Messages.followUp(report, viewer: "me", leavesAt: nil, now: now),
        options: [
            MapViewModel.FollowUp.Option(answer: .dispute, title: "Evet, hâlâ yardım gerekiyor"),
            MapViewModel.FollowUp.Option(answer: .dontKnow, title: "Hayır / bilmiyorum"),
        ]
    )
    // Son bir saatte hayvanın yanında değildi: itiraz kapalı, altında nedeni.
    return FollowUpSheet(followUp: followUp, now: now, isBusy: false, disabledAnswers: [.dispute]) { _ in }
}
