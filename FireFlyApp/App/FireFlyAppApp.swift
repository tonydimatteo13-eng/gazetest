import SwiftUI
import FireFlyCore

@main
struct FireFlyAppApp: App {
    @StateObject private var coordinator = SessionCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
        }
    }
}
