import Foundation
import UserNotifications

/// Notificaciones locales (no remotas/push de servidor) — todo lo que
/// dispara una notificacion aqui ya es informacion que el propio
/// dispositivo conoce de antemano (fecha de vencimiento de una factura,
/// el dia fijo de un recurrente) o que acaba de calcular en el momento
/// (el consejo de pago al registrar un ingreso), asi que no hace falta
/// un servidor empujando nada por APNs — el telefono programa sus propios
/// avisos con UNUserNotificationCenter.
///
/// Cada tipo de recordatorio se reprograma por completo (se cancelan los
/// pendientes y se vuelven a crear) cada vez que su ViewModel refresca o
/// cambia algo, usando un identifier estable por registro
/// ("bill-lead-<id>", etc.) — asi nunca quedan duplicados ni recordatorios
/// viejos de algo que ya se borro o se marco como pagado.
enum NotificationManager {
    static let reminderLeadDaysKey = "reminderLeadDays"
    static let defaultLeadDays = 3
    /// Rango razonable para el picker de Ajustes — de 1 a 7 dias.
    static let leadDaysRange = 1...7

    static var reminderLeadDays: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: reminderLeadDaysKey)
            return stored > 0 ? stored : defaultLeadDays
        }
        set {
            UserDefaults.standard.set(newValue, forKey: reminderLeadDaysKey)
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - Facturas (cuentas por cobrar)

    /// Dos avisos por factura pendiente: uno `reminderLeadDays` antes del
    /// vencimiento, y uno justo el dia que vence.
    static func scheduleInvoiceReminders(_ invoices: [Invoice]) {
        for invoice in invoices {
            let leadId = "invoice-lead-\(invoice.id)"
            let overdueId = "invoice-overdue-\(invoice.id)"
            removePending(ids: [leadId, overdueId])

            guard
                invoice.status != .pagada, invoice.status != .anulada,
                let dueDate = invoice.dueDateValue
            else { continue }

            let amountText = formattedAmount(invoice.total)

            if let leadDate = Calendar.current.date(byAdding: .day, value: -reminderLeadDays, to: dueDate),
               leadDate > Date() {
                schedule(
                    id: leadId,
                    title: "Factura por vencer",
                    body: "La factura de \(invoice.customerName) por \(amountText) vence en \(reminderLeadDays) dia\(reminderLeadDays == 1 ? "" : "s").",
                    date: atReminderHour(leadDate)
                )
            }

            if dueDate > Date() {
                schedule(
                    id: overdueId,
                    title: "Factura vence hoy",
                    body: "La factura de \(invoice.customerName) por \(amountText) vence hoy.",
                    date: atReminderHour(dueDate)
                )
            }
        }
    }

    // MARK: - Cuentas por pagar

    static func scheduleBillReminders(_ bills: [Bill]) {
        for bill in bills {
            let leadId = "bill-lead-\(bill.id)"
            let overdueId = "bill-overdue-\(bill.id)"
            removePending(ids: [leadId, overdueId])

            guard bill.status == .pendiente else { continue }

            let dueDate = bill.dueDateValue
            let amountText = formattedAmount(bill.amount)
            let urgency = (bill.priority == .critica || bill.priority == .alta)
                ? " — prioridad \(bill.priority.displayName.lowercased())"
                : ""

            if let leadDate = Calendar.current.date(byAdding: .day, value: -reminderLeadDays, to: dueDate),
               leadDate > Date() {
                schedule(
                    id: leadId,
                    title: "Cuenta por vencer",
                    body: "Recuerda tu pago de \(bill.name) por \(amountText) — vence en \(reminderLeadDays) dia\(reminderLeadDays == 1 ? "" : "s")\(urgency).",
                    date: atReminderHour(leadDate)
                )
            }

            if dueDate > Date() {
                schedule(
                    id: overdueId,
                    title: "Cuenta vence hoy",
                    body: "\(bill.name) por \(amountText) vence hoy.",
                    date: atReminderHour(dueDate)
                )
            }
        }
    }

    // MARK: - Recurrentes (dia fijo del mes: luz el 20, tarjeta el 15...)

    static func scheduleRecurringReminders(_ items: [RecurringTransaction]) {
        for item in items {
            let id = "recurring-\(item.id)"
            removePending(ids: [id])

            guard item.active, item.movementType != .ingreso else { continue }
            guard let dueDate = nextOccurrence(dayOfMonth: item.dayOfMonth) else { continue }
            guard
                let leadDate = Calendar.current.date(byAdding: .day, value: -reminderLeadDays, to: dueDate),
                leadDate > Date()
            else { continue }

            schedule(
                id: id,
                title: "Pago fijo por vencer",
                body: "Recuerda tu pago de \(item.name) por \(formattedAmount(item.amount)) — vence en \(reminderLeadDays) dia\(reminderLeadDays == 1 ? "" : "s").",
                date: atReminderHour(leadDate)
            )
        }
    }

    // MARK: - Consejo de pago al registrar un ingreso

    /// A diferencia de los recordatorios de arriba, esta se dispara de
    /// inmediato (no se programa a futuro) — es el mismo consejo que ya
    /// se muestra en pantalla via PaymentAdviceView, solo que tambien
    /// como notificacion para que quede ahi si sales de la app.
    static func sendPaymentPriorityNotification(items: [PaymentAdviceItem]) {
        guard let first = items.first else { return }

        let content = UNMutableNotificationContent()
        content.title = "Que pagar primero"
        content.sound = .default
        if items.count == 1 {
            content.body = "\(first.name) — \(formattedAmount(Decimal(first.amount))) (\(first.dueInfo))"
        } else {
            content.body = "1. \(first.name) — \(formattedAmount(Decimal(first.amount))). Tienes \(items.count - 1) mas por priorizar."
        }

        let request = UNNotificationRequest(
            identifier: "payment-priority-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Sobrante al terminar de pagar todas las cuentas

    /// Se dispara una sola vez, cuando `BillsViewModel` detecta que ya no
    /// queda ninguna cuenta pendiente y sobro dinero en la cuenta — el
    /// mensaje ya viene armado por `SurplusAdviceService` con datos reales
    /// del cliente (su deuda, su meta de ahorro, o un consejo por rango).
    static func sendSurplusAdvice(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Te sobro dinero — que hacer con el"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "surplus-advice-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    /// La proxima fecha en que cae `dayOfMonth` — hoy mismo si todavia no
    /// ha pasado este mes, si no el mes que viene. Evita el problema de
    /// que un disparador repetitivo "cada dia X del mes" no sepa manejar
    /// bien restar dias cerca del limite de un mes (28/29/30/31) — en vez
    /// de eso, se reprograma la proxima ocurrencia cada vez que el
    /// ViewModel refresca.
    private static func nextOccurrence(dayOfMonth: Int) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month], from: now)
        components.day = dayOfMonth
        guard let thisMonth = calendar.date(from: components) else { return nil }

        if thisMonth >= calendar.startOfDay(for: now) {
            return thisMonth
        }
        return calendar.date(byAdding: .month, value: 1, to: thisMonth)
    }

    private static func atReminderHour(_ date: Date) -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    private static func formattedAmount(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "USD"))
    }

    private static func schedule(id: String, title: String, body: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static func removePending(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
