import AnimalKit
import SwiftUI

/// Haritadaki işaretlerin anlamı ve bir işaretin yaşam döngüsü.
struct LegendSheet: View {
    /// En altta kimliğin başı gösterilir: TestFlight'ta silip yeniden kurunca aynı kimlik mi, bakılabilsin.
    let userID: String?
    /// Kanıtlı "Çözüldü dendi"nin başkalarının haritasında nasıl göründüğü (`config/public.closingMode`):
    /// yalnızca `demote`da işaret başkalarından da kalkar; gece kuralı ve paydaş satırı yalnızca orada geçerli.
    let closingMode: ClosingMode

    var body: some View {
        NavigationStack {
            List {
                Section("İhtiyaçlar") {
                    ForEach(Need.allCases.sorted { $0.priority > $1.priority }) { need in
                        HStack(spacing: 12) {
                            pin(MarkerStyle(need: need, species: .cat, badge: nil, isSelected: false, seenBadge: nil))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(need.title).font(.body.weight(.medium))
                                Text("Güncellenmezse \(need.lifetimeHours) saat sonra haritadan kalkar")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Durum") {
                    row(
                        pin(MarkerStyle(need: .injured, species: .dog, badge: .helping, isSelected: false, seenBadge: nil)),
                        "Yürüyen kişi rozeti: biri ilgileniyor. 3 saat içinde çözülmezse işaret yeniden yardım bekler."
                    )
                    row(
                        pin(MarkerStyle(need: .vet, species: .cat, badge: .helpingStale, isSelected: false, seenBadge: nil)),
                        "Gri yürüyen kişi: biri 45 dakikadan uzun süredir ilgileniyor ama haber yok. Sen de gidebilirsin."
                    )
                    row(
                        pin(MarkerStyle(need: .food, species: .cat, badge: nil, isSelected: false, seenBadge: "3")),
                        "Sağ alttaki sayı: kaç kişinin bildirdiği — \"Hâlâ orada\" ya da \"Ben de gördüm\" diyen herkes eklenir."
                    )
                    Label("Soluk işaretler bir süredir kimse tarafından doğrulanmadı.", systemImage: "circle.lefthalf.filled")
                        .font(.subheadline)
                    Label("Köşedeki emoji hayvanın türünü gösterir.", systemImage: "pawprint")
                        .font(.subheadline)
                }

                Section("\"Çözüldü\" dendiğinde") {
                    row(
                        pin(MarkerStyle(need: .injured, species: .cat, badge: .closing, isSelected: false, seenBadge: nil)),
                        "? rozetli işaret: Biri 'Çözüldü' dedi ama doğrulanmadı. Hâlâ yardım bekleyenlerden sayılır."
                    )
                    // strict modda her öneri yalnızca "?" olarak görünür; soluk işaret yok.
                    if closingMode != .strict {
                        row(
                            pin(MarkerStyle(need: .food, species: .dog, badge: .closing, isSelected: false, seenBadge: nil))
                                .opacity(ReportMapView.fadingAlpha),
                            fadingText
                        )
                    }
                    row(
                        StreetDot()
                            .frame(width: 56, height: 44),
                        streetDotText
                    )
                    if closingMode == .demote {
                        Label("Gece yarısından sabah 7'ye kadar bu süre işlemez.", systemImage: "moon.zzz")
                            .font(.subheadline)
                        Label("İşareti koyan ve hayvanı gördüğünü söyleyenler, soruyu yanıtlayana kadar işareti görmeye devam eder.", systemImage: "person.2")
                            .font(.subheadline)
                    }
                }

                Section {
                    Label("Hayvan gördüm → türünü ve ihtiyacını seç.", systemImage: "1.circle.fill")
                    Label("Yakındakiler haritada görür, biri \"İlgileniyorum\" der.", systemImage: "2.circle.fill")
                    Label(resolveStepText, systemImage: "3.circle.fill")
                    Label("Hayvanı yine görürsen \"Hâlâ orada\", göremezsen \"Artık yok\" de.", systemImage: "arrow.triangle.2.circlepath")
                    Label("Biri yanlışlıkla 'Çözüldü' dediyse ve hayvanı şimdi görüyorsan \"Hâlâ yardım gerekiyor\" de.", systemImage: "exclamationmark.circle")
                } header: {
                    Text("Nasıl çalışır?")
                } footer: {
                    if let userID {
                        Text("Kimlik: \(String(userID.prefix(6)))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("uid-prefix")
                    }
                }
                .font(.subheadline)
            }
            .navigationTitle("İşaretler")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Moda göre metinler

    /// Soluk (kanıtlı) öneri: `demote`da başkalarından da kalkar, `label`da onaylanana kadar kalır.
    private var fadingText: String {
        switch closingMode {
        case .demote:
            "Soluk işaret: 'Çözüldü' dendi, kısa süre sonra haritadan kalkacak. Acil, yaralı, yavru, veteriner ve barınak işaretleri solmaz."
        case .label, .strict:
            "Soluk işaret: 'Çözüldü' dendi; işareti koyan onaylayınca ya da süresi dolunca kalkar. Acil, yaralı, yavru, veteriner ve barınak işaretleri solmaz."
        }
    }

    /// `demote` dışında başkasının önerisi haritadan kalkmaz; gri noktayı yalnızca öneriyi yapan görür.
    private var streetDotText: String {
        switch closingMode {
        case .demote:
            "Gri nokta (yakınlaşınca): 'Çözüldü' denip haritadan kalkan işaret. Hayvan hâlâ oradaysa dokunup bildir."
        case .label, .strict:
            "Gri nokta (yakınlaşınca): senin 'Çözüldü' dediğin işaret. Yanlışlıkla dediysen dokunup geri al."
        }
    }

    /// "Nasıl çalışır?" 3. adım.
    private var resolveStepText: String {
        switch closingMode {
        case .demote:
            "Yardım edince 'Çözüldü' de. İşaret senin haritandan hemen, başkalarınınkinden kısa süre sonra kalkar."
        case .label:
            "Yardım edince 'Çözüldü' de. İşaret senin haritandan hemen kalkar; başkalarında 'Çözüldü dendi' olarak görünür."
        case .strict:
            "Yardım edince 'Çözüldü' de. İşaret senin haritandan hemen kalkar; başkalarında 'doğrulanmadı' olarak görünür, işareti koyan onaylayınca kalkar."
        }
    }

    private func pin(_ style: MarkerStyle) -> some View {
        MarkerPin(style: style)
            .scaleEffect(0.8)
            .frame(width: 56, height: 60)
    }

    private func row(_ icon: some View, _ text: String) -> some View {
        HStack(spacing: 12) {
            icon
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    LegendSheet(userID: "a1b2c3d4e5f6", closingMode: .demote)
}
