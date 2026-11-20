import Foundation
import Supabase
import UIKit

/// Reprograma TODOS los recordatorios locales con datos frescos del
/// servidor. Antes solo se programaban al abrir la pantalla de Cuentas por
/// pagar o de Recurrentes; si el usuario nunca entraba ahi, no recibia
/// avisos. Ahora se llama al abrir la app, al volver a ella, y al cambiar
/// algo en Ajustes > Notificaciones.
@MainActor
enum ReminderScheduler {
    static func refreshAll(userId: UUID) async {
        let status = await NotificationManager.authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        // Con permiso de notificaciones: pedir (o refrescar) el token de
        // APNs y subirlo para este usuario. El token llega despues al
        // AppDelegate; PushTokenService lo sube en cuanto lo tenga.
        UIApplication.shared.registerForRemoteNotifications()
        await PushTokenService.shared.sync(userId: userId)

        let supabase = SupabaseManager.shared.client

        let bills: [Bill]? = try? await supabase
            .from("bills")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
        if let bills { NotificationManager.scheduleBillReminders(bills) }

        let recurring: [RecurringTransaction]? = try? await supabase
            .from("recurring_transactions")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
        if let recurring { NotificationManager.scheduleRecurringReminders(recurring) }

        let invoices: [Invoice]? = try? await supabase
            .from("invoices")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
        if let invoices { NotificationManager.scheduleInvoiceReminders(invoices) }

        if let today = try? await TransactionsRepository.shared.fetchToday(userId: userId) {
            NotificationManager.scheduleDailyLogReminders(loggedToday: !today.isEmpty)
        }
    }

    /// Pide permiso una sola vez (la primera vez que se entra a la app ya
    /// con sesion), en vez de esconderlo en Ajustes.
    static func requestPermissionIfNeeded() async {
        guard await NotificationManager.authorizationStatus() == .notDetermined else { return }
        await NotificationManager.requestAuthorization()
    }
}
