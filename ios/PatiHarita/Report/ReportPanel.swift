import AnimalKit
import SwiftUI

/// Yeni işaretin iki adımlık seçimi: tür → ihtiyaç. Açıklama, fotoğraf, form yok.
/// İhtiyaca dokunulduğu an işaret kaydedilir (toplam 3 dokunuş).
struct ReportPanel: View {
    let mode: MapViewModel.Mode
    let onSpecies: (Species) -> Void
    let onNeed: (Need) -> Void
    let onBack: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch mode {
            case .choosingNeed:
                needGrid
            case .choosingSpecies, .browsing:
                speciesRow
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if case .choosingNeed = mode {
                CircleButton(systemImage: "chevron.left", accessibilityLabel: "Geri", action: onBack)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text("İğneyi ayarlamak için haritayı kaydır")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            CircleButton(systemImage: "xmark", accessibilityLabel: "Vazgeç", action: onCancel)
        }
    }

    private var title: String {
        if case .choosingNeed(let species) = mode {
            return "\(species.emoji) Neye ihtiyacı var?"
        }
        return "Hangi hayvan?"
    }

    private var speciesRow: some View {
        HStack(spacing: 10) {
            ForEach(Species.allCases) { species in
                Button {
                    onSpecies(species)
                } label: {
                    VStack(spacing: 6) {
                        Text(species.emoji)
                            .font(.system(size: 34))
                        Text(species.title)
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    /// "Acil yardım" en üstte ve tam genişlikte; diğerleri iki sütunda.
    private var needGrid: some View {
        VStack(spacing: 10) {
            Button {
                onNeed(.emergency)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: Need.emergency.symbolName)
                        .font(.system(size: 18, weight: .heavy))
                    Text(Need.emergency.title)
                        .font(.headline)
                    Spacer(minLength: 0)
                    Text("Hayati tehlike")
                        .font(.footnote.weight(.medium))
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(Need.emergency.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableStyle())

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Need.allCases.filter { $0 != .emergency }) { need in
                    Button {
                        onNeed(need)
                    } label: {
                        HStack(spacing: 10) {
                            NeedBadge(need: need, size: 32)
                            Text(need.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 56)
                        .background(need.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

/// Dokunulduğunda hafifçe küçülen düğme.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct CircleButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("Tür seçimi") {
    ReportPanel(mode: .choosingSpecies, onSpecies: { _ in }, onNeed: { _ in }, onBack: {}, onCancel: {})
        .padding()
}

#Preview("İhtiyaç seçimi") {
    ReportPanel(mode: .choosingNeed(.cat), onSpecies: { _ in }, onNeed: { _ in }, onBack: {}, onCancel: {})
        .padding()
}
