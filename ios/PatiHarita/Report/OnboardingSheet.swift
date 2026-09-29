import SwiftUI

/// İlk açılıştaki kurallar: harita ne için, neyin işaretlenip neyin işaretlenmediği, güvenlik ve kötüye
/// kullanıma sıfır tolerans. `AppInfo.termsVersion` başına bir kez kabul edilir; harita arkada yüklenir ve sayfa
/// kaydırılarak kapatılamaz. Açıklama ekranındaki "Kurallar" ile yalnızca okunmak üzere yeniden açılır.
struct OnboardingSheet: View {
    /// "Kabul ediyorum, başla". `nil`: açıklama ekranından açıldı, yalnızca "Kapat" gösterilir.
    let onAccept: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    static let title = "Pati Harita'ya hoş geldin"
    static let intro = "Burası yardıma ihtiyacı olan sokak hayvanlarının haritası. Her işaret bir gönüllünün yola çıkması demek."
    static let acceptTitle = "Kabul ediyorum, başla"
    static let closeTitle = "Kapat"

    private struct Rule: Identifiable {
        let symbol: String
        let color: Color
        let text: String

        var id: String { symbol }
    }

    private static let rules: [Rule] = [
        Rule(
            symbol: "checkmark.circle.fill",
            color: .green,
            text: "İşaretle: yaralı ya da hasta, tehlikede ya da annesiz yavrular, çok zayıf ya da terk edilmiş hayvanlar."
        ),
        Rule(
            symbol: "xmark.circle.fill",
            color: .red,
            text: "İşaretleme: sağlıklı ve beslenen sokak hayvanlarını, mama noktalarını."
        ),
        // İlk "İlgileniyorum" ya da "Yol tarifi"ndeki uyarıyla aynı cümleler.
        Rule(symbol: "shield.lefthalf.filled", color: .blue, text: Messages.safetyRule),
        Rule(
            symbol: "mappin.and.ellipse",
            color: .orange,
            text: "Harita yalnızca hayvanlara yardım için. İşaretleri buluşma, işaretleşme, satış, reklam ya da yasa dışı bir amaçla kullanmak, gönüllüleri ya da hayvanları tuzağa düşürmek yasaktır. Kurallara uymayan işaretler kaldırılır ve o kimlik engellenir."
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "pawprint.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(Self.title)
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(Self.intro)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Self.rules) { rule in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: rule.symbol)
                                .font(.title3)
                                .foregroundStyle(rule.color)
                                .frame(width: 26)
                                .accessibilityHidden(true)
                            Text(rule.text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                // Bağlantılar Safari'de açılır; kabul etmek için okumak şart değil.
                Text(onAccept == nil ? Self.linksText : Self.consentText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding-links")
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 12)
        }
        // Düğme hep görünür: küçük ekranda ve büyük yazıda da kaydırmadan kabul edilebilsin.
        .safeAreaInset(edge: .bottom) {
            button
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.bar)
        }
    }

    @ViewBuilder
    private var button: some View {
        if let onAccept {
            Button(action: onAccept) {
                Text(Self.acceptTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 54)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("onboarding-accept")
        } else {
            Button {
                dismiss()
            } label: {
                Text(Self.closeTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("onboarding-close")
        }
    }

    // MARK: Bağlantılar

    /// "Devam ederek Kullanım Koşulları'nı kabul etmiş ve Gizlilik Politikası'nı okumuş olursun."
    static var consentText: AttributedString {
        var text = AttributedString("Devam ederek ")
        text += link("Kullanım Koşulları", to: AppInfo.termsURL)
        text += AttributedString("'nı kabul etmiş ve ")
        text += link("Gizlilik Politikası", to: AppInfo.privacyURL)
        text += AttributedString("'nı okumuş olursun.")
        return text
    }

    /// Yeniden açıldığında (kabul zaten verildi): yalnızca bağlantılar.
    static var linksText: AttributedString {
        var text = AttributedString("Ayrıntılar: ")
        text += link("Kullanım Koşulları", to: AppInfo.termsURL)
        text += AttributedString(" · ")
        text += link("Gizlilik Politikası", to: AppInfo.privacyURL)
        return text
    }

    /// Markdown yerine parça parça: Türkçe ek ('nı) bağlantının hemen ardından gelir.
    private static func link(_ title: String, to url: URL) -> AttributedString {
        var run = AttributedString(title)
        run.link = url
        return run
    }
}

#Preview("İlk açılış") {
    OnboardingSheet(onAccept: {})
}

#Preview("Açıklamadan") {
    OnboardingSheet(onAccept: nil)
}
