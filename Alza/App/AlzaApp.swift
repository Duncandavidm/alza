import SwiftUI

@main
struct AmadaiApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task { appState.start() }
        }
    }
}
