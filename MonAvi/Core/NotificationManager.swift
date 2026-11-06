import Foundation
import UIKit
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

    /// iOS limita a 64 notificaciones locales pendientes por app — pasado
    /// ese tope, `add()` falla en silencio y el usuario deja de recibir
    /// avisos sin ningun error visible. Como facturas, cuentas y
    /// recurrentes se programan por separado (cada ViewModel no sabe
    /// cuantas tiene el resto), cada categoria se limita a sus items mas
    /// urgentes (los que vencen antes) para que la suma de las tres nunca
    /// se acerque al limite, incluso con un usuario de Negocio con decenas
    /// de facturas o cuentas activas. La ventana avanza sola: cada vez que
    /// el ViewModel refresca se vuelve a elegir el subconjunto mas urgente
    /// vigente en ese momento.
    ///
    /// Presupuesto (todo junto queda en 59 de 64):
    /// - cuentas por pagar: 8 x 3 avisos (antes, el dia, al dia siguiente) = 24
    /// - pagos fijos: 8 x 2 avisos (antes, el dia) = 16
    /// - facturas por cobrar: 6 x 2 avisos = 12
    /// - recordatorio diario de anotar: 7
    static let maxBills = 8
    static let maxRecurring = 8
    static let maxInvoices = 6
    static let dailyLogDays = 7

    /// Avisos que puede programar cada categoria por item (ver el desglose
    /// de arriba): cuentas por pagar 3 (antes, el dia, al dia siguiente),
    /// pagos fijos 2, facturas 2, y el diario 1 por dia. Se exponen para
    /// poder fijar en un test que la suma nunca pase el tope de iOS (64).
    static let remindersPerBill = 3
    static let remindersPerRecurring = 2
    static let remindersPerInvoice = 2

    /// Peor caso de avisos pendientes programados a la vez — debe quedar
    /// holgadamente por debajo de 64 (iOS descarta en silencio los que
    /// pasen de ese tope).
    static var worstCaseScheduledCount: Int {
        maxBills * remindersPerBill
            + maxRecurring * remindersPerRecurring
            + maxInvoices * remindersPerInvoice
            + dailyLogDays
    }

    /// Sonido propio de MonAvi para todos los avisos (tres notas que
    /// suben, 1.3 s, en Resources/Sounds). iOS vibra junto con el sonido
    /// segun los ajustes de Sonidos y vibracion del usuario.
    static let brandSound = UNNotificationSound(named: UNNotificationSoundName("monavi-alert.wav"))

    static let dailyLogReminderKey = "dailyLogReminderEnabled"
    /// Hora del recordatorio diario "¿Anotaste tus gastos de hoy?".
    static let dailyLogHour = 20

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

    /// Si el usuario da permiso, de una vez se registra para push
    /// (APNs) — el token llega al AppDelegate y lo sube PushTokenService.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return granted
    }

    // MARK: - Facturas (cuentas por cobrar)

    /// Dos avisos por factura pendiente: uno `reminderLeadDays` antes del
    /// vencimiento, y uno justo el dia que vence.
    static func scheduleInvoiceReminders(_ invoices: [Invoice]) {
        for invoice in invoices {
            removePending(ids: ["invoice-lead-\(invoice.id)", "invoice-overdue-\(invoice.id)"])
        }

        let pending = invoices
            .filter { $0.status != .pagada && $0.status != .anulada && $0.dueDateValue != nil }
            .sorted { $0.dueDateValue! < $1.dueDateValue! }
            .prefix(maxInvoices)

        for invoice in pending {
            let leadId = "invoice-lead-\(invoice.id)"
            let overdueId = "invoice-overdue-\(invoice.id)"
            let dueDate = invoice.dueDateValue!
            let amountText = formattedAmount(invoice.total)

            if let leadDate = Calendar.current.date(byAdding: .day, value: -reminderLeadDays, to: dueDate),
               leadDate > Date() {
                schedule(
                    id: leadId,
                    title: "Factura por vencer",
                    body: "La factura de \(invoice.customerName) por \(amountText) vence en \(reminderLeadDays) día\(reminderLeadDays == 1 ? "" : "s").",
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
            removePending(ids: ["bill-lead-\(bill.id)", "bill-overdue-\(bill.id)", "bill-late-\(bill.id)"])
        }

        // Incluye las que vencieron ayer: todavia les toca el aviso de
        // "vencio ayer" si siguen pendientes.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let pending = bills
            .filter { $0.status == .pendiente && $0.dueDateValue >= yesterday }
            .sorted { $0.dueDateValue < $1.dueDateValue }
            .prefix(maxBills)

        for bill in pending {
            let leadId = "bill-lead-\(bill.id)"
            let overdueId = "bill-overdue-\(bill.id)"
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
                    body: "Recuerda tu pago de \(bill.name) por \(amountText) — vence en \(reminderLeadDays) día\(reminderLeadDays == 1 ? "" : "s")\(urgency).",
                    date: atReminderHour(leadDate)
                )
            }

            if atReminderHour(dueDate) > Date() {
                schedule(
                    id: overdueId,
                    title: "Cuenta vence hoy",
                    body: "\(bill.name) por \(amountText) vence hoy. Cuando la pagues, márcala como pagada en MonAvi.",
                    date: atReminderHour(dueDate),
                    timeSensitive: true
                )
            }

            // Si se marca como pagada antes, el siguiente refresh lo cancela.
            if let lateDate = Calendar.current.date(byAdding: .day, value: 1, to: dueDate),
               atReminderHour(lateDate) > Date() {
                schedule(
                    id: "bill-late-\(bill.id)",
                    title: "Cuenta vencida",
                    body: "\(bill.name) por \(amountText) venció ayer y sigue pendiente. ¿Ya la pagaste? Regístralo en MonAvi.",
                    date: atReminderHour(lateDate),
                    timeSensitive: true
                )
            }
        }
    }

    // MARK: - Recurrentes (dia fijo del mes: luz el 20, tarjeta el 15...)

    /// Por cada pago fijo: un aviso `reminderLeadDays` antes (solo gastos)
    /// y otro el mismo dia para que no se olvide registrarlo ("Hoy toca
    /// pagar la luz" / "¿Ya recibiste tu salario?"). Si ese mes ya se
    /// registro, no se avisa.
    static func scheduleRecurringReminders(_ items: [RecurringTransaction]) {
        for item in items {
            removePending(ids: ["recurring-\(item.id)", "recurring-due-\(item.id)"])
        }

        let calendar = Calendar.current
        let candidates = items
            .filter(\.active)
            .compactMap { item -> (item: RecurringTransaction, dueDate: Date)? in
                guard let dueDate = nextOccurrence(dayOfMonth: item.dayOfMonth) else { return nil }
                if let lastLoggedOn = item.lastLoggedOn,
                   calendar.isDate(lastLoggedOn, equalTo: dueDate, toGranularity: .month) {
                    return nil // ya registrado este mes
                }
                return (item, dueDate)
            }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(maxRecurring)

        for candidate in candidates {
            let item = candidate.item
            let amountText = formattedAmount(item.amount)

            if !item.movementType.isInflow,
               let leadDate = calendar.date(byAdding: .day, value: -reminderLeadDays, to: candidate.dueDate),
               atReminderHour(leadDate) > Date() {
                schedule(
                    id: "recurring-\(item.id)",
                    title: "Pago fijo por vencer",
                    body: "Recuerda tu pago de \(item.name) por \(amountText) — vence en \(reminderLeadDays) día\(reminderLeadDays == 1 ? "" : "s").",
                    date: atReminderHour(leadDate)
                )
            }

            if atReminderHour(candidate.dueDate) > Date() {
                let isIncome = item.movementType.isInflow
                schedule(
                    id: "recurring-due-\(item.id)",
                    title: isIncome ? "¿Ya recibiste \(item.name)?" : "Hoy toca pagar \(item.name)",
                    body: isIncome
                        ? "Hoy es el día de \(item.name) (\(amountText)). Cuando lo recibas, regístralo en MonAvi."
                        : "\(item.name) por \(amountText). Cuando lo pagues, regístralo en MonAvi para llevar tus cuentas al día.",
                    date: atReminderHour(candidate.dueDate),
                    timeSensitive: !isIncome
                )
            }
        }
    }

    // MARK: - Recordatorio diario de anotar

    static var isDailyLogReminderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: dailyLogReminderKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: dailyLogReminderKey) }
    }

    /// "¿Anotaste tus gastos de hoy?" a las 8 p. m. los proximos 7 dias.
    /// Si hoy ya anoto algo, empieza mañana. Se reprograma al abrir la app
    /// y cada vez que se anota un movimiento, asi que no avisa un dia en
    /// que ya anoto.
    static func scheduleDailyLogReminders(loggedToday: Bool) {
        removePending(ids: (0..<dailyLogDays).map { "daily-log-\($0)" })
        guard isDailyLogReminderEnabled else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let messages = [
            "¿Anotaste tus gastos de hoy? Toma 10 segundos y mantienes tu racha 🔥",
            "Un minuto para tus finanzas: anota lo que gastaste hoy.",
            "¿Qué gastaste hoy? Anótalo antes de que se te olvide.",
        ]

        for offset in 0..<dailyLogDays {
            if offset == 0 && loggedToday { continue }
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: today),
                let fireDate = calendar.date(bySettingHour: dailyLogHour, minute: 0, second: 0, of: day),
                fireDate > Date()
            else { continue }

            schedule(
                id: "daily-log-\(offset)",
                title: "MonAvi",
                body: messages[offset % messages.count],
                date: fireDate
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
        content.title = "Qué pagar primero"
        content.sound = brandSound
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
        content.title = "Te sobró dinero: qué hacer con él"
        content.body = message
        content.sound = brandSound

        let request = UNNotificationRequest(
            identifier: "surplus-advice-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Prueba

    /// Desde Ajustes: un aviso de prueba a los 5 segundos para escuchar el
    /// sonido de MonAvi y sentir la vibracion (sirve tambien en el
    /// simulador). Da tiempo de salir de la app para verlo como llega.
    static func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Hoy toca pagar la luz"
        content.body = "Así te van a llegar los recordatorios de MonAvi: con este sonido y vibración."
        content.sound = brandSound
        content.threadIdentifier = "monavi-recordatorios"

        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
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
    static func nextOccurrence(dayOfMonth: Int, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start else { return nil }

        // Un pago "el 31" cae el ultimo dia en meses mas cortos (28/29/30),
        // en vez de saltar al mes siguiente.
        func occurrence(inMonthStarting start: Date) -> Date? {
            let daysInMonth = calendar.range(of: .day, in: .month, for: start)?.count ?? 28
            let day = min(max(dayOfMonth, 1), daysInMonth)
            return calendar.date(byAdding: .day, value: day - 1, to: start)
        }

        if let thisMonth = occurrence(inMonthStarting: monthStart),
           thisMonth >= calendar.startOfDay(for: now) {
            return thisMonth
        }
        guard let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return nil }
        return occurrence(inMonthStarting: nextMonthStart)
    }

    private static func atReminderHour(_ date: Date) -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    private static func formattedAmount(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "USD"))
    }

    /// `timeSensitive`: para los avisos del dia de pago (o de un pago
    /// vencido) — iOS los deja sonar y vibrar aunque el usuario tenga
    /// activado un modo de concentracion. El resto son avisos normales.
    private static func schedule(id: String, title: String, body: String, date: Date, timeSensitive: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = brandSound
        content.interruptionLevel = timeSensitive ? .timeSensitive : .active
        content.threadIdentifier = "monavi-recordatorios"

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static func removePending(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

/// Sin esto, iOS no muestra ninguna notificacion mientras la app esta
/// abierta (por ejemplo, el "Qué pagar primero" justo despues de anotar un
/// ingreso). Se instala una vez al arrancar la app (MonAviApp).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Con la app abierta iOS reproduce el sonido pero no siempre vibra:
        // se agrega la vibracion a mano para que se sienta igual.
        await MainActor.run {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        return [.banner, .list, .sound]
    }

    /// El usuario toco la notificacion: si trae un destino ("screen"),
    /// la app abre esa pantalla (ej. Puntos al sumar puntos).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let screen = response.notification.request.content.userInfo["screen"] as? String
        await MainActor.run {
            NotificationRouter.shared.open(screen: screen)
        }
    }
}
