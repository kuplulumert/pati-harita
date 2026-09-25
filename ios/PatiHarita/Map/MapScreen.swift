import AnimalKit
import SwiftUI

/// Uygulamanın tek ana ekranı: tam ekran harita.
struct MapScreen: View {
    @State private var viewModel: MapViewModel
    @State private var bottomPanelHeight: CGFloat = 0
    @State private var showsLegend = false
    @Environment(\.openURL) private var openURL

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: MapViewModel(environment: environment))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                map(safeArea: proxy.safeAreaInsets)
                    .ignoresSafeArea()

                if viewModel.isPlacing {
                    placementPin
                }

                VStack(spacing: 10) {
                    topBar
                    Spacer(minLength: 0)
                    if let toast = viewModel.toast {
                        ToastView(toast: toast) { viewModel.undo(toast) }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    bottomPanel
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            // Harita dolgusu da 0,25 sn'de değişir; iğne onunla birlikte kaysın.
                            withAnimation(.easeInOut(duration: 0.25)) { bottomPanelHeight = height }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .animation(.snappy(duration: 0.3), value: viewModel.mode)
        .animation(.snappy(duration: 0.3), value: viewModel.selectedReportID)
        .animation(.snappy(duration: 0.3), value: viewModel.duplicateCandidateID)
        .animation(.snappy(duration: 0.3), value: viewModel.toast)
        .sensoryFeedback(.success, trigger: viewModel.reportsCreated)
        .sheet(isPresented: $showsLegend) {
            LegendSheet()
                .presentationDetents([.medium, .large])
        }
        .task { await viewModel.run() }
        .onChange(of: viewModel.location.coordinate) {
            viewModel.userLocationChanged()
        }
    }

    // MARK: Harita

    private func map(safeArea: EdgeInsets) -> some View {
        ReportMapView(
            reports: viewModel.visibleReports,
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
            onCameraWillMove: { viewModel.cameraWillMove() },
            onCameraMove: { viewModel.cameraMoved(to: $0) },
            onCameraIdle: { viewModel.cameraBecameIdle(center: $0, visibleRadius: $1) },
            onMarkerTap: { viewModel.markerTapped($0) },
            onMapTap: { viewModel.mapTapped() },
            onLongPress: { viewModel.mapLongPressed(at: $0) }
        )
    }

    /// Haritanın görünen kısmının tam ortasında duran iğne; ucu kamera hedefini gösterir.
    private var placementPin: some View {
        VStack(spacing: 0) {
            ZStack {
                Ellipse()
                    .fill(.black.opacity(0.25))
                    .frame(width: 14, height: 6)
                PlacementPin(species: viewModel.mode.species, isLifted: viewModel.isCameraMoving)
                    .alignmentGuide(VerticalAlignment.center) { $0[.bottom] }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Color.clear.frame(height: bottomPanelHeight + 8)
        }
        .allowsHitTesting(false)
    }

    // MARK: Üst çubuk

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
        if viewModel.userID == nil { return "Bağlanıyor…" }
        if viewModel.isZoomedTooFarOut { return "İşaretleri görmek için yakınlaştır" }
        switch viewModel.waitingCount {
        case 0: return "Yakında yardım bekleyen yok"
        case let count: return "\(count) hayvan yardım bekliyor"
        }
    }

    private var statusSymbol: String {
        if viewModel.environment.setupWarning != nil { return "exclamationmark.triangle.fill" }
        if viewModel.userID == nil { return "antenna.radiowaves.left.and.right" }
        return "pawprint.fill"
    }

    // MARK: Alt panel

    @ViewBuilder
    private var bottomPanel: some View {
        switch viewModel.mode {
        case .choosingSpecies, .choosingNeed:
            ReportPanel(
                mode: viewModel.mode,
                duplicate: viewModel.duplicateCandidate,
                onSpecies: { viewModel.choose($0) },
                onNeed: { viewModel.choose($0) },
                onDuplicate: { viewModel.confirmDuplicate($0) },
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
                    busyAction: viewModel.busyAction,
                    onAction: { action in Task { await viewModel.perform(action, on: report) } },
                    onDirections: {
                        if let url = viewModel.directionsURL(for: report) { openURL(url) }
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
            Spacer()
            Button {
                viewModel.startPlacing()
            } label: {
                Label("Hayvan gördüm", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .frame(height: 60)
                    .foregroundStyle(Color(.systemBackground))
                    .background(Color.accentColor, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Bulunduğun noktayı işaretler. Haritaya uzun basarak başka bir nokta da seçebilirsin.")
            Spacer()
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

private extension MapViewModel.Mode {
    var species: Species? {
        if case .choosingNeed(let species) = self { return species }
        return nil
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

/// "İşaretlendi · Geri al" gibi kısa bildirimler.
struct ToastView: View {
    let toast: MapViewModel.Toast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            if toast.undoReportID != nil {
                Button("Geri al", action: onUndo)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
