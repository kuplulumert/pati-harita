import AnimalKit
import SwiftUI

/// Haritadaki işaretin görünümünü belirleyen her şey (ikon önbelleğinin anahtarı).
struct MarkerStyle: Hashable {
    let need: Need
    let species: Species
    let isBeingHelped: Bool
    let isSelected: Bool
}

/// Harita işareti: renk + simge ihtiyacı, köşedeki emoji türü, sol üstteki rozet
/// birinin ilgilendiğini gösterir. Acil işaretler daha büyük ve haleli çizilir.
///
/// Görünümün alt-orta noktası iğnenin ucudur (`ReportMapView` işareti bu noktadan konumlar).
struct MarkerPin: View {
    let style: MarkerStyle

    private var diameter: CGFloat {
        (style.need.isUrgent ? 46 : 40) * (style.isSelected ? 1.2 : 1)
    }

    var body: some View {
        VStack(spacing: -2) {
            head
            PinTail()
                .fill(style.need.color)
                .frame(width: 14, height: 9)
        }
        .padding([.top, .horizontal], 8)
    }

    private var head: some View {
        ZStack {
            if style.need.isUrgent {
                Circle()
                    .fill(style.need.color.opacity(0.28))
                    .frame(width: diameter + 12, height: diameter + 12)
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
                .font(.system(size: 12))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.2), radius: 1)
                .offset(x: 4, y: -4)
        }
        .overlay(alignment: .topLeading) {
            if style.isBeingHelped {
                Image(systemName: "figure.walk")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.blue))
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .offset(x: -4, y: -4)
            }
        }
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

/// Yeni işaret konumunu gösteren, haritanın ortasında sabit duran iğne.
struct PlacementPin: View {
    var species: Species?
    var isLifted: Bool

    var body: some View {
        VStack(spacing: -3) {
            Circle()
                .fill(Color.accentColor)
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
                .fill(Color.accentColor)
                .frame(width: 16, height: 12)
        }
        .offset(y: isLifted ? -10 : 0)
        .animation(.spring(duration: 0.25), value: isLifted)
    }
}

#Preview("İşaretler") {
    VStack(spacing: 24) {
        HStack(alignment: .bottom) {
            ForEach(Need.allCases) { need in
                MarkerPin(style: MarkerStyle(need: need, species: .cat, isBeingHelped: false, isSelected: false))
            }
        }
        HStack(alignment: .bottom) {
            MarkerPin(style: MarkerStyle(need: .injured, species: .dog, isBeingHelped: true, isSelected: false))
            MarkerPin(style: MarkerStyle(need: .food, species: .bird, isBeingHelped: false, isSelected: true))
            PlacementPin(species: nil, isLifted: false)
            PlacementPin(species: .cat, isLifted: true)
        }
    }
    .padding()
    .background(Color(white: 0.93))
}
