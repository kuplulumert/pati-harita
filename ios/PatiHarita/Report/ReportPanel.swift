import AnimalKit
import SwiftUI

/// Yeni işaretin iki adımlık seçimi: tür → ihtiyaç. Açıklama, fotoğraf, form yok.
/// İhtiyaca dokunulduğu an işaret kaydedilir (toplam 3 dokunuş); hafif ihtiyaçta bazen önce kısa bir soru
/// ("Yardıma ihtiyacı var mı?") ızgaranın yerine gelir.
///
/// İşaret yalnızca kişinin çevresine, orman, yerleşim dışı ve su dışına konabilir (`PlacementGate`). Engel
/// varsa başlığın altında tek bir satır söyler ve ihtiyaç düğmeleri kapanır; tür, geri, "Vazgeç" ve "Ben de gördüm"
/// açık kalır. Engel ilk dokunuştan (tür seçimi) itibaren görünür.
///
/// Aynı panel düzeltmede de kullanılır ("İşareti düzelt"): iğne işaretin üstündedir, tür ve ihtiyaç yeniden
/// seçilir, ihtiyaca dokununca düzeltme kaydedilir.
struct ReportPanel: View {
    let mode: MapViewModel.Mode
    /// İğnenin yakınındaki aynı türden işaret; varsa ihtiyaçların üstünde "Ben de gördüm" önerilir. Yalnızca
    /// hayvanın yanındayken verilir (`ProximityPolicy`); bu yüzden öneri hiç kapalı görünmez.
    let duplicate: Report?
    /// Öneri bir "… dendi" işaretiyse sorulacak soru ("Burada 2 sa önce bir kedi için 'Çözüldü' dendi. …");
    /// bekleyen işarette `nil`.
    let duplicatePrompt: String?
    /// "3 yeni işaret hakkın kaldı" / "Yeni işaret hakkın saat 14.20'de açılır"; hak boldaysa `nil`.
    let allowanceText: String?
    /// İhtiyaç seçildi, önce "Yardıma ihtiyacı var mı?" soruluyor.
    let pendingReport: MapViewModel.PendingReport?
    /// Düzeltilen işaret: şimdiki türü ve ihtiyacı işaretli görünür.
    let editingReport: Report?
    /// Bir düzeltme kaydediliyor. Yalnızca düzeltme panelinde etkilidir (bkz. `isSaving`).
    let isSavingEdit: Bool
    /// Düzeltmede iğne izin verilenden (~200 m) uzağa kaydı.
    let isEditTargetTooFar: Bool
    /// Düzeltmede "İşareti sil" gösterilsin mi.
    let canRetract: Bool
    /// İğne şimdi kaydedilebilir mi; değilse neden.
    let placementVerdict: PlacementVerdict
    /// Düzeltmede iğne işaretin yerinden kaydırıldı.
    let isEditingPinMoved: Bool
    /// Kullanılabilir konum var ve iğne ondan uzakta.
    let canRecenterPin: Bool
    /// "Yanlış mı? Bize yaz" e-postası; iletişim adresi yoksa `nil` (düğme gösterilmez).
    let reportWrongURL: URL?
    let onSpecies: (Species) -> Void
    let onNeed: (Need) -> Void
    /// Öneriye dokunuldu: bekleyen işarette "Hâlâ orada", "… dendi" işaretinde itiraz.
    let onDuplicate: (Report) -> Void
    /// "Hayır, başka bir hayvan"
    let onDismissDuplicate: () -> Void
    /// "Yardıma ihtiyacı var, işaretle"
    let onConfirmPending: () -> Void
    /// "Sağlıklı görünüyor, vazgeç"
    let onCancelPending: () -> Void
    /// "İşareti sil" (onay ayrıca sorulur).
    let onRetract: () -> Void
    /// "İğneyi konumuma getir"
    let onRecenterPin: () -> Void
    /// "İğneyi eski yerine getir"
    let onRestorePin: () -> Void
    let onBack: () -> Void
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL

    /// İhtiyaç ızgarasının üstündeki tek satır: sağlıklı sokak hayvanı işaretlenmez.
    static let needGuidance = "Yalnızca yardıma ihtiyacı varsa işaretle. Sağlıklı sokak hayvanları işaretlenmez."

    private var isEditing: Bool {
        if case .editing = mode { return true }
        return false
    }

    /// Düzeltme kaydediliyor: düğmeler, geri ve "Vazgeç" dahil, kayıt bitene kadar bekler (düzeltmeden çıkıp yeni
    /// işarete başlanırsa kaydın sonucu onu bozmasın). Yeni işaret panelini etkilemez.
    private var isSaving: Bool {
        isEditing && isSavingEdit
    }

    /// İhtiyaç ızgarası mı (yeni işarette ya da düzeltmede tür seçildikten sonra), tür satırı mı?
    private var showsNeeds: Bool {
        switch mode {
        case .choosingNeed: true
        case .editing(_, let species): species != nil
        case .browsing, .choosingSpecies: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let pendingReport, case .choosingNeed = mode {
                pendingQuestion(pendingReport)
            } else if showsNeeds {
                if !isEditing, let duplicate {
                    if let duplicatePrompt {
                        closingDuplicatePrompt(duplicate, prompt: duplicatePrompt)
                    } else {
                        duplicateSuggestion(duplicate)
                    }
                }
                needSection
            } else {
                speciesRow
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
    }

    // MARK: Başlık

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            if showsNeeds {
                CircleButton(systemImage: "chevron.left", accessibilityLabel: "Geri", action: onBack)
                    .disabled(isSaving)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    if isSaving {
                        ProgressView()
                    }
                }
                // Soru açıkken iğne sabittir (harita kaydırılamaz); ipucu gösterilmez.
                if pendingReport == nil {
                    Text(isEditing ? MapViewModel.editPanelSubtitle : MapViewModel.placementPanelSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Tek ileti yeri: düzeltmede önce ~200 m sınırı, sonra kapının kararı.
                if isEditing && isEditTargetTooFar {
                    Label(ReportError.editTooFar.errorDescription ?? "Konum en fazla 200 m kaydırılabilir.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("edit-too-far")
                } else if pendingReport == nil, let message = Messages.placementMessage(placementVerdict, isEditing: isEditing) {
                    placementMessage(message)
                }
                placementButtons
                if let allowanceText {
                    // Hak az kaldığında: son işaretten sonra sınır bildirimi sürpriz olmasın.
                    Label(allowanceText, systemImage: "hourglass")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("create-allowance")
                }
                if isEditing && canRetract {
                    Button(role: .destructive, action: onRetract) {
                        Label(MapViewModel.retractButtonTitle, systemImage: "trash")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
                    .disabled(isSaving)
                    .accessibilityIdentifier("edit-retract")
                }
            }
            Spacer(minLength: 0)
            CircleButton(systemImage: "xmark", accessibilityLabel: "Vazgeç", action: onCancel)
                .disabled(isSaving)
        }
    }

    private var title: String {
        switch mode {
        case .editing:
            return MapViewModel.editPanelTitle
        case .choosingNeed(let species):
            return "\(species.emoji) Neye ihtiyacı var?"
        case .browsing, .choosingSpecies:
            return "Hangi hayvan?"
        }
    }

    // MARK: Nereye işaret konabilir

    /// Kapının tek satırı: turuncu uyarı; konum beklenirken dönen gösterge ve soluk metin.
    private func placementMessage(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if case .locating = placementVerdict {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("placement-message")
    }

    /// İletinin altındaki düğmeler (iletiyle birleşmez, ayrı ayrı basılır).
    @ViewBuilder
    private var placementButtons: some View {
        if pendingReport == nil {
            let isAreaBlock = placementVerdict.isAreaBlock
            let showsSettings = placementVerdict == .needsPermission || placementVerdict == .approximateOnly
            let showsRecenter = !isEditing && canRecenterPin && (placementVerdict == .tooFar || isAreaBlock)
            // Düzeltmede kaydırılan iğne engeldeyse eski yerine dönmek her engeli kaldırır.
            let showsRestore = isEditing && isEditingPinMoved && (placementVerdict != .ready || isEditTargetTooFar)
            let wrongURL = isAreaBlock ? reportWrongURL : nil
            if showsSettings || showsRecenter || showsRestore || wrongURL != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if showsSettings {
                        placementButton(Messages.openSettingsTitle, systemImage: "gear") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .accessibilityIdentifier("placement-settings")
                    }
                    if showsRecenter {
                        placementButton(Messages.recenterPinTitle, systemImage: "location.fill", action: onRecenterPin)
                            .accessibilityIdentifier("placement-recenter")
                    }
                    if showsRestore {
                        placementButton(Messages.restorePinTitle, systemImage: "arrow.uturn.backward", action: onRestorePin)
                            .disabled(isSaving)
                            .accessibilityIdentifier("edit-restore-pin")
                    }
                    if let wrongURL {
                        placementButton(Messages.reportWrongBlockTitle, systemImage: "envelope") {
                            openURL(wrongURL)
                        }
                        .accessibilityIdentifier("placement-report-wrong")
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func placementButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    // MARK: Tür

    private var speciesRow: some View {
        HStack(spacing: 10) {
            ForEach(Species.allCases) { species in
                let isCurrent = isEditing && editingReport?.species == species
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
                    .overlay {
                        // Düzeltmede şimdiki tür işaretli; aynısına dokunmak da ihtiyaca geçer.
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                }
                .buttonStyle(PressableStyle())
                .disabled(isSaving)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                // Arayüz testi için: etiket haritadaki işaretlerle ("Yaralı / hasta, Kedi") karışmasın.
                .accessibilityIdentifier("species-\(species.rawValue)")
            }
        }
    }

    // MARK: "Aynı hayvan mı?"

    /// Aynı hayvan zaten işaretliyse yeni işaret yerine tek dokunuşla ona "Hâlâ orada" denir.
    /// İhtiyaç düğmeleri yine yeni işaret koyar; öneri yalnızca bir kısayoldur.
    private func duplicateSuggestion(_ report: Report) -> some View {
        Button {
            onDuplicate(report)
        } label: {
            HStack(spacing: 10) {
                NeedBadge(need: report.need, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ben de gördüm")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(duplicateDetail(report))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Ben de gördüm. \(duplicateDetail(report))")
        .accessibilityIdentifier("duplicate-suggestion")
    }

    /// "Aynı hayvan mı? Yakında Yaralı / hasta · 3 kişi bildirdi"
    private func duplicateDetail(_ report: Report) -> String {
        let detail = "Aynı hayvan mı? Yakında \(report.need.title)"
        guard let seen = Formatting.seenCount(report.seenCount) else { return detail }
        return "\(detail) · \(seen)"
    }

    /// Yakında "Çözüldü dendi" bir işaret var (haritadan kalkmış olabilir): kişi hayvanın başında, aynı
    /// hayvansa tek dokunuşla itiraz eder. Değilse öneri kapanır ve ihtiyaç seçimiyle yeni işaret konur.
    private func closingDuplicatePrompt(_ report: Report, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                NeedBadge(need: report.need, size: 32)
                Text(prompt)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("duplicate-closing-prompt")
            }
            HStack(spacing: 8) {
                promptButton(MapViewModel.duplicateDisputeTitle, tint: report.need.color) {
                    onDuplicate(report)
                }
                .accessibilityIdentifier("duplicate-dispute")
                promptButton(MapViewModel.duplicateDismissTitle, tint: nil, action: onDismissDuplicate)
                    .accessibilityIdentifier("duplicate-dismiss")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// `tint` verilirse dolu (öne çıkan) düğme, yoksa sade.
    private func promptButton(_ title: String, tint: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .foregroundStyle(tint == nil ? Color.primary : Color.white)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(tint ?? Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Kaydetmeden önceki soru

    /// "Yardıma ihtiyacı var mı?": ızgaranın yerinde, iki düğme. İşaretlemeyi engellemez; öne çıkan düğme işaretler.
    private func pendingQuestion(_ pending: MapViewModel.PendingReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                NeedBadge(need: pending.need, size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pending.title)
                        .font(.headline)
                    Text(pending.message)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pending-message")
                }
            }
            VStack(spacing: 8) {
                questionButton(pending.confirmTitle, isPrimary: true, action: onConfirmPending)
                    .accessibilityIdentifier(pending.confirmIdentifier)
                questionButton(pending.cancelTitle, isPrimary: false, action: onCancelPending)
                    .accessibilityIdentifier(pending.cancelIdentifier)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Tam genişlikte. Öne çıkan düğme ana düğmenin renklerinde (ihtiyaç rengi açık yeşilde beyaz yazı okunmuyordu).
    private func questionButton(_ title: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .foregroundStyle(isPrimary ? Color(.systemBackground) : Color.primary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(
                    isPrimary ? Color.accentColor : Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: İhtiyaç

    private var needSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.needGuidance)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("need-guidance")
            needGrid
        }
    }

    /// Düzeltmede işaretin şimdiki ihtiyacı.
    private func isCurrent(_ need: Need) -> Bool {
        isEditing && editingReport?.need == need
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
                .overlay {
                    if isCurrent(.emergency) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary, lineWidth: 3)
                    }
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityAddTraits(isCurrent(.emergency) ? .isSelected : [])
            .accessibilityIdentifier("need-\(Need.emergency.rawValue)")

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
                        .overlay {
                            if isCurrent(need) {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(need.color, lineWidth: 2)
                            }
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(isCurrent(need) ? .isSelected : [])
                    .accessibilityIdentifier("need-\(need.rawValue)")
                }
            }
        }
        // Engel başlıktaki satırda söylenir; düğmeler soluk ve kapalı.
        .disabled(placementVerdict != .ready || isSaving)
        .opacity(placementVerdict != .ready ? 0.4 : (isSaving ? 0.6 : 1))
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

// MARK: Önizlemeler

private extension ReportPanel {
    /// Önizlemeler için: yalnızca değişen girdiler verilir.
    init(
        mode: MapViewModel.Mode,
        duplicate: Report? = nil,
        duplicatePrompt: String? = nil,
        allowanceText: String? = nil,
        pendingReport: MapViewModel.PendingReport? = nil,
        editingReport: Report? = nil,
        isEditTargetTooFar: Bool = false,
        canRetract: Bool = false,
        placementVerdict: PlacementVerdict = .ready,
        isEditingPinMoved: Bool = false,
        canRecenterPin: Bool = false
    ) {
        self.init(
            mode: mode,
            duplicate: duplicate,
            duplicatePrompt: duplicatePrompt,
            allowanceText: allowanceText,
            pendingReport: pendingReport,
            editingReport: editingReport,
            isSavingEdit: false,
            isEditTargetTooFar: isEditTargetTooFar,
            canRetract: canRetract,
            placementVerdict: placementVerdict,
            isEditingPinMoved: isEditingPinMoved,
            canRecenterPin: canRecenterPin,
            reportWrongURL: nil,
            onSpecies: { _ in },
            onNeed: { _ in },
            onDuplicate: { _ in },
            onDismissDuplicate: {},
            onConfirmPending: {},
            onCancelPending: {},
            onRetract: {},
            onRecenterPin: {},
            onRestorePin: {},
            onBack: {},
            onCancel: {}
        )
    }
}

#Preview("Tür seçimi") {
    ReportPanel(mode: .choosingSpecies, allowanceText: "3 yeni işaret hakkın kaldı")
        .padding()
}

#Preview("İhtiyaç seçimi") {
    ReportPanel(mode: .choosingNeed(.cat))
        .padding()
}

#Preview("Yardıma ihtiyacı var mı?") {
    ReportPanel(
        mode: .choosingNeed(.cat),
        pendingReport: MapViewModel.PendingReport(
            species: .cat,
            need: .food,
            coordinate: Coordinate(latitude: 40.99, longitude: 29.03),
            step: .gentleCheck(recentCount: 2)
        )
    )
    .padding()
}

#Preview("Çevrenin dışında") {
    ReportPanel(mode: .choosingNeed(.dog), placementVerdict: .tooFar, canRecenterPin: true)
        .padding()
}

#Preview("Konum bulunuyor") {
    ReportPanel(mode: .choosingSpecies, placementVerdict: .locating(slow: false))
        .padding()
}

#Preview("Orman") {
    ReportPanel(mode: .choosingNeed(.cat), placementVerdict: .forest, canRecenterPin: true)
        .padding()
}

#Preview("İşareti düzelt") {
    let report = ReportLifecycle.makeReport(
        id: "preview-edit",
        species: .cat,
        need: .food,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "me",
        now: Date().addingTimeInterval(-5 * 60)
    )
    return ReportPanel(
        mode: .editing(reportID: report.id, species: .cat),
        editingReport: report,
        isEditTargetTooFar: true,
        canRetract: true
    )
    .padding()
}

#Preview("Aynı hayvan mı?") {
    let nearby = ReportLifecycle.makeReport(
        id: "preview",
        species: .cat,
        need: .injured,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "someone",
        now: Date().addingTimeInterval(-30 * 60)
    )
    let seen = (try? ReportLifecycle.apply(.confirmStillThere, to: nearby, by: "passer-by", at: Date())) ?? nearby
    return ReportPanel(mode: .choosingNeed(.cat), duplicate: seen)
        .padding()
}

#Preview("Burada 'Çözüldü' dendi") {
    let now = Date()
    let nearby = ReportLifecycle.makeReport(
        id: "preview-closing",
        species: .cat,
        need: .injured,
        at: Coordinate(latitude: 40.99, longitude: 29.03),
        reporterID: "someone",
        now: now.addingTimeInterval(-3 * 3600)
    )
    let seen = (try? ReportLifecycle.apply(.confirmStillThere, to: nearby, by: "passer-by", at: now.addingTimeInterval(-150 * 60))) ?? nearby
    let closing = (try? ReportLifecycle.apply(.resolve, to: seen, by: "another", at: now.addingTimeInterval(-2 * 3600))) ?? seen
    return ReportPanel(
        mode: .choosingNeed(.cat),
        duplicate: closing,
        duplicatePrompt: Messages.duplicateClosingPrompt(closing, now: now)
    )
    .padding()
}
