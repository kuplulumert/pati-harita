import Foundation
import Observation

/// Kullanıcı kimliği. Kayıt/giriş ekranı yoktur; kimlik yalnızca işaretlerin
/// kime ait olduğunu (kim koydu, kim ilgileniyor) ayırt etmek içindir.
@MainActor
@Observable
final class UserSession {
    private(set) var userID: String? = nil
    private let signIn: () async throws -> String

    init(userID: String?, signIn: @escaping () async throws -> String) {
        self.userID = userID
        self.signIn = signIn
    }

    /// Oturum yoksa açar; ağ yoksa artan aralıklarla yeniden dener.
    func ensureSignedIn() async {
        var delay: Double = 1
        while userID == nil, !Task.isCancelled {
            do {
                userID = try await signIn()
            } catch {
                try? await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, 30)
            }
        }
    }
}
