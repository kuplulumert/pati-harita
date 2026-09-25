import AnimalKit
import SwiftUI

/// İşarete dokununca açılan kart. Yalnızca temel bilgiler: ihtiyaç, tür,
/// ne zaman işaretlendiği, mevcut durum ve yapılabilecek eylemler.
struct ReportCard: View {
    let report: Report
    let userID: String?
    let now: Date
    let distance: Double?
    let busyAction: ReportAction?
    let onAction: (ReportAction) -> Void
    let onDirections: () -> Void
    let onClose: () -> Void

    private var phase: ReportPhase {
        report.phase(for: userID, at: now)
    }

    private var actions: [ReportAction] {
        guard let userID else { return [] }
        return ReportLifecycle.availableActions(for: report, userID: userID, at: now)
    }

    /// "İlgileniyorum" ya da "Çözüldü" varsa büyük düğme olarak öne çıkar.
    private var primaryAction: ReportAction? {
        actions.first.flatMap { $0 == .claim || $0 == .resolve ? $0 : nil }
    }

    private var secondaryActions: [ReportAction] {
        actions.filter { $0 != primaryAction }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statusLine
            if let primaryAction {
                primaryButton(primaryAction)
            }
            secondaryRow
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            NeedBadge(need: report.need, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(report.need.title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let seen = Formatting.seenCount(report.seenCount) {
                    // "Hâlâ orada" diyen herkes sayılır; tek başına işareti koyan bildirdiyse gösterilmez.
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(report.need.color)
                            .accessibilityHidden(true)
                        Text(seen)
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
            Spacer(minLength: 0)
            CircleButton(systemImage: "xmark", accessibilityLabel: "Kapat", action: onClose)
        }
    }

    private var subtitle: String {
        var parts = [
            "\(report.species.emoji) \(report.species.title)",
            "\(Formatting.timeAgo(report.createdAt, now: now)) işaretlendi",
        ]
        if let distance {
            parts.append(Formatting.distance(meters: distance))
        }
        return parts.joined(separator: " · ")
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(phase.color)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(phase.color.opacity(0.12), in: Capsule())
    }

    private var statusText: String {
        switch phase {
        case .helpedByMe(let until):
            return "\(phase.title) · \(Formatting.remaining(until: until, now: now)) kaldı"
        case .helpedByOther(let since):
            return "\(phase.title) · \(Formatting.timeAgo(since, now: now))"
        case .waiting where report.lastSeenAt > report.createdAt:
            return "\(phase.title) · \(Formatting.timeAgo(report.lastSeenAt, now: now)) görüldü"
        default:
            return phase.title
        }
    }

    private func primaryButton(_ action: ReportAction) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 8) {
                if busyAction == action {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: action.symbolName)
                }
                Text(action.title)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(action == .resolve ? Color.green : report.need.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(busyAction != nil)
    }

    private var secondaryRow: some View {
        HStack(spacing: 8) {
            ForEach(secondaryActions) { action in
                SecondaryButton(
                    title: action.title,
                    systemImage: action.symbolName,
                    isBusy: busyAction == action
                ) {
                    onAction(action)
                }
                .disabled(busyAction != nil)
            }
            SecondaryButton(title: "Yol tarifi", systemImage: "figure.walk", isBusy: false, action: onDirections)
        }
    }
}

private struct SecondaryButton: View {
    let title: String
    let systemImage: String
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if isBusy {
                    ProgressView().frame(height: 20)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(height: 20)
                }
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

#Preview {
    var report = ReportLifecycle.makeReport(
        id: "preview",
        species: .cat,
        need: .injured,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "someone",
        now: Date().addingTimeInterval(-12 * 60)
    )
    // İki kişi daha "Hâlâ orada" dedi: kartta "3 kişi bildirdi".
    for passerBy in ["passer-by", "neighbour"] {
        report = (try? ReportLifecycle.apply(.confirmStillThere, to: report, by: passerBy, at: Date())) ?? report
    }
    return ReportCard(
        report: report,
        userID: "me",
        now: Date(),
        distance: 240,
        busyAction: nil,
        onAction: { _ in },
        onDirections: {},
        onClose: {}
    )
    .padding()
}
