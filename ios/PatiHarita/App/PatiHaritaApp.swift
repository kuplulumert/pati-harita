import SwiftUI

@main
struct PatiHaritaApp: App {
    @State private var environment: AppEnvironment

    init() {
        _environment = State(initialValue: AppEnvironment.bootstrap())
    }

    var body: some Scene {
        WindowGroup {
            MapScreen(environment: environment)
        }
    }
}
