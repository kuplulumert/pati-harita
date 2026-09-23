import AnimalKit
import SwiftUI

/// Her ihtiyacın haritadaki rengi. Renkler birbirinden kolay ayrılsın diye seçildi;
/// renk körlüğü için simge de her zaman birlikte kullanılır.
extension Need {
    var color: Color {
        switch self {
        case .emergency: Color(red: 0.90, green: 0.22, blue: 0.27) // #E63946
        case .injured: Color(red: 0.95, green: 0.45, blue: 0.17) // #F3722C
        case .vet: Color(red: 0.15, green: 0.49, blue: 0.63) // #277DA1
        case .food: Color(red: 0.26, green: 0.67, blue: 0.55) // #43AA8B
        case .shelter: Color(red: 0.43, green: 0.36, blue: 0.82) // #6D5BD0
        case .babies: Color(red: 0.88, green: 0.34, blue: 0.61) // #E0569B
        case .other: Color(red: 0.42, green: 0.46, blue: 0.49) // #6C757D
        }
    }
}

extension ReportPhase {
    var title: String {
        switch self {
        case .waiting: "Yardım bekliyor"
        case .helpedByMe: "Sen ilgileniyorsun"
        case .helpedByOther: "Biri ilgileniyor"
        case .closed(.resolved): "Çözüldü"
        case .closed(.gone): "Artık orada değil"
        case .closed(.expired): "Süresi doldu"
        }
    }

    var color: Color {
        switch self {
        case .waiting: .orange
        case .helpedByMe: .green
        case .helpedByOther: .blue
        case .closed: .secondary
        }
    }

    var isBeingHelped: Bool {
        switch self {
        case .helpedByMe, .helpedByOther: true
        case .waiting, .closed: false
        }
    }
}

/// İhtiyacın renkli daire içindeki simgesi (kart, seçim paneli ve açıklama ekranında).
struct NeedBadge: View {
    let need: Need
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(need.color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: need.symbolName)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}
