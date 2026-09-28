import AnimalKit
import CoreLocation
import Observation

/// Kullanıcının konumu. Yalnızca "uygulama açıkken" izni istenir.
@MainActor
@Observable
final class LocationProvider {
    /// Son konum okuması: "İğne bulunduğun yerden … uzakta" sorusu yalnızca taze ve yeterince doğru
    /// okumayla sorulur (bkz. `GentleCheck.distanceToAsk`).
    struct Fix: Equatable, Sendable {
        let coordinate: Coordinate
        let timestamp: Date
        /// Metre; geçersiz okumada negatif (CoreLocation'daki gibi).
        let horizontalAccuracy: Double
    }

    /// `coordinate` ancak bu kadar metre değişince güncellenir: ona bağlı görünümler (uzaklık, ilk
    /// ortalama) her okumada yeniden çizilmesin.
    static let coordinateStep: Double = 10

    private(set) var coordinate: Coordinate? = nil
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// Her okumada yenilenir (gözlenmez); yalnızca işaret konurken okunur.
    @ObservationIgnored private(set) var fix: Fix? = nil

    private let manager = CLLocationManager()
    private let delegate = LocationDelegate()

    init() {
        authorization = manager.authorizationStatus
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Kıpırdamayan kullanıcının okuması da taze kalsın (uzaklık sorusu en fazla 2 dk'lık okumayla
        // sorulur); harita kullanıcı konumunu zaten izlediği için ek yük küçüktür.
        manager.distanceFilter = kCLDistanceFilterNone
        manager.delegate = delegate
        delegate.onLocation = { [weak self] fix in
            self?.update(with: fix)
        }
        delegate.onAuthorization = { [weak self] status in
            self?.authorization = status
            self?.start()
        }
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    private func update(with fix: Fix) {
        self.fix = fix
        if let coordinate, coordinate.distance(to: fix.coordinate) < Self.coordinateStep { return }
        coordinate = fix.coordinate
    }
}

/// CLLocationManager geri çağrıları, yöneticinin oluşturulduğu ana iş parçacığında gelir.
private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onLocation: (@MainActor (LocationProvider.Fix) -> Void)?
    var onAuthorization: (@MainActor (CLAuthorizationStatus) -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let timestamp = location.timestamp
        let accuracy = location.horizontalAccuracy
        MainActor.assumeIsolated {
            guard let onLocation else { return }
            onLocation(LocationProvider.Fix(coordinate: coordinate, timestamp: timestamp, horizontalAccuracy: accuracy))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard let onAuthorization else { return }
            onAuthorization(status)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Geçici hatalar (ör. kapalı alan) yok sayılır; son bilinen konum kullanılmaya devam eder.
    }
}
