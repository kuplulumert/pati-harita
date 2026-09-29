import AnimalKit
import SwiftUI

/// Haritadaki işaretin görünümünü belirleyen her şey (ikon önbelleğinin anahtarı).
struct MarkerStyle: Hashable {
    let need: Need
    let species: Species
    /// Sol üstteki durum rozeti; yoksa `nil`.
    let badge: MarkerBadge?
    let isSelected: Bool
    /// Sağ alttaki "kaç kişi bildirdi" rozeti (`Formatting.seenCountBadge`); tek kişi bildirdiyse `nil`.
    /// Ham sayı yerine metin tutulur: 99'dan sonrası aynı ikonu paylaşır.
    let seenBadge: String?
}

/// İşaretin sol üst köşesindeki durum rozeti.
enum MarkerBadge: Hashable, CaseIterable {
    /// Biri ilgileniyor (mavi yürüyen kişi).
    case helping
    /// Başkasının sahipliği 45 dk'yı geçti ve haber yok (gri yürüyen kişi): sen de gidebilirsin.
    case helpingStale
    /// "Çözüldü dendi" / "Artık yok dendi" ("?"): doğrulanmadı ya da birazdan kalkacak.
    case closing

    var symbolName: String {
        switch self {
        case .helping, .helpingStale: "figure.walk"
        case .closing: "questionmark"
        }
    }

    /// İkonlar açık/koyu moddan bağımsız çizilir; renkler sabittir.
    var color: Color {
        switch self {
        case .helping: .blue
        case .helpingStale: Color(red: 0.56, green: 0.56, blue: 0.58) // #8E8E93
        case .closing: Color(red: 0.2, green: 0.23, blue: 0.25) // #343A40
        }
    }
}

/// İkon önbelleğinin anahtarı: iğne ya da gri nokta.
enum MarkerIcon: Hashable {
    case pin(MarkerStyle)
    /// Başkalarının haritasından kalkan "… dendi" işareti; yalnızca sokak yakınlığında çizilir.
    case streetDot(isSelected: Bool)
}

/// Harita işareti: renk + simge ihtiyacı, köşedeki emoji türü, sol üstteki rozet
/// durumu (ilgilenen, haber vermeyen ilgilenen, "… dendi"), sağ alttaki sayı hayvanı kaç kişinin
/// bildirdiğini gösterir. Acil işaretler daha büyük ve haleli, hafif ihtiyaçlar ("Aç ve zayıf") daha küçük çizilir.
///
/// Görünümün alt-orta noktası iğnenin ucudur (`ReportMapView` işareti bu noktadan konumlar).
struct MarkerPin: View {
    let style: MarkerStyle

    /// Başın çapı (seçili değilken): acil 46, ağır ihtiyaçlar 40, hafifler 32.
    static func baseDiameter(for need: Need) -> CGFloat {
        if need.isUrgent { return 46 }
        return need.isSerious ? 40 : 32
    }

    private var diameter: CGFloat {
        Self.baseDiameter(for: style.need) * (style.isSelected ? 1.2 : 1)
    }

    /// Acil işaretin halesinin daireden her yana taşan kısmı.
    private var haloInset: CGFloat {
        style.need.isUrgent ? 6 : 0
    }

    /// Köşe rozetleri (tür, durum); küçük başta biraz küçülür ki simgeyi örtmesin.
    private var cornerBadgeSize: CGFloat {
        style.need.isSerious ? 20 : 18
    }

    var body: some View {
        VStack(spacing: -2) {
            head
            PinTail()
                .fill(style.need.color)
                .frame(width: style.need.isSerious ? 14 : 12, height: style.need.isSerious ? 9 : 8)
        }
        // Kuyruğun da üstünde çizilsin diye tüm iğneye eklenir. Kaplama yerleşimi (boyut, uç noktası)
        // değiştirmez; rozet dairenin sağ alt köşesinden biraz taşar ama kenar boşluğunun içinde kalır.
        .overlay(alignment: .top) {
            if let badge = style.seenBadge {
                seenBadge(badge)
                    .frame(width: diameter, height: diameter, alignment: .bottomTrailing)
                    .offset(x: 5, y: haloInset + 4)
            }
        }
        .padding([.top, .horizontal], 8)
    }

    private var head: some View {
        ZStack {
            if style.need.isUrgent {
                Circle()
                    .fill(style.need.color.opacity(0.28))
                    .frame(width: diameter + 2 * haloInset, height: diameter + 2 * haloInset)
            }
            Circle()
                .fill(style.need.color)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            Image(systemName: style.need.symbolName)
                .font(.system(size: diameter * 0.42, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .topTrailing) {
            Text(style.species.emoji)
                .font(.system(size: cornerBadgeSize * 0.6))
                .frame(width: cornerBadgeSize, height: cornerBadgeSize)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.2), radius: 1)
                .offset(x: 4, y: -4)
        }
        .overlay(alignment: .topLeading) {
            if let badge = style.badge {
                Image(systemName: badge.symbolName)
                    .font(.system(size: badge == .closing ? 11 : 10, weight: badge == .closing ? .heavy : .bold))
                    .foregroundStyle(.white)
                    .frame(width: cornerBadgeSize, height: cornerBadgeSize)
                    .background(Circle().fill(badge.color))
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .offset(x: -4, y: -4)
            }
        }
    }

    private func seenBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(style.need.color)
            .fixedSize()
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(.white))
            .shadow(color: .black.opacity(0.2), radius: 1)
    }
}

/// Başkalarının haritasından kalkan "… dendi" işareti: sokak yakınlığında küçük gri nokta. Yanındaki kişi
/// dokunup "Hâlâ yardım gerekiyor" diyebilsin, kapatan da "Geri al" diyebilsin diye çizilir; dokunma alanı
/// haritada genişletilir (`ReportAnnotationView.touchPadding`). Görünümün ortası koordinattır.
struct StreetDot: View {
    var isSelected = false

    var body: some View {
        Circle()
            .fill(Color(red: 0.56, green: 0.56, blue: 0.58))
            .frame(width: isSelected ? 18 : 14, height: isSelected ? 18 : 14)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 1)
            .frame(width: isSelected ? 24 : 20, height: isSelected ? 24 : 20)
    }
}

/// İğnenin sivri ucu.
struct PinTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Yeni işaret konumunu gösteren, haritanın ortasında sabit duran iğne. Buraya şimdi işaret konamıyorsa
/// (`PlacementVerdict` hazır değil) soluk ve gri çizilir.
struct PlacementPin: View {
    var species: Species?
    var isLifted: Bool
    var isBlocked: Bool = false

    private var color: Color {
        isBlocked ? Color.secondary : Color.accentColor
    }

    var body: some View {
        VStack(spacing: -3) {
            Circle()
                .fill(color)
                .frame(width: 50, height: 50)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .overlay {
                    if let species {
                        Text(species.emoji).font(.system(size: 24))
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color(.systemBackground))
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: isLifted ? 8 : 3, y: isLifted ? 6 : 2)
            PinTail()
                .fill(color)
                .frame(width: 16, height: 12)
        }
        .opacity(isBlocked ? 0.6 : 1)
        .offset(y: isLifted ? -10 : 0)
        .animation(.spring(duration: 0.25), value: isLifted)
        .animation(.easeInOut(duration: 0.2), value: isBlocked)
    }
}

#Preview("İşaretler") {
    VStack(spacing: 24) {
        HStack(alignment: .bottom) {
            ForEach(Need.allCases) { need in
                MarkerPin(style: MarkerStyle(need: need, species: .cat, badge: nil, isSelected: false, seenBadge: nil))
            }
        }
        HStack(alignment: .bottom) {
            MarkerPin(style: MarkerStyle(need: .injured, species: .dog, badge: .helping, isSelected: false, seenBadge: "3"))
            MarkerPin(style: MarkerStyle(need: .food, species: .cat, badge: nil, isSelected: true, seenBadge: "12"))
            MarkerPin(style: MarkerStyle(need: .emergency, species: .dog, badge: nil, isSelected: false, seenBadge: "99+"))
            PlacementPin(species: nil, isLifted: false)
            PlacementPin(species: .cat, isLifted: true)
            PlacementPin(species: .dog, isLifted: false, isBlocked: true)
        }
        // "… dendi": "?" rozeti; hafif ihtiyaçlar soluk; kalkınca gri nokta. Haber vermeyen ilgilenen: gri rozet.
        HStack(alignment: .bottom) {
            MarkerPin(style: MarkerStyle(need: .injured, species: .cat, badge: .closing, isSelected: false, seenBadge: "2"))
            MarkerPin(style: MarkerStyle(need: .food, species: .dog, badge: .closing, isSelected: false, seenBadge: nil))
                .opacity(0.6)
            MarkerPin(style: MarkerStyle(need: .vet, species: .dog, badge: .helpingStale, isSelected: false, seenBadge: nil))
            StreetDot()
            StreetDot(isSelected: true)
        }
    }
    .padding()
    .background(Color(white: 0.93))
}
