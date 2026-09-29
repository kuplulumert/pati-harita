import AnimalKit
import CoreLocation
import Observation

/// Kullanıcının konumu. Yalnızca "uygulama açıkken" izni istenir; konum cihazdan çıkmaz.
@MainActor
@Observable
final class LocationProvider {
    /// Son iyi konum okuması: yakınlık kapısı (`PlacementGate`) ve "Hâlâ orada mı?" sorusu bunu kullanır.
    typealias Fix = LocationFix

    /// `coordinate` ancak bu kadar metre değişince güncellenir: ona bağlı görünümler (uzaklık, ilk
    /// ortalama) her okumada yeniden çizilmesin.
    static let coordinateStep: Double = 10

    private(set) var coordinate: Coordinate? = nil
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// Tam Konum açık mı; yalnızca değişince yazılır.
    private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    /// Kabul edilen son okuma (`LocationFix.shouldReplace`). Gözlenmez: her okumada ekran yeniden çizilmesin.
    @ObservationIgnored private(set) var fix: Fix? = nil
    /// Son `NearbyPrompt.speedSampleCount` okumanın hızı ("Hâlâ orada mı?" hızlı gidene sorulmaz).
    @ObservationIgnored private(set) var speedSamples: [NearbyPrompt.SpeedSample] = []
    /// Her kabul edilen okumadan sonra. Gözlenmeyen bir geri çağrı: işaretleme durumu okuma başına yeniden
    /// hesaplanır, ekran değil.
    @ObservationIgnored var onFix: (@MainActor () -> Void)?
    /// İzin ya da Tam Konum değişince.
    @ObservationIgnored var onAccessChange: (@MainActor () -> Void)?

    /// Demo modu simülatörde: okumanın zamanı her soruda "şimdi" sayılır (`gateFix`). CI ve Appetize
    /// Release derlemesi kullanır; simülatörün konumu ne sıklıkla verdiği bilinmediği için okuma eskimesin.
    let restampsFixes: Bool

    private let manager = CLLocationManager()
    private let delegate = LocationDelegate()

    init(restampsFixes: Bool = false) {
        self.restampsFixes = restampsFixes
        authorization = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Kıpırdamayan kullanıcının okuması da taze kalsın (işaret yalnızca taze okumayla konabilir);
        // harita kullanıcı konumunu zaten izlediği için ek yük küçüktür.
        manager.distanceFilter = kCLDistanceFilterNone
        // Uygulama yalnızca öndeyken konum kullanır; duran kişinin güncellemeleri kendiliğinden durmasın.
        manager.pausesLocationUpdatesAutomatically = false
        manager.delegate = delegate
        delegate.onLocations = { [weak self] fixes in
            self?.update(with: fixes)
        }
        delegate.onAuthorization = { [weak self] status, accuracy in
            self?.authorizationChanged(status: status, accuracy: accuracy)
        }
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Yakınlık kapısı için izin durumu.
    var access: LocationAccess {
        switch authorization {
        case .notDetermined:
            return .notDetermined
        case .authorizedWhenInUse, .authorizedAlways:
            return accuracyAuthorization == .reducedAccuracy ? .approximate : .full
        default:
            // .denied, .restricted
            return .denied
        }
    }

    /// Kişi hızlı mı gidiyor (ör. araçta)?
    var isMovingFast: Bool {
        NearbyPrompt.isMovingFast(speedSamples)
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

    /// Kapının kullandığı okuma. `restampsFixes` iken zamanı `now` olur.
    func gateFix(at now: Date) -> Fix? {
        guard var current = self.fix else { return nil }
        if restampsFixes {
            current.timestamp = now
        }
        return current
    }

    /// Okuma eskiyse güncellemeler yeniden başlatılır (işaretleme başlarken).
    func refresh() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.stopUpdatingLocation()
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    /// Tam Konum kapalıyken bu işaretleme için geçici tam konum istenir (Info.plist'teki "PlaceReport").
    func requestFullAccuracy() {
        guard accuracyAuthorization == .reducedAccuracy else { return }
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PlaceReport")
    }

    private func update(with fixes: [Fix]) {
        var accepted = false
        for candidate in fixes {
            speedSamples.append(NearbyPrompt.SpeedSample(
                at: candidate.timestamp,
                speed: candidate.speed,
                accuracy: candidate.speedAccuracy
            ))
            // "En iyi yakın okuma": önbellekteki eski ya da tek bir kaba okuma iyi konumu silmesin.
            if LocationFix.shouldReplace(current: self.fix, with: candidate) {
                self.fix = candidate
                accepted = true
            }
        }
        if speedSamples.count > NearbyPrompt.speedSampleCount {
            speedSamples.removeFirst(speedSamples.count - NearbyPrompt.speedSampleCount)
        }
        guard accepted, let current = self.fix else { return }
        let moved = coordinate.map { $0.distance(to: current.coordinate) >= Self.coordinateStep } ?? true
        if moved {
            coordinate = current.coordinate
        }
        onFix?()
    }

    private func authorizationChanged(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) {
        if authorization != status {
            authorization = status
        }
        if accuracyAuthorization != accuracy {
            accuracyAuthorization = accuracy
        }
        start()
        onAccessChange?()
    }
}

/// CLLocationManager geri çağrıları, yöneticinin oluşturulduğu ana iş parçacığında gelir.
private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onLocations: (@MainActor ([LocationFix]) -> Void)?
    var onAuthorization: (@MainActor (CLAuthorizationStatus, CLAccuracyAuthorization) -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map { location in
            LocationFix(
                coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                timestamp: location.timestamp,
                horizontalAccuracy: location.horizontalAccuracy,
                speed: location.speed,
                speedAccuracy: location.speedAccuracy,
                isSimulatedBySoftware: location.sourceInformation?.isSimulatedBySoftware ?? false
            )
        }
        guard !fixes.isEmpty else { return }
        MainActor.assumeIsolated {
            guard let onLocations else { return }
            onLocations(fixes)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        MainActor.assumeIsolated {
            guard let onAuthorization else { return }
            onAuthorization(status, accuracy)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Geçici hatalar (ör. kapalı alan) yok sayılır; son bilinen konum kullanılmaya devam eder.
    }
}
