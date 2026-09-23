import AnimalKit
import CoreLocation
import Observation

/// Kullanıcının konumu. Yalnızca "uygulama açıkken" izni istenir.
@MainActor
@Observable
final class LocationProvider {
    private(set) var coordinate: Coordinate? = nil
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private let delegate = LocationDelegate()

    init() {
        authorization = manager.authorizationStatus
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.delegate = delegate
        delegate.onLocation = { [weak self] coordinate in
            self?.coordinate = coordinate
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
}

/// CLLocationManager geri çağrıları, yöneticinin oluşturulduğu ana iş parçacığında gelir.
private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onLocation: (@MainActor (Coordinate) -> Void)?
    var onAuthorization: (@MainActor (CLAuthorizationStatus) -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        MainActor.assumeIsolated {
            guard let onLocation else { return }
            onLocation(coordinate)
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
