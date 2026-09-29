import AnimalKit
import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import OSLog

/// Uygulamanın bağımlılıkları. Açılışta bir kez kurulur.
///
/// Çalışma modları:
/// - **firebase**: GoogleService-Info.plist varsa gerçek Firebase projesi.
/// - **emulator**: `-useEmulator` başlatma argümanı; yerel Firebase emülatörleri (plist gerekmez).
/// - **demo**: plist yoksa ya da `-demo` argümanıyla; işaretler yalnızca bellekte. Cihaz ayarları (kabul edilen
///   kurallar vb.) plist'siz demo derlemesinde saklanır, `-demo` ile saklanmaz.
///
/// `-noNightReminder` argümanı gece hatırlatmasını ve ilk gidişteki "Yardıma gidiyorsun" uyarısını kapatır (arayüz
/// testi günün her saatinde aynı akışı dener; `-demo` cihaz durumunu saklamadığı için uyarı her açılışta çıkardı).
/// `-noNearbyPrompt` "Hâlâ orada mı?" sorusunu kapatır (arayüz testinin ana akışı). `-areaClass <sınıf>` yalnızca
/// demo modunda her noktayı o alan sayar (`remote`, `allowed`, `water`, `forest`): arayüz testi alan verisinden
/// bağımsız olsun. Bunlar Release derlemesinde de çalışır (CI testi Release ile yapar).
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
    static let noNearbyPromptArgument = "-noNearbyPrompt"
    static let areaClassArgument = "-areaClass"

    #if targetEnvironment(simulator)
    static let isSimulator = true
    #else
    static let isSimulator = false
    #endif

    private static let logger = Logger(subsystem: "app.patiharita.ios", category: "area")

    let backend: Backend
    let repository: ReportRepository
    let session: UserSession
    let location: LocationProvider
    /// Takip sorusu (A7) için bu cihazın ilgilendiği işaretler.
    let watched: WatchedReports
    /// Kurallar, "Yardıma ihtiyacı var mı?" sayaçları, gizlenen işaretler, güvenlik hatırlatmaları.
    let device: DeviceState
    /// Üst etikette gösterilen demo uyarısı (işaretlerin örnek olduğunu söyler).
    let setupWarning: String?
    /// Yardıma giderken güvenlik hatırlatmaları (gece 21.00–06.00 ve ilk gidişte) gösterilsin mi.
    let nightReminderEnabled: Bool
    /// İğnenin alanı (orman, yerleşim dışı, su): uygulamayla gelen ızgara; yoksa her yer serbest.
    let areaClassifier: any AreaClassifying
    /// "Hâlâ orada mı?" sorusu (`-noNearbyPrompt` kapatır).
    let nearbyPromptEnabled: Bool
    /// Yazılımla taklit edilen konumla işaret konamaz. Yalnızca gerçek Firebase ve gerçek cihazda: demo, emülatör
    /// ve simülatör konumu zaten taklittir.
    let rejectsSimulatedFixes: Bool

    init(
        backend: Backend,
        repository: ReportRepository,
        session: UserSession,
        location: LocationProvider,
        watched: WatchedReports,
        device: DeviceState,
        setupWarning: String?,
        nightReminderEnabled: Bool = true,
        areaClassifier: any AreaClassifying = FixedAreaClassifier(nil),
        nearbyPromptEnabled: Bool = true,
        rejectsSimulatedFixes: Bool = false
    ) {
        self.backend = backend
        self.repository = repository
        self.session = session
        self.location = location
        self.watched = watched
        self.device = device
        self.setupWarning = setupWarning
        self.nightReminderEnabled = nightReminderEnabled
        self.areaClassifier = areaClassifier
        self.nearbyPromptEnabled = nearbyPromptEnabled
        self.rejectsSimulatedFixes = rejectsSimulatedFixes
    }

    static func bootstrap(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        let nightReminderEnabled = !arguments.contains(noNightReminderArgument)
        let nearbyPromptEnabled = !arguments.contains(noNearbyPromptArgument)
        if arguments.contains("-useEmulator") {
            configureFirebaseForEmulator()
            return firebaseEnvironment(
                backend: .emulator,
                nightReminderEnabled: nightReminderEnabled,
                nearbyPromptEnabled: nearbyPromptEnabled
            )
        }

        let hasFirebaseConfig = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
        let demoArgument = arguments.contains("-demo")
        guard hasFirebaseConfig, !demoArgument else {
            let demoWarning = hasFirebaseConfig ? nil : "Demo modu: işaretler örnektir. Seninkileri kimse görmez."
            return AppEnvironment(
                backend: .demo,
                repository: DemoReportRepository(),
                session: UserSession(userID: DemoReportRepository.demoUserID) { DemoReportRepository.demoUserID },
                // Simülatör konumu seyrek gelebilir: okuma eskidi diye işaretleme "konum bulunuyor"da kalmasın.
                location: LocationProvider(restampsFixes: isSimulator),
                // Demo örneklerinin kimlikleri her açılışta aynı; önceki açılıştan kalan takip soru sordurmasın.
                watched: WatchedReports(defaults: nil),
                // Aynı nedenle gizlenen ve son 24 saatin işaretleri yalnızca bellekte. `-demo` ile (arayüz testi)
                // hiçbir şey saklanmaz, test hep ilk açılıştan başlar. Plist'siz demo derlemesi (TestFlight) ise
                // kabul edilen kuralları, hafif işaret sayacını ve güvenlik hatırlatmalarını hatırlar: kurallar her
                // açılışta yeniden sorulmaz.
                device: DeviceState(defaults: demoArgument ? nil : .standard, persistsReports: false),
                setupWarning: demoWarning,
                nightReminderEnabled: nightReminderEnabled,
                areaClassifier: fixedAreaClassifier(arguments: arguments) ?? bundledAreaClassifier(),
                nearbyPromptEnabled: nearbyPromptEnabled,
                rejectsSimulatedFixes: false
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
        return firebaseEnvironment(
            backend: .firebase,
            nightReminderEnabled: nightReminderEnabled,
            nearbyPromptEnabled: nearbyPromptEnabled
        )
    }

    private static func firebaseEnvironment(
        backend: Backend,
        nightReminderEnabled: Bool,
        nearbyPromptEnabled: Bool
    ) -> AppEnvironment {
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
            nightReminderEnabled: nightReminderEnabled,
            areaClassifier: bundledAreaClassifier(),
            nearbyPromptEnabled: nearbyPromptEnabled,
            rejectsSimulatedFixes: backend == .firebase && !isSimulator
        )
    }

    /// Uygulamayla gelen alan ızgarası (shared/area-tr.bin, tools/area-grid ile üretilir). Dosya yoksa ya da
    /// bozuksa her yer serbest sayılır (fail-open): yanlış engel, eksik engelden kötüdür.
    private static func bundledAreaClassifier() -> any AreaClassifying {
        guard let url = Bundle.main.url(forResource: "area-tr", withExtension: "bin") else {
            logger.notice("area-tr.bin uygulamada yok; alan denetimi kapalı")
            return FixedAreaClassifier(nil)
        }
        guard let grid = AreaGrid(contentsOf: url) else {
            logger.error("area-tr.bin okunamadı ya da bozuk; alan denetimi kapalı")
            assertionFailure("area-tr.bin bozuk")
            return FixedAreaClassifier(nil)
        }
        return grid
    }

    /// `-areaClass water` gibi: her noktaya aynı sınıf. Tanınmayan değer yok sayılır.
    private static func fixedAreaClassifier(arguments: [String]) -> (any AreaClassifying)? {
        guard let index = arguments.firstIndex(of: areaClassArgument),
              index + 1 < arguments.count,
              let value = AreaClass(name: arguments[index + 1])
        else { return nil }
        return FixedAreaClassifier(value)
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
