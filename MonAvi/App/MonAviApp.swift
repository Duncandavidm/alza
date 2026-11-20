import SwiftUI

@main
struct MonAviApp: App {
    /// Solo para recibir el token de APNs (ver AppDelegate). Las
    /// notificaciones en primer plano siguen en NotificationPresenter.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        NotificationPresenter.shared.install()
    }

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
