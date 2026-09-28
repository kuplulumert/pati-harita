import AnimalKit
import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

/// Uygulamanın bağımlılıkları. Açılışta bir kez kurulur.
///
/// Çalışma modları:
/// - **firebase**: GoogleService-Info.plist varsa gerçek Firebase projesi.
/// - **emulator**: `-useEmulator` başlatma argümanı; yerel Firebase emülatörleri (plist gerekmez).
/// - **demo**: plist yoksa ya da `-demo` argümanıyla; işaretler yalnızca bellekte. Cihaz ayarları (kabul edilen
///   kurallar vb.) plist'siz demo derlemesinde saklanır, `-demo` ile saklanmaz.
///
/// `-noNightReminder` argümanı gece hatırlatmasını kapatır (arayüz testi günün her saatinde çalışır).
///
/// Oturum kapatma bilerek yok: her cihaz tek bir anonim kimlikle kalır (hesap yaşı ve günlük haklar ona bağlı).
@MainActor
final class AppEnvironment {
    enum Backend {
        case firebase
        case emulator
        case demo
    }

    static let noNightReminderArgument = "-noNightReminder"

    let backend: Backend
    let repository: ReportRepository
    let session: UserSession
    let location: LocationProvider
    /// Takip sorusu (A7) için bu cihazın ilgilendiği işaretler.
    let watched: WatchedReports
    /// Kurallar, "Yardıma ihtiyacı var mı?" sayaçları, gizlenen işaretler, gece hatırlatması.
    let device: DeviceState
    /// Üst etikette gösterilen demo uyarısı (işaretlerin örnek olduğunu söyler).
    let setupWarning: String?
    /// Gece (21.00–06.00) yardıma giderken güvenlik hatırlatması gösterilsin mi.
    let nightReminderEnabled: Bool

    init(
        backend: Backend,
        repository: ReportRepository,
        session: UserSession,
        location: LocationProvider,
        watched: WatchedReports,
        device: DeviceState,
        setupWarning: String?,
        nightReminderEnabled: Bool = true
    ) {
        self.backend = backend
        self.repository = repository
        self.session = session
        self.location = location
        self.watched = watched
        self.device = device
        self.setupWarning = setupWarning
        self.nightReminderEnabled = nightReminderEnabled
    }

    static func bootstrap(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        let nightReminderEnabled = !arguments.contains(noNightReminderArgument)
        if arguments.contains("-useEmulator") {
            configureFirebaseForEmulator()
            return firebaseEnvironment(backend: .emulator, nightReminderEnabled: nightReminderEnabled)
        }

        let hasFirebaseConfig = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
        let demoArgument = arguments.contains("-demo")
        guard hasFirebaseConfig, !demoArgument else {
            let demoWarning = hasFirebaseConfig ? nil : "Demo modu: işaretler örnektir. Seninkileri kimse görmez."
            return AppEnvironment(
                backend: .demo,
                repository: DemoReportRepository(),
                session: UserSession(userID: DemoReportRepository.demoUserID) { DemoReportRepository.demoUserID },
                location: LocationProvider(),
                // Demo örneklerinin kimlikleri her açılışta aynı; önceki açılıştan kalan takip soru sordurmasın.
                watched: WatchedReports(defaults: nil),
                // Aynı nedenle gizlenen ve son 24 saatin işaretleri yalnızca bellekte. `-demo` ile (arayüz testi)
                // hiçbir şey saklanmaz, test hep ilk açılıştan başlar. Plist'siz demo derlemesi (TestFlight) ise
                // kabul edilen kuralları, hafif işaret sayacını ve gece hatırlatmasını hatırlar: kurallar her
                // açılışta yeniden sorulmaz.
                device: DeviceState(defaults: demoArgument ? nil : .standard, persistsReports: false),
                setupWarning: demoWarning,
                nightReminderEnabled: nightReminderEnabled
            )
        }

        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        // App Attest daha güçlü ama App ID'de App Attest yeteneği ve imza dosyasında
        // `com.apple.developer.devicecheck.appattest-environment` ister; ikisi yokken jeton alınamaz.
        // Zorunlu kılmadan (2. aşama) önce onlarla birlikte App Attest'e geçilecek.
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        #endif
        FirebaseApp.configure()
        return firebaseEnvironment(backend: .firebase, nightReminderEnabled: nightReminderEnabled)
    }

    private static func firebaseEnvironment(backend: Backend, nightReminderEnabled: Bool) -> AppEnvironment {
        let auth = Auth.auth()
        return AppEnvironment(
            backend: backend,
            repository: FirestoreReportRepository(db: Firestore.firestore()),
            session: UserSession(userID: auth.currentUser?.uid) {
                // Hesap yok, form yok: herkes ilk açılışta sessizce anonim oturum açar.
                try await auth.signInAnonymously().user.uid
            },
            location: LocationProvider(),
            watched: WatchedReports(defaults: .standard),
            device: DeviceState(defaults: .standard),
            setupWarning: nil,
            nightReminderEnabled: nightReminderEnabled
        )
    }

    /// `firebase emulators:start` ile çalışan yerel emülatörler; gerçek bir Firebase projesi gerekmez.
    private static func configureFirebaseForEmulator() {
        let options = FirebaseOptions(googleAppID: "1:123456789012:ios:0123456789abcdef", gcmSenderID: "123456789012")
        options.projectID = "demo-patiharita"
        options.apiKey = "AIzaSyDemoKeyForLocalEmulatorOnly000000"
        FirebaseApp.configure(options: options)
        Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
        Firestore.firestore().useEmulator(withHost: "127.0.0.1", port: 8080)
    }
}
