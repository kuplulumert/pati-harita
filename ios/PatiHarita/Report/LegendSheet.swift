import AnimalKit
import SwiftUI

/// Haritadaki işaretlerin anlamı, bir işaretin yaşam döngüsü, kurallar ve iletişim.
struct LegendSheet: View {
    /// En altta kimliğin başı gösterilir: TestFlight'ta silip yeniden kurunca aynı kimlik mi, bakılabilsin
    /// (demo modunda `nil`: kimlik hep aynıdır).
    let userID: String?
    /// Kanıtlı "Çözüldü dendi"nin başkalarının haritasında nasıl göründüğü (`config/public.closingMode`):
    /// yalnızca `demote`da işaret başkalarından da kalkar; gece kuralı ve paydaş satırı yalnızca orada geçerli.
    let closingMode: ClosingMode
    /// Uygulamayla gelen alan verisinin sürümü ("2026-10-01"); veri yoksa `nil` (kaynak satırı gösterilmez).
    var areaDataVersion: String? = nil

    /// "Kurallar": ilk açılıştaki sayfa, yalnızca okunur.
    @State private var showsRules = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Need.allCases.sorted { $0.priority > $1.priority }) { need in
                        HStack(spacing: 12) {
                            pin(MarkerStyle(need: need, species: .cat, badge: nil, isSelected: false, seenBadge: nil))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(need.title).font(.body.weight(.medium))
                                Text(need.definition)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Güncellenmezse \(need.lifetimeHours) saat sonra haritadan kalkar")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("İhtiyaçlar")
                } footer: {
                    Text("Sağlıklı, beslenen sokak hayvanları ve mama noktaları işaretlenmez.")
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
                        pin(MarkerStyle(need: .babies, species: .cat, badge: nil, isSelected: false, seenBadge: "3")),
                        "Sağ alttaki sayı: kaç kişinin bildirdiği — 'Hâlâ orada' ya da 'Ben de gördüm' diyen herkes eklenir."
                    )
                    row(
                        pin(MarkerStyle(need: .food, species: .dog, badge: nil, isSelected: false, seenBadge: nil)),
                        "Küçük işaretler (Aç ve zayıf) düşük önceliklidir. Üstteki sayıda ayrı gösterilir, çakışınca diğerlerinin altında kalır."
                    )
                    Label("Rozetsiz soluk işaret: bir süredir kimse 'Hâlâ orada' demedi.", systemImage: "circle.lefthalf.filled")
                        .font(.subheadline)
                    Label("Köşedeki emoji hayvanın türünü gösterir.", systemImage: "pawprint")
                        .font(.subheadline)
                }

                Section("'Çözüldü' ya da 'Yardım gerekmiyor' dendiğinde") {
                    row(
                        pin(MarkerStyle(need: .injured, species: .cat, badge: .closing, isSelected: false, seenBadge: nil)),
                        "? rozeti: Biri 'Çözüldü', 'Artık yok' ya da 'Yardım gerekmiyor' dedi, henüz onaylanmadı. Kartta 'doğrulanmadı' yazıyorsa hâlâ yardım bekleyenlerden sayılır."
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
                        Label("'Çözüldü' denen işaretin kalkma süresi gece yarısından sabah 7'ye kadar durur.", systemImage: "moon.zzz")
                            .font(.subheadline)
                        Label("İşareti koyana ve hayvanı gördüğünü söyleyenlere bir soru sorulur; yanıtlayana kadar işareti görmeye devam ederler.", systemImage: "person.2")
                            .font(.subheadline)
                    }
                }

                Section("Nasıl çalışır?") {
                    Label(Messages.placementRule, systemImage: "location.circle.fill")
                    Label("Yardım gereken hayvan → türünü ve ihtiyacını seç.", systemImage: "1.circle.fill")
                    Label("Yakındakiler haritada görür, biri 'İlgileniyorum' der.", systemImage: "2.circle.fill")
                    Label(resolveStepText, systemImage: "3.circle.fill")
                    Label("Hayvanı yine görürsen 'Hâlâ orada', göremezsen 'Artık yok' de.", systemImage: "arrow.triangle.2.circlepath")
                    Label("'Aç ve zayıf' işaretindeki hayvan iyi görünüyorsa 'Yardım gerekmiyor' de.", systemImage: "hand.thumbsup")
                    Label("'Çözüldü' ya da 'Yardım gerekmiyor' denen bir hayvanı şimdi görüyorsan ve hâlâ yardıma ihtiyacı varsa 'Hâlâ yardım gerekiyor' de.", systemImage: "exclamationmark.circle")
                    Label("Yanlış işaretlediysen kimse dokunmadan, ilk 30 dakikada kartındaki 'Düzenle' ile türü, ihtiyacı ve yeri (en fazla 200 m) düzeltebilir ya da silebilirsin.", systemImage: "pencil")
                    Label("Şüpheli bir işareti kartın '⋯ Diğer' menüsünden bildirebilir ya da yalnızca kendi haritandan gizleyebilirsin.", systemImage: "flag")
                }
                .font(.subheadline)

                Section {
                    Button {
                        showsRules = true
                    } label: {
                        Label("Kurallar", systemImage: "list.bullet.rectangle")
                    }
                    .accessibilityIdentifier("legend-rules")
                    Link(destination: AppInfo.termsURL) {
                        Label("Kullanım koşulları", systemImage: "doc.text")
                    }
                    Link(destination: AppInfo.privacyURL) {
                        Label("Gizlilik politikası", systemImage: "hand.raised")
                    }
                    // Adres sahibi tarafından doldurulana kadar hiçbir yerde gösterilmez.
                    if let contactURL {
                        Link(destination: contactURL) {
                            Label("Şikayet ve iletişim: \(AppInfo.supportEmail)", systemImage: "envelope")
                        }
                    }
                } header: {
                    Text("Kurallar ve iletişim")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        // Alan ızgarası OpenStreetMap'ten türetilmiş bir veritabanıdır (ODbL): kaynak belirtilmeli.
                        if let areaDataVersion {
                            Text(Messages.areaDataCredit(dataVersion: areaDataVersion))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("area-data-credit")
                        }
                        if let userID {
                            Text("Kimlik: \(String(userID.prefix(6)))")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("uid-prefix")
                        }
                    }
                }
            }
            .navigationTitle("İşaretler")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showsRules) {
            OnboardingSheet(onAccept: nil)
        }
    }

    /// "Şikayet ve iletişim" e-postası; adres yoksa `nil`.
    private var contactURL: URL? {
        AppInfo.supportMailURL(subject: "Pati Harita", body: "")
    }

    // MARK: Moda göre metinler

    /// Soluk (kanıtlı) öneri: `demote`da başkalarından da kalkar, `label`da onaylanana kadar kalır. Yalnızca hafif
    /// ihtiyaç solar; ağır ihtiyaçlar kalkana kadar aynı renkte kalır.
    private var fadingText: String {
        switch closingMode {
        case .demote:
            "Soluk, ? rozetli işaret: bir hayvan için 'Çözüldü' ya da 'Yardım gerekmiyor' dendi, yaklaşık 1 saat içinde haritadan kalkacak. Yalnızca 'Aç ve zayıf' işaretleri solar."
        case .label, .strict:
            "Soluk, ? rozetli işaret: bir hayvan için 'Çözüldü' ya da 'Yardım gerekmiyor' dendi; işareti koyan onaylayınca ya da süresi dolunca kalkar. Yalnızca 'Aç ve zayıf' işaretleri solar."
        }
    }

    /// `demote` dışında başkasının önerisi haritadan kalkmaz; gri noktayı yalnızca öneriyi yapan görür.
    private var streetDotText: String {
        switch closingMode {
        case .demote:
            "Gri nokta (yakınlaşınca): 'Çözüldü', 'Artık yok' ya da 'Yardım gerekmiyor' denip haritadan kalkan işaret. Hayvan hâlâ yardım bekliyorsa dokunup bildir."
        case .label, .strict:
            "Gri nokta (yakınlaşınca): senin 'Çözüldü' ya da 'Yardım gerekmiyor' dediğin işaret. Yanlışlıkla dediysen dokunup geri al."
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
    LegendSheet(userID: "a1b2c3d4e5f6", closingMode: .demote, areaDataVersion: "2026-10-01")
}
