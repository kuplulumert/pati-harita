import AnimalKit
import CoreLocation
import MapKit
import SwiftUI

/// Kameranın gitmesi istenen konum. Her istek yeni bir `id` taşır; aynı istek iki kez uygulanmaz.
struct CameraRequest: Equatable {
    let id = UUID()
    let target: Coordinate
    /// Web haritalarındaki yakınlaştırma ölçeği: 0 dünyanın tamamı, her adım iki kat yakın (16 ≈ mahalle).
    var zoom: Float?
}

/// Apple Haritalar'ın `MKMapView`'ını SwiftUI'a bağlar ve işaretleri senkronize eder.
struct ReportMapView: UIViewRepresentable {
    static let defaultCenter = Coordinate(latitude: 41.0082, longitude: 28.9784) // İstanbul
    static let defaultZoom: Double = 13

    let reports: [Report]
    let selectedID: String?
    let userID: String?
    let now: Date
    let cameraRequest: CameraRequest?
    /// Haritanın üst/alt arayüzün altında kalan kısmı. Kamera hedefi (ve yeni işaret iğnesi)
    /// her zaman kalan görünür alanın ortasındadır; harita yazıları da bu alanda kalır.
    let insets: UIEdgeInsets

    var onCameraWillMove: @MainActor () -> Void = {}
    var onCameraMove: @MainActor (Coordinate) -> Void = { _ in }
    var onCameraIdle: @MainActor (_ center: Coordinate, _ visibleRadius: Double) -> Void = { _, _ in }
    var onMarkerTap: @MainActor (_ reportID: String) -> Void = { _ in }
    var onMapTap: @MainActor () -> Void = {}
    var onLongPress: @MainActor (Coordinate) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LayoutReportingMapView {
        let mapView = LayoutReportingMapView()
        context.coordinator.parent = self
        context.coordinator.attach(to: mapView)
        return mapView
    }

    func updateUIView(_ mapView: LayoutReportingMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.update(insets: insets)
        coordinator.syncAnnotations()

        if let request = cameraRequest, request.id != coordinator.appliedCameraRequestID {
            coordinator.appliedCameraRequestID = request.id
            coordinator.move(to: request.target, zoom: request.zoom.map(Double.init))
        }
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        private static let reuseIdentifier = "report"

        var parent: ReportMapView?
        var appliedCameraRequestID: UUID?
        private weak var mapView: LayoutReportingMapView?
        private var annotations: [String: ReportAnnotation] = [:]
        private var renderedScale: CGFloat = 0
        private let icons = MarkerIconRenderer()
        private var insets: UIEdgeInsets = .zero
        /// Boyut belli olunca kamera kurulur; o zamana kadar gelen hedef burada bekler.
        private var hasLaidOut = false
        private var cameraBeforeLayout: (target: CLLocationCoordinate2D, zoom: Double)?
        /// Sürmekte olan programatik kamera hareketi. Dolgu bu sırada değişirse hedef korunur.
        private var cameraInFlight: (target: CLLocationCoordinate2D, zoom: Double)?

        func attach(to mapView: LayoutReportingMapView) {
            self.mapView = mapView
            mapView.delegate = self
            mapView.showsUserLocation = true
            mapView.isRotateEnabled = false
            mapView.isPitchEnabled = false
            mapView.showsCompass = false
            mapView.insetsLayoutMarginsFromSafeArea = false
            // Kullanıcının konum noktası mavi kalsın (uygulamanın koyu vurgu rengini almasın).
            mapView.tintColor = .systemBlue

            // Sade harita: işletme ve ulaşım simgeleri gizlenir ki yardım işaretleri öne çıksın.
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            configuration.pointOfInterestFilter = MKPointOfInterestFilter(including: [.park])
            configuration.showsTraffic = false
            mapView.preferredConfiguration = configuration

            mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: Self.reuseIdentifier)

            // Kullanıcının haritayı kendisi hareket ettirdiğini (programatik kamera değil) ayırt eder.
            // Çift dokunuş da MapKit'te yakınlaştırmadır.
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleUserCameraGesture(_:)))
            doubleTap.numberOfTapsRequired = 2
            // Tek dokunuş ancak çift dokunuş değilse sayılır.
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.require(toFail: doubleTap)
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleUserCameraGesture(_:)))
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleUserCameraGesture(_:)))
            for recognizer in [doubleTap, tap, longPress, pan, pinch] {
                recognizer.delegate = self
                recognizer.cancelsTouchesInView = false
                mapView.addGestureRecognizer(recognizer)
            }

            mapView.onLayout = { [weak self] in self?.mapDidLayout() }
        }

        // MARK: Kamera

        func move(to target: Coordinate, zoom: Double?) {
            let zoom = zoom ?? mapView.map { currentZoom(of: $0) } ?? ReportMapView.defaultZoom
            setCamera(target: CLLocationCoordinate2D(target), zoom: zoom, animated: true)
        }

        func update(insets newInsets: UIEdgeInsets) {
            guard newInsets != insets else { return }
            let oldInsets = insets
            insets = newInsets
            guard let mapView else { return }
            // Apple Haritalar yazısı ve "Yasal" bağlantısı alt panelin altında kalmasın.
            mapView.layoutMargins = newInsets
            guard hasLaidOut else { return }
            // Görünen alan değişti: hedef yine görünen alanın ortasında kalsın.
            let target = cameraInFlight?.target ?? visibleCenter(of: mapView, insets: oldInsets)
            let zoom = cameraInFlight?.zoom ?? currentZoom(of: mapView)
            setCamera(target: target, zoom: zoom, animated: true)
        }

        private func mapDidLayout() {
            guard !hasLaidOut, let mapView, mapView.bounds.width > 0, mapView.bounds.height > 0 else { return }
            hasLaidOut = true
            mapView.layoutMargins = insets
            // Etiketler iki tarafta da olmalı; yoksa `??` sonucu etiketsiz demet olur ve `.target` derlenmez.
            let camera = cameraBeforeLayout
                ?? (target: CLLocationCoordinate2D(ReportMapView.defaultCenter), zoom: ReportMapView.defaultZoom)
            cameraBeforeLayout = nil
            setCamera(target: camera.target, zoom: camera.zoom, animated: false)
        }

        /// `target`'ı haritanın dolgular dışında kalan kısmının ortasına, `zoom` ölçeğinde getirir.
        private func setCamera(target: CLLocationCoordinate2D, zoom: Double, animated: Bool) {
            guard hasLaidOut, let mapView else {
                cameraBeforeLayout = (target, zoom)
                return
            }
            let visible = mapView.bounds.inset(by: insets)
            guard visible.width > 1, visible.height > 1 else { return }
            // MapKit dünyası 2^28 harita noktası genişliğindedir; z ölçeğinde bir ekran noktası 2^(20 - z) harita noktası.
            let mapPointsPerPoint = pow(2, 20 - zoom)
            let size = MKMapSize(width: visible.width * mapPointsPerPoint, height: visible.height * mapPointsPerPoint)
            let center = MKMapPoint(target)
            let rect = MKMapRect(
                origin: MKMapPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                size: size
            )
            cameraInFlight = (target, zoom)
            // Dolgu burada verilmez: MapKit `layoutMargins`'i (= insets) bölge hesabına kendisi ekler.
            // `edgePadding: insets` ile birlikte dolgu iki kez sayılıyordu (CI ekran görüntülerinde iğne
            // hedefin ~100 nokta altında kalıyor, harita panel büyüdükçe uzaklaşıyordu).
            mapView.setVisibleMapRect(rect, animated: animated)
        }

        private func visibleCenter(of mapView: MKMapView, insets: UIEdgeInsets) -> CLLocationCoordinate2D {
            let visible = mapView.bounds.inset(by: insets)
            return mapView.convert(CGPoint(x: visible.midX, y: visible.midY), toCoordinateFrom: mapView)
        }

        private func currentZoom(of mapView: MKMapView) -> Double {
            guard mapView.bounds.width > 0, mapView.visibleMapRect.width > 0 else { return ReportMapView.defaultZoom }
            return 20 - log2(mapView.visibleMapRect.width / Double(mapView.bounds.width))
        }

        // MARK: İşaretler

        func syncAnnotations() {
            guard let mapView, let parent else { return }
            let scale = mapView.traitCollection.displayScale
            if scale != renderedScale {
                // Ekran ölçeği ilk çizimden sonra belli olabilir; tüm ikonları yeniden çiz.
                annotations.values.forEach { $0.style = nil }
                renderedScale = scale
            }
            var visibleIDs = Set<String>()
            var added: [ReportAnnotation] = []

            for report in parent.reports {
                visibleIDs.insert(report.id)
                let isSelected = report.id == parent.selectedID
                let style = MarkerStyle(
                    need: report.need,
                    species: report.species,
                    isBeingHelped: report.phase(for: parent.userID, at: parent.now).isBeingHelped,
                    isSelected: isSelected,
                    seenBadge: Formatting.seenCountBadge(report.seenCount)
                )

                let annotation: ReportAnnotation
                if let existing = annotations[report.id] {
                    annotation = existing
                } else {
                    annotation = ReportAnnotation(
                        reportID: report.id,
                        coordinate: CLLocationCoordinate2D(report.coordinate)
                    )
                    annotations[report.id] = annotation
                    added.append(annotation)
                }
                if annotation.style != style {
                    annotation.image = icons.image(for: style, scale: scale)
                    annotation.style = style
                    annotation.title = "\(report.need.title), \(report.species.title)"
                }
                // Rozet 99'da durur; sesli okunan değer gerçek sayıdır.
                annotation.seenValue = Formatting.seenCount(report.seenCount)
                // Eski işaretler soluklaşır: hâlâ geçerli mi bilinmiyor.
                annotation.alpha = CGFloat(0.5 + 0.5 * report.freshness(at: parent.now))
                // Üst üste binen işaretlerde acil (ve seçili) olan üstte çizilir.
                annotation.zPriority = MKAnnotationViewZPriority(
                    rawValue: MKAnnotationViewZPriority.defaultUnselected.rawValue
                        + Float(report.need.priority + (isSelected ? 100 : 0))
                )
                if let view = mapView.view(for: annotation) {
                    apply(annotation, to: view)
                }
            }

            let removedIDs = annotations.keys.filter { !visibleIDs.contains($0) }
            let removed = removedIDs.compactMap { annotations.removeValue(forKey: $0) }
            if !removed.isEmpty {
                mapView.removeAnnotations(removed)
            }
            if !added.isEmpty {
                mapView.addAnnotations(added)
            }
        }

        private func apply(_ annotation: ReportAnnotation, to view: MKAnnotationView) {
            view.image = annotation.image
            // Görüntünün alt-orta noktası iğnenin ucudur; koordinata o nokta oturur.
            view.centerOffset = CGPoint(x: 0, y: -(annotation.image?.size.height ?? 0) / 2)
            view.alpha = annotation.alpha
            view.zPriority = annotation.zPriority
            // VoiceOver ve arayüz testi işareti "Mama / su, Kedi" gibi okur; birden çok kişi bildirdiyse
            // ardından değer olarak "3 kişi bildirdi" gelir (etiket değişmez, test onu birebir arar).
            view.isAccessibilityElement = true
            view.accessibilityTraits = .button
            view.accessibilityIdentifier = "report-marker"
            view.accessibilityLabel = annotation.title
            view.accessibilityValue = annotation.seenValue
        }

        // MARK: Hareketler

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let parent else { return }
            parent.onMapTap()
        }

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let mapView, let parent else { return }
            let coordinate = mapView.convert(recognizer.location(in: mapView), toCoordinateFrom: mapView)
            parent.onLongPress(Coordinate(coordinate))
        }

        @objc private func handleUserCameraGesture(_ recognizer: UIGestureRecognizer) {
            // Dokunuş tanıyıcıları `.began` bildirmez, doğrudan `.ended` olur.
            let started = recognizer is UITapGestureRecognizer ? recognizer.state == .ended : recognizer.state == .began
            guard started, let parent else { return }
            cameraInFlight = nil
            parent.onCameraWillMove()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // İşarete dokunmak haritaya dokunmak sayılmaz; seçim `didSelect` ile gelir.
            // Kullanıcının mavi konum noktası sayılmaz: üstüne uzun basınca oradan işaretlenebilsin.
            guard gestureRecognizer is UITapGestureRecognizer || gestureRecognizer is UILongPressGestureRecognizer else {
                return true
            }
            var view = touch.view
            while let current = view {
                if let annotationView = current as? MKAnnotationView, annotationView.annotation is ReportAnnotation {
                    return false
                }
                view = current.superview
            }
            return true
        }

        // MARK: MKMapViewDelegate — MapKit bu çağrıları ana iş parçacığında yapar.

        nonisolated func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            MainActor.assumeIsolated {
                guard hasLaidOut, let parent else { return }
                // Programatik hareket (ör. panel değişince yeniden ortalama) sürerken hedef bildirilir;
                // yarı yoldaki merkez yeni dolgularla ölçülür ve işaret o anda koyulursa kayık kaydedilirdi.
                let center = cameraInFlight?.target ?? visibleCenter(of: mapView, insets: insets)
                parent.onCameraMove(Coordinate(center))
            }
        }

        nonisolated func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            MainActor.assumeIsolated {
                guard hasLaidOut, let parent else { return }
                let visible = visibleCenter(of: mapView, insets: insets)
                if let inFlight = cameraInFlight {
                    // Yeni bir hareketle yarıda kesilen animasyonun bildirimi hedefi silmesin: hedefe varınca silinir.
                    let target = MKMapPoint(inFlight.target)
                    let reached = MKMapPoint(visible)
                    let tolerance = 4 * pow(2, 20 - inFlight.zoom) // ~4 ekran noktası, harita noktası cinsinden
                    if hypot(target.x - reached.x, target.y - reached.y) <= tolerance {
                        cameraInFlight = nil
                    }
                }
                let center = cameraInFlight?.target ?? visible

                // Yarıçap dolgulardan bağımsız ölçülür: panel açılıp kapanınca "çok uzak" sınırı oynamasın
                // (aksi hâlde sınırın hemen ötesinde kart açılıp kapanarak döngüye girebiliyordu).
                // `centerCoordinate` değil: MapKit onu da `layoutMargins`'e göre hesaplar.
                let bounds = mapView.bounds
                let boundsCenter = MKMapPoint(
                    mapView.convert(CGPoint(x: bounds.midX, y: bounds.midY), toCoordinateFrom: mapView)
                )
                let corners = [
                    CGPoint(x: bounds.minX, y: bounds.minY),
                    CGPoint(x: bounds.maxX, y: bounds.minY),
                    CGPoint(x: bounds.minX, y: bounds.maxY),
                    CGPoint(x: bounds.maxX, y: bounds.maxY),
                ]
                let radius = corners
                    .map { MKMapPoint(mapView.convert($0, toCoordinateFrom: mapView)).distance(to: boundsCenter) }
                    .max() ?? 0
                parent.onCameraIdle(Coordinate(center), radius)
            }
        }

        nonisolated func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            MainActor.assumeIsolated {
                // Kullanıcının konumu için MapKit'in mavi noktası kullanılır.
                guard let annotation = annotation as? ReportAnnotation else { return nil }
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.reuseIdentifier, for: annotation)
                view.canShowCallout = false
                view.displayPriority = .required
                apply(annotation, to: view)
                return view
            }
        }

        nonisolated func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            MainActor.assumeIsolated {
                for view in views {
                    // Yeni işaret "belirir"; kaydırınca yeniden görünen işaretler canlandırılmaz.
                    guard let annotation = view.annotation as? ReportAnnotation, !annotation.hasAppeared else { continue }
                    annotation.hasAppeared = true
                    view.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
                    UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) {
                        view.transform = .identity
                    }
                }
            }
        }

        nonisolated func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            MainActor.assumeIsolated {
                // Seçim durumu uygulamada tutulur; MapKit'in seçimi hemen bırakılır ki aynı işarete
                // yeniden dokunulabilsin.
                mapView.deselectAnnotation(annotation, animated: false)
                guard let annotation = annotation as? ReportAnnotation, let parent else { return }
                parent.onMarkerTap(annotation.reportID)
            }
        }
    }
}

/// İlk yerleşimi bildiren harita: kamera, haritanın boyutu belli olunca kurulur.
final class LayoutReportingMapView: MKMapView {
    var onLayout: (@MainActor () -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// Haritadaki bir işaret. Konumu değişmez (kurallar izin vermez); görünümü her güncellemede yenilenir.
final class ReportAnnotation: NSObject, MKAnnotation {
    let reportID: String
    let coordinate: CLLocationCoordinate2D
    /// Erişilebilirlik etiketi ("Mama / su, Kedi"); `canShowCallout` kapalı olduğu için ekranda görünmez.
    var title: String?
    /// Erişilebilirlik değeri ("3 kişi bildirdi"); yalnızca işareti koyan bildirdiyse `nil`.
    var seenValue: String?
    var style: MarkerStyle?
    var image: UIImage?
    var alpha: CGFloat = 1
    var zPriority: MKAnnotationViewZPriority = .defaultUnselected
    var hasAppeared = false

    init(reportID: String, coordinate: CLLocationCoordinate2D) {
        self.reportID = reportID
        self.coordinate = coordinate
    }
}

extension Coordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension CLLocationCoordinate2D {
    init(_ coordinate: Coordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
