import SwiftUI

@main
struct MonAviApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task {
                    appState.start()
                    DiagnosticsReporter.shared.start()
                }
        }
    }
}
