import AnimalKit
import SwiftUI

/// Haritadaki işaretlerin anlamı ve bir işaretin yaşam döngüsü.
struct LegendSheet: View {
    var body: some View {
        NavigationStack {
            List {
                Section("İhtiyaçlar") {
                    ForEach(Need.allCases.sorted { $0.priority > $1.priority }) { need in
                        HStack(spacing: 12) {
                            MarkerPin(style: MarkerStyle(need: need, species: .cat, isBeingHelped: false, isSelected: false))
                                .scaleEffect(0.8)
                                .frame(width: 56, height: 60)
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
                    HStack(spacing: 12) {
                        MarkerPin(style: MarkerStyle(need: .injured, species: .dog, isBeingHelped: true, isSelected: false))
                            .scaleEffect(0.8)
                            .frame(width: 56, height: 60)
                        Text("Yürüyen kişi rozeti: biri ilgileniyor. 3 saat içinde çözülmezse işaret yeniden yardım bekler.")
                            .font(.subheadline)
                    }
                    Label("Soluk işaretler bir süredir kimse tarafından doğrulanmadı.", systemImage: "circle.lefthalf.filled")
                        .font(.subheadline)
                    Label("Köşedeki emoji hayvanın türünü gösterir.", systemImage: "pawprint")
                        .font(.subheadline)
                }

                Section("Nasıl çalışır?") {
                    Label("Hayvan gördüm → türünü ve ihtiyacını seç.", systemImage: "1.circle.fill")
                    Label("Yakındakiler haritada görür, biri \"İlgileniyorum\" der.", systemImage: "2.circle.fill")
                    Label("Yardım edilince \"Çözüldü\" ile işaret kalkar.", systemImage: "3.circle.fill")
                    Label("Hayvanı yine görürsen \"Hâlâ orada\", göremezsen \"Artık yok\" de.", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.subheadline)
            }
            .navigationTitle("İşaretler")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    LegendSheet()
}
