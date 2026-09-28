import Foundation

/// Sürüm, kurallar ve iletişim bilgileri.
enum AppInfo {
    /// İlk açılıştaki kurallar sayfasının sürümü. Kurallar değişince artırılır: herkes yeniden kabul eder.
    static let termsVersion = 1
    /// Şikayet ve iletişim adresi. Boşken uygulamada hiçbir yerde gösterilmez.
    static let supportEmail = ""
    static let termsURL = URL(string: "https://github.com/kuplulumert/pati-harita/blob/main/docs/kullanim-kosullari.md")!
    static let privacyURL = URL(string: "https://github.com/kuplulumert/pati-harita/blob/main/docs/gizlilik-politikasi.md")!

    /// Çalışan derlemenin numarası (CFBundleVersion, TestFlight'ta her yüklemede artar); okunamazsa `nil`.
    static let build: Int? = buildNumber(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)

    static func buildNumber(_ value: String?) -> Int? {
        value.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// `config/public.minBuild`: bu derleme artık desteklenmiyor mu? Numara okunamazsa kimse engellenmez.
    static func requiresUpdate(build: Int?, minBuild: Int?) -> Bool {
        guard let build, let minBuild else { return false }
        return build < minBuild
    }

    /// `supportEmail`e hazır e-posta; adres yoksa `nil`.
    static func supportMailURL(subject: String, body: String) -> URL? {
        guard !supportEmail.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
