import SwiftUI

/// Bu derleme `config/public.minBuild`den eski: kapatılamaz. Desteklenmeyen sürüm yeni işaret nedenlerini
/// yanlış gösterebilir ya da kuralların reddedeceği yazımlar yapabilir.
struct UpdateRequiredSheet: View {
    @Environment(\.openURL) private var openURL

    /// TestFlight uygulaması; yüklü değilse hiçbir şey olmaz.
    static let testFlightURL = URL(string: "itms-beta://")!

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(Messages.updateRequiredTitle)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(Messages.updateRequiredMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                openURL(Self.testFlightURL)
            } label: {
                Text("TestFlight'ı aç")
                    .font(.headline)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 54)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("update-open-testflight")
        }
        .padding(24)
    }
}

#Preview {
    UpdateRequiredSheet()
}
