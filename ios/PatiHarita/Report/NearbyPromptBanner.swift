import AnimalKit
import SwiftUI

/// "Yakınındaki kedi hâlâ orada mı?": yanından geçilen işaret için üst çubuğun altında kısa bir şerit. Haritayı
/// ve alttaki düğmeyi kaydırmaz, hiçbir şeyi engellemez; 20 sn sonra kendiliğinden kalkar. Düğmeler yanlışlıkla
/// basılmasın diye kısa bir beklemeden sonra açılır. Üst satıra dokununca işaretin kartı açılır.
struct NearbyPromptBanner: View {
    let prompt: MapViewModel.NearbyQuestion
    /// Kişinin işarete uzaklığı; konum yoksa `nil`.
    let distance: Double?
    /// Mamada "Yardım gerekmiyor" diyebiliyor mu (`ReportAction.reportUnneeded` açık mı).
    let showsUnneeded: Bool
    /// Başka bir eylem sürüyor: düğmeler bekler.
    let isBusy: Bool
    let onAnswer: (NearbyPrompt.Answer) -> Void
    /// Üst satır: kartı aç.
    let onOpen: () -> Void

    private struct Choice {
        /// Adımdaki yeri (`NearbyPrompt.Answer`); gizlenen düğme diğerlerinin yerini değiştirmez.
        let answer: NearbyPrompt.Answer
        let title: String
        /// Arayüz testi düğmeleri bunlarla bulur.
        let identifier: String
    }

    private var choices: [Choice] {
        switch prompt.step {
        case .presence:
            return [
                Choice(answer: .first, title: Messages.nearbyYesTitle, identifier: "nearby-yes"),
                Choice(answer: .second, title: Messages.nearbyNoTitle, identifier: "nearby-no"),
                Choice(answer: .third, title: Messages.nearbyDontKnowTitle, identifier: "nearby-dontknow"),
            ]
        case .needsHelp:
            var list = [Choice(answer: .first, title: Messages.nearbyStillNeedsTitle, identifier: "nearby-stillneeds")]
            if showsUnneeded {
                list.append(Choice(answer: .second, title: Messages.nearbyUnneededTitle, identifier: "nearby-unneeded"))
            }
            list.append(Choice(answer: .third, title: Messages.nearbyDontKnowTitle, identifier: "nearby-dontknow"))
            return list
        case .confirmGone:
            return [
                Choice(answer: .first, title: Messages.nearbyGoneTitle, identifier: "nearby-gone"),
                Choice(answer: .second, title: Messages.nearbyUnsureTitle, identifier: "nearby-unsure"),
            ]
        }
    }

    private var isEnabled: Bool {
        prompt.isArmed && !isBusy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                NeedBadge(need: prompt.report.need, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Messages.nearbyQuestion(prompt.step, report: prompt.report))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        // VoiceOver'da da soruya dokunmak kartı açar.
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onOpen() }
                        .accessibilityIdentifier("nearby-question")
                    Text(Messages.nearbyDetail(prompt.step, report: prompt.report, distance: distance))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            HStack(spacing: 8) {
                ForEach(Array(choices.enumerated()), id: \.element.identifier) { index, choice in
                    button(choice, isPrimary: index == 0)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nearby-prompt")
    }

    /// Eşit genişlikte; ilki dolu (ana düğmenin renklerinde), diğerleri sade.
    private func button(_ choice: Choice, isPrimary: Bool) -> some View {
        Button {
            onAnswer(choice.answer)
        } label: {
            Text(choice.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isPrimary ? Color(.systemBackground) : Color.primary)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(
                    isPrimary ? Color.accentColor : Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityIdentifier(choice.identifier)
    }
}

#Preview("Hâlâ orada mı?") {
    let report = ReportLifecycle.makeReport(
        id: "preview-nearby",
        species: .cat,
        need: .injured,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "someone",
        now: Date().addingTimeInterval(-30 * 60)
    )
    return NearbyPromptBanner(
        prompt: MapViewModel.NearbyQuestion(report: report, step: .presence, shownAt: Date(), isArmed: true),
        distance: 30,
        showsUnneeded: false,
        isBusy: false,
        onAnswer: { _ in },
        onOpen: {}
    )
    .padding()
}

#Preview("Yardıma ihtiyacı var mı?") {
    let report = ReportLifecycle.makeReport(
        id: "preview-nearby-food",
        species: .dog,
        need: .food,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "someone",
        now: Date().addingTimeInterval(-30 * 60)
    )
    return NearbyPromptBanner(
        prompt: MapViewModel.NearbyQuestion(report: report, step: .needsHelp, shownAt: Date(), isArmed: false),
        distance: 20,
        showsUnneeded: true,
        isBusy: false,
        onAnswer: { _ in },
        onOpen: {}
    )
    .padding()
}
