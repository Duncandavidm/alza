import UIKit

/// Solo para recibir el token de APNs (notificaciones push). El
/// delegate de UNUserNotificationCenter sigue siendo
/// `NotificationPresenter` (ver MonAviApp.init) — este no lo toca.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = PushTokenFormatter.hexString(from: deviceToken)
        Task { @MainActor in
            PushTokenService.shared.didReceive(token: token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[Push] No se pudo registrar para notificaciones push: \(error.localizedDescription)")
        #endif
    }
}
