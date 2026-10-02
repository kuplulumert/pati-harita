import AnimalKit
import SwiftUI

/// Uygulamanın tek ana ekranı: tam ekran harita.
struct MapScreen: View {
    @State private var viewModel: MapViewModel
    @State private var bottomPanelHeight: CGFloat = 0
    @State private var showsLegend = false
    /// Ekranda olan takip sorusunun kimliği (bkz. `followUpBinding`).
    @State private var presentedFollowUpID: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: MapViewModel(environment: environment))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                map(safeArea: proxy.safeAreaInsets)
                    .ignoresSafeArea()
                    // Yardıma giderken (gece ya da bu cihazda ilk kez); "Devam et" bekleyen işi (İlgileniyorum ya da
                    // yol tarifi) yapar.
                    .alert(
                        MapViewModel.reminderTitle(viewModel.nightReminder?.kind ?? .night),
                        isPresented: Binding(
                            get: { viewModel.nightReminder != nil },
                            set: { if !$0 { viewModel.dismissNightReminder() } }
                        ),
                        presenting: viewModel.nightReminder
                    ) { reminder in
                        Button(MapViewModel.nightReminderContinueTitle) {
                            if let url = viewModel.continueAfterNightReminder(reminder) { openURL(url) }
                        }
                    } message: { reminder in
                        Text(MapViewModel.reminderMessage(reminder.kind))
                    }

                if viewModel.isPlacing {
                    placementPin
                }

                VStack(spacing: 10) {
                    topBar
                        // Takip sorusu ve açıklama sayfasından ayrı bir görünüme bağlı (bkz. `followUpBinding`).
                        .sheet(item: blockingSheet) { sheet in
                            switch sheet {
                            case .update:
                                UpdateRequiredSheet()
                                    .interactiveDismissDisabled()
                            case .onboarding:
                                OnboardingSheet(onAccept: { viewModel.acceptTerms() })
                                    .interactiveDismissDisabled()
                            }
                        }
                    nearbyBanner
                    Spacer(minLength: 0)
                    if let toast = viewModel.toast {
                        ToastView(toast: toast) { viewModel.undo(toast) }
                            // Apple Haritalar yazısı ve "Yasal" bağlantısı alt panelin hemen üstünde; bildirim onu örtmesin.
                            .padding(.bottom, 24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    // Kartın gövdesi ekranın en fazla %60'ı kadar; büyük yazıda kayar.
                    bottomPanel(maxCardContentHeight: max(proxy.size.height * 0.6, 200))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            // Harita dolgusu da 0,25 sn'de değişir; iğne onunla birlikte kaysın.
                            withAnimation(.easeInOut(duration: 0.25)) { bottomPanelHeight = height }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                // Konum izni kapalıyken "Yardım gereken hayvan": işaret yalnızca konumun çevresine konabilir.
                .alert(
                    Messages.locationAlertTitle,
                    isPresented: Binding(
                        get: { viewModel.locationAlert },
                        set: { if !$0 { viewModel.dismissLocationAlert() } }
                    )
                ) {
                    Button(Messages.openSettingsTitle) {
                        viewModel.dismissLocationAlert()
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    Button(Messages.locationAlertCancelTitle, role: .cancel) { viewModel.dismissLocationAlert() }
                } message: {
                    Text(Messages.locationAlertMessage)
                }
            }
            // Açıklama sayfasıyla aynı görünüme bağlanmasın diye burada (iki `.sheet` bir arada sorun çıkarabiliyor).
            .sheet(item: followUpBinding) { followUp in
                FollowUpSheet(
                    followUp: followUp,
                    now: viewModel.now,
                    isBusy: viewModel.busyAction != nil,
                    // Hayvanın yanında değilken itiraz kapalı (işareti koyanınki hariç).
                    disabledAnswers: viewModel.followUpDisabledAnswers(followUp)
                ) { answer in
                    viewModel.answerFollowUp(answer)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .onAppear { presentedFollowUpID = followUp.id }
            }
            // "⋯ Diğer" → "Bu işareti bildir": neden sabit listeden seçilir, serbest metin yok. Onayların hepsinde
            // düğmeler, soru açıldığı andaki işaretle çalışır (`presenting`).
            .confirmationDialog(
                MapViewModel.flagQuestion,
                isPresented: Binding(
                    get: { viewModel.flagCandidate != nil },
                    set: { if !$0 { viewModel.cancelFlag() } }
                ),
                titleVisibility: .visible,
                presenting: viewModel.flagCandidate
            ) { report in
                ForEach(FlagReason.allCases) { reason in
                    Button(reason.title) { viewModel.flag(report, reason: reason) }
                        .accessibilityIdentifier("flag-\(reason.rawValue)")
                }
                Button(MapViewModel.flagCancelTitle, role: .cancel) { viewModel.cancelFlag() }
            } message: { _ in
                Text(MapViewModel.flagMessage)
            }
        }
        .animation(.snappy(duration: 0.3), value: viewModel.mode)
        .animation(.snappy(duration: 0.3), value: viewModel.selectedReportID)
        .animation(.snappy(duration: 0.3), value: viewModel.duplicateCandidateID)
        .animation(.snappy(duration: 0.3), value: viewModel.pendingReport)
        .animation(.snappy(duration: 0.3), value: viewModel.toast)
        .animation(.snappy(duration: 0.3), value: viewModel.nearbyPrompt)
        .sensoryFeedback(.success, trigger: viewModel.reportsCreated)
        // Engellenen dokunuş ya da iğne engele girdi.
        .sensoryFeedback(.warning, trigger: viewModel.blockedFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.nearbyPromptsShown)
        .sheet(isPresented: $showsLegend) {
            LegendSheet(
                userID: viewModel.environment.backend == .demo ? nil : viewModel.userID,
                closingMode: viewModel.closingMode,
                areaDataVersion: viewModel.environment.areaClassifier.dataVersion
            )
                .presentationDetents([.medium, .large])
        }
        // "Hâlâ yardım gerekiyor" onayı. `presenting`: düğme, soru açıldığı andaki işaretle çalışır.
        .confirmationDialog(
            MapViewModel.disputeQuestion,
            isPresented: Binding(
                get: { viewModel.disputeCandidate != nil },
                set: { if !$0 { viewModel.cancelDispute() } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.disputeCandidate
        ) { report in
            Button(MapViewModel.disputeConfirmTitle) { viewModel.confirmDispute(report) }
            Button(MapViewModel.disputeCancelTitle, role: .cancel) { viewModel.cancelDispute() }
        }
        // Düzeltme panelindeki "İşareti sil".
        .confirmationDialog(
            MapViewModel.retractQuestion,
            isPresented: Binding(
                get: { viewModel.retractCandidate != nil },
                set: { if !$0 { viewModel.cancelRetract() } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.retractCandidate
        ) { report in
            Button(MapViewModel.retractConfirmTitle, role: .destructive) { viewModel.confirmRetract(report) }
            Button(MapViewModel.retractCancelTitle, role: .cancel) { viewModel.cancelRetract() }
        }
        .task { await viewModel.run() }
        // Öne gelince takip edilen işaretler (en fazla 10 dk'da bir) yeniden okunur; arka plana geçince
        // "Hâlâ orada mı?" kesilir.
        .onChange(of: scenePhase) { _, phase in
            viewModel.scenePhaseChanged(isActive: phase == .active)
        }
        // Açıklama sayfasının arkasındaki "Hâlâ orada mı?" şeridine dokunulamaz: sayfa açıkken soru sorulmaz.
        .onChange(of: showsLegend) { _, shown in
            viewModel.legendPresented(shown)
        }
        // `initial`: konum ekran ilk çizilmeden gelmişse de (izin önceden verilmişken olur) kullanıcının
        // çevresine gidilsin; yoksa harita varsayılan şehir merkezinde kalıyor ve oraya abone oluyordu.
        .onChange(of: viewModel.location.coordinate, initial: true) {
            viewModel.userLocationChanged()
        }
    }

    /// Kaydırarak kapatılamayan sayfalar. Önce güncelleme (desteklenmeyen sürüm hiçbir şey yazmamalı), sonra ilk
    /// açılıştaki kurallar; harita arkada yüklenir.
    private enum BlockingSheet: String, Identifiable {
        case update
        case onboarding

        var id: String { rawValue }
    }

    private var blockingSheet: Binding<BlockingSheet?> {
        Binding(
            get: {
                if viewModel.requiresUpdate { return .update }
                if viewModel.needsOnboarding { return .onboarding }
                return nil
            },
            // Yalnızca durum değişince kapanır ("Kabul ediyorum, başla" ya da yeni `minBuild`).
            set: { _ in }
        )
    }

    /// Takip sorusu sayfası. Kullanıcı sayfayı kaydırıp kapatınca "Bilmiyorum" sayılır. Yanıt verilince
    /// sıradaki soru hemen gelebilir; o sırada gelen `nil`, henüz gösterilmemiş sıradakini yanıtlamasın.
    private var followUpBinding: Binding<MapViewModel.FollowUp?> {
        Binding(
            // Açıklama sayfası, kurallar ya da güncelleme sayfası, onay ya da seçim açıkken ikinci bir sayfa açılamaz:
            // SwiftUI onu atlar ve `followUp` takılı kalıp sonraki soruları da engellerdi. Onlar kapanınca gösterilir.
            get: {
                let blocked = showsLegend || viewModel.isShowingPrompt
                    || viewModel.needsOnboarding || viewModel.requiresUpdate
                return blocked ? nil : viewModel.followUp
            },
            set: { newValue in
                guard newValue == nil, let shown = presentedFollowUpID, viewModel.followUp?.id == shown else { return }
                viewModel.dismissFollowUp()
            }
        )
    }

    // MARK: Harita

    private func map(safeArea: EdgeInsets) -> some View {
        ReportMapView(
            // Düzeltilen işaret yerine ortadaki iğne gösterilir (iki iğne üst üste binmesin).
            reports: viewModel.visibleReports.filter { $0.id != viewModel.editingReportID },
            streetDots: viewModel.streetDotReports,
            closingLooks: viewModel.closingLooks,
            selectedID: viewModel.selectedReportID,
            userID: viewModel.userID,
            now: viewModel.now,
            cameraRequest: viewModel.cameraRequest,
            insets: UIEdgeInsets(
                top: safeArea.top,
                left: 0,
                bottom: safeArea.bottom + bottomPanelHeight + 8,
                right: 0
            ),
            placementArea: viewModel.placementArea,
            onCameraWillMove: { viewModel.cameraWillMove() },
            onCameraMove: { viewModel.cameraMoved(to: $0) },
            onCameraIdle: { viewModel.cameraBecameIdle(center: $0, visibleRadius: $1) },
            onMarkerTap: { viewModel.markerTapped($0) },
            onMapTap: { viewModel.mapTapped() },
            onLongPress: { viewModel.mapLongPressed(at: $0) }
        )
        // Kaydetmeden önceki soru, ihtiyaca dokunulduğu andaki noktayı sorar: yanıtlanana kadar iğne sabit kalır
        // ("İğneyi düzelt" haritayı yeniden açar).
        .allowsHitTesting(viewModel.pendingReport == nil)
    }

    /// Haritanın görünen kısmının tam ortasında duran iğne; ucu kamera hedefini gösterir.
    private var placementPin: some View {
        VStack(spacing: 0) {
            ZStack {
                Ellipse()
                    .fill(.black.opacity(0.25))
                    .frame(width: 14, height: 6)
                PlacementPin(
                    species: viewModel.placementSpecies,
                    isLifted: viewModel.isCameraMoving,
                    isBlocked: viewModel.placementVerdict != .ready
                )
                    .alignmentGuide(VerticalAlignment.center) { $0[.bottom] }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Color.clear.frame(height: bottomPanelHeight + 8)
        }
        .allowsHitTesting(false)
    }

    // MARK: Üst çubuk

    /// "Hâlâ orada mı?": üst çubuğun altında, haritanın üstünde; alt panel ve ana düğme yerinden oynamaz.
    @ViewBuilder
    private var nearbyBanner: some View {
        if let prompt = viewModel.nearbyPrompt {
            NearbyPromptBanner(
                prompt: prompt,
                distance: viewModel.distance(to: prompt.report),
                showsUnneeded: viewModel.nearbyAvailableActions(for: prompt.report).contains(.reportUnneeded),
                isBusy: viewModel.busyAction != nil,
                onAnswer: { viewModel.answerNearbyPrompt($0) },
                onOpen: { viewModel.nearbyPromptTapped() }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            StatusChip(text: statusText, systemImage: statusSymbol)
            Spacer(minLength: 0)
            Button {
                showsLegend = true
            } label: {
                Image(systemName: "info")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: Circle())
            .accessibilityLabel("İşaretlerin anlamı")
        }
    }

    private var statusText: String {
        if let warning = viewModel.environment.setupWarning { return warning }
        // Engellenen kimlik: kalıcı olarak söylenir.
        if viewModel.isBanned { return Messages.banned }
        if viewModel.userID == nil { return "Bağlanıyor…" }
        // İlk alana henüz bakılmadı: "yardım bekleyen yok" demek yanlış olurdu.
        if !viewModel.initialAreaIsOpen { return "Konumun bulunuyor…" }
        if viewModel.isZoomedTooFarOut { return "İşaretleri görmek için yakınlaştır" }
        return Messages.waitingHeadline(viewModel.waitingCounts)
    }

    private var statusSymbol: String {
        if viewModel.environment.setupWarning != nil { return "exclamationmark.triangle.fill" }
        if viewModel.isBanned { return "nosign" }
        if viewModel.userID == nil { return "antenna.radiowaves.left.and.right" }
        return "pawprint.fill"
    }

    // MARK: Alt panel

    @ViewBuilder
    private func bottomPanel(maxCardContentHeight: CGFloat) -> some View {
        switch viewModel.mode {
        case .choosingSpecies, .choosingNeed, .editing:
            ReportPanel(
                mode: viewModel.mode,
                duplicate: viewModel.duplicateCandidate,
                duplicatePrompt: viewModel.duplicatePrompt,
                allowanceText: viewModel.createAllowanceText,
                pendingReport: viewModel.pendingReport,
                editingReport: viewModel.editingReport,
                isSavingEdit: viewModel.isSavingEdit,
                isEditTargetTooFar: viewModel.isEditTargetTooFar,
                canRetract: viewModel.canRetractEditing,
                placementVerdict: viewModel.placementVerdict,
                isEditingPinMoved: viewModel.isEditingPinMoved,
                canRecenterPin: viewModel.canRecenterPin,
                reportWrongURL: viewModel.reportWrongURL,
                onSpecies: { viewModel.choose($0) },
                onNeed: { viewModel.choose($0) },
                onDuplicate: { viewModel.confirmDuplicate($0) },
                onDismissDuplicate: { viewModel.dismissDuplicate() },
                onConfirmPending: { viewModel.confirmPendingReport() },
                onCancelPending: { viewModel.cancelPendingReport() },
                onRetract: { viewModel.requestRetract() },
                onRecenterPin: { viewModel.recenterPin() },
                onRestorePin: { viewModel.restoreEditPin() },
                onBack: { viewModel.backToSpecies() },
                onCancel: { viewModel.cancelPlacing() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .browsing:
            if let report = viewModel.selectedReport {
                ReportCard(
                    report: report,
                    userID: viewModel.userID,
                    now: viewModel.now,
                    distance: viewModel.distance(to: report),
                    look: viewModel.look(for: report),
                    closingMode: viewModel.closingMode,
                    plan: viewModel.cardPlan(for: report),
                    busyAction: viewModel.busyAction,
                    flagMailURL: viewModel.flagMailURL(for: report),
                    maxContentHeight: maxCardContentHeight,
                    onAction: { action in viewModel.handle(action, on: report) },
                    onEdit: { viewModel.startEditing(report) },
                    onFlag: { viewModel.requestFlag(report) },
                    onHide: { viewModel.hide(report) },
                    onDirections: {
                        // Gece hatırlatması gösterilecekse bağlantı "Devam et"ten sonra açılır.
                        if let url = viewModel.requestDirections(for: report) { openURL(url) }
                    },
                    onClose: { viewModel.closeCard() }
                )
                .id(report.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                browsingControls
                    .transition(.opacity)
            }
        }
    }

    private var browsingControls: some View {
        HStack(alignment: .center) {
            Color.clear.frame(width: 52, height: 52)
            Spacer(minLength: 8)
            // "Hayvan gördüm" her sokak kedisi için basılıyordu; düğme yardım ihtiyacını sorar.
            Button {
                viewModel.startPlacing()
            } label: {
                Label("Yardım gereken hayvan", systemImage: "plus")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 20)
                    .frame(height: 60)
                    .foregroundStyle(Color(.systemBackground))
                    .background(Color.accentColor, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityHint("Bulunduğun yerin çevresine işaret koyar. Haritaya uzun basarak çevrende başka bir nokta da seçebilirsin.")
            .accessibilityIdentifier("report-button")
            Spacer(minLength: 8)
            Button {
                viewModel.recenterOnUser()
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: Circle())
            .accessibilityLabel("Konumuma git")
        }
    }
}

/// Üstteki küçük durum etiketi: haritanın canlı olduğunu hissettirir.
struct StatusChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .lineLimit(2)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
    }
}

/// "İşaretlendi · Geri al" gibi kısa bildirimler. "Geri al" az önce konan işareti siler ya da az önceki
/// "Çözüldü" / "Artık yok" önerisini geri alır (bkz. `MapViewModel.Toast.Undo`).
struct ToastView: View {
    let toast: MapViewModel.Toast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("toast-message")
            if toast.undoReportID != nil {
                Button("Geri al", action: onUndo)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(.primary)
                    .fixedSize()
                    .accessibilityIdentifier("toast-undo")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
