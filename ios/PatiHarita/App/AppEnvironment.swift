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
/// - **demo**: plist yoksa ya da `-demo` argümanıyla; veriler yalnızca bellekte.
@MainActor
final class AppEnvironment {
    enum Backend {
        case firebase
        case emulator
        case demo
    }

    let backend: Backend
    let repository: ReportRepository
    let session: UserSession
    let location: LocationProvider
    /// Geliştiriciye gösterilecek kurulum uyarısı (ör. demo modu).
    let setupWarning: String?

    init(backend: Backend, repository: ReportRepository, session: UserSession, location: LocationProvider, setupWarning: String?) {
        self.backend = backend
        self.repository = repository
        self.session = session
        self.location = location
        self.setupWarning = setupWarning
    }

    static func bootstrap(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        if arguments.contains("-useEmulator") {
            configureFirebaseForEmulator()
            return firebaseEnvironment(backend: .emulator)
        }

        let hasFirebaseConfig = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
        guard hasFirebaseConfig, !arguments.contains("-demo") else {
            let demoWarning = hasFirebaseConfig ? nil : "Demo modu: GoogleService-Info.plist yok, işaretler yalnızca bu cihazda."
            return AppEnvironment(
                backend: .demo,
                repository: DemoReportRepository(),
                session: UserSession(userID: DemoReportRepository.demoUserID) { DemoReportRepository.demoUserID },
                location: LocationProvider(),
                setupWarning: demoWarning
            )
        }

        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        #endif
        FirebaseApp.configure()
        return firebaseEnvironment(backend: .firebase)
    }

    private static func firebaseEnvironment(backend: Backend) -> AppEnvironment {
        let auth = Auth.auth()
        return AppEnvironment(
            backend: backend,
            repository: FirestoreReportRepository(db: Firestore.firestore()),
            session: UserSession(userID: auth.currentUser?.uid) {
                // Hesap yok, form yok: herkes ilk açılışta sessizce anonim oturum açar.
                try await auth.signInAnonymously().user.uid
            },
            location: LocationProvider(),
            setupWarning: nil
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
