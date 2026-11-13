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
    /// Hora del recordatorio diario "¿Anotaste tus gastos de hoy?", en
    /// minutos desde la medianoche (la elige el usuario en Ajustes; por
    /// defecto 8:00 p. m.).
    static let dailyLogTimeKey = "dailyLogReminderMinutes"
    static let defaultDailyLogMinutes = 20 * 60

    static var dailyLogMinutes: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: dailyLogTimeKey) as? Int
            return clampedDailyLogMinutes(stored ?? defaultDailyLogMinutes)
        }
        set { UserDefaults.standard.set(clampedDailyLogMinutes(newValue), forKey: dailyLogTimeKey) }
    }

    /// Cualquier valor fuera de 0...1439 (dato corrupto) vuelve a las 8 p. m.
    static func clampedDailyLogMinutes(_ minutes: Int) -> Int {
        (0..<(24 * 60)).contains(minutes) ? minutes : defaultDailyLogMinutes
    }

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

        // Un "Recordarme más tarde" sigue vivo mientras el pago siga
        // pendiente; si ya se registro (o se desactivo/borro), se cancela.
        let pendingIds = Set(candidates.map(\.item.id))
        removePending(ids: items.filter { !pendingIds.contains($0.id) }.map { recurringSnoozeId($0.id) })

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
                        ? "Hoy es el día de \(item.name) (\(amountText)). ¿Ya lo recibiste? Mantén presionado para registrarlo."
                        : "\(item.name) por \(amountText). ¿Ya lo pagaste? Mantén presionado para registrarlo de una vez.",
                    date: atReminderHour(candidate.dueDate),
                    timeSensitive: !isIncome,
                    categoryIdentifier: isIncome ? recurringIncomeCategory : recurringExpenseCategory,
                    userInfo: [recurringIdKey: item.id.uuidString]
                )
            }
        }
    }

    // MARK: - Acciones del aviso de recurrente ("Sí, ya lo pagué")

    /// Categorias de notificacion con botones: una para gastos ("Sí, ya lo
    /// pagué") y otra para ingresos ("Sí, ya lo recibí"), las dos con
    /// "Recordarme más tarde" (+2 h).
    static let recurringExpenseCategory = "RECURRING_DUE_EXPENSE"
    static let recurringIncomeCategory = "RECURRING_DUE_INCOME"
    static let recurringConfirmAction = "RECURRING_CONFIRM"
    static let recurringSnoozeAction = "RECURRING_SNOOZE"
    static let recurringIdKey = "recurringId"
    static let recurringSnoozeInterval: TimeInterval = 2 * 60 * 60

    static func recurringSnoozeId(_ id: UUID) -> String { "recurring-snooze-\(id)" }

    /// Se registra una vez al arrancar (NotificationPresenter.install).
    /// Sin opciones en "Sí": iOS corre la accion en segundo plano, sin
    /// abrir la app (la sesion de Supabase vive en el llavero).
    static func registerNotificationCategories() {
        let snooze = UNNotificationAction(
            identifier: recurringSnoozeAction,
            title: "Recordarme más tarde",
            options: []
        )
        let paid = UNNotificationAction(
            identifier: recurringConfirmAction,
            title: "Sí, ya lo pagué",
            options: []
        )
        let received = UNNotificationAction(
            identifier: recurringConfirmAction,
            title: "Sí, ya lo recibí",
            options: []
        )
        let expense = UNNotificationCategory(
            identifier: recurringExpenseCategory,
            actions: [paid, snooze],
            intentIdentifiers: [],
            options: []
        )
        let income = UNNotificationCategory(
            identifier: recurringIncomeCategory,
            actions: [received, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([expense, income])
    }

    /// "Sí, ya lo pagué/recibí": registra el movimiento igual que el boton
    /// de Hoy (RecurringTransactionsViewModel.logPayment) y avisa con una
    /// notificacion local "Listo: registramos ...".
    @MainActor
    static func confirmRecurringFromNotification(idString: String?) async {
        guard let idString, let id = UUID(uuidString: idString) else { return }
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let item = try await RecurringTransactionsViewModel.fetchItem(id: id)
            removePending(ids: [recurringSnoozeId(id), "recurring-due-\(id)"])

            if let lastLoggedOn = item.lastLoggedOn,
               Calendar.current.isDate(lastLoggedOn, equalTo: Date(), toGranularity: .month) {
                sendImmediate(
                    id: "recurring-done-\(id)",
                    title: "Ya estaba registrado",
                    body: "\(item.name) ya está anotado este mes en MonAvi."
                )
                return
            }

            try await RecurringTransactionsViewModel.logPayment(for: item, userId: session.user.id)
            sendImmediate(
                id: "recurring-done-\(id)",
                title: "Listo",
                body: "Listo: registramos \(item.name) por \(formattedAmount(item.amount))."
            )
            // Si la app esta abierta, Hoy se recarga (DayJournalView).
            NotificationCenter.default.post(name: .recurringLoggedFromNotification, object: nil)
        } catch {
            sendImmediate(
                id: "recurring-failed-\(id)",
                title: "No se pudo registrar",
                body: "Abre MonAvi para registrar este pago fijo. Revisa tu conexión a internet.",
                userInfo: ["screen": "home"]
            )
        }
    }

    /// "Recordarme más tarde": el mismo aviso (con sus botones) en 2 horas.
    static func snoozeRecurring(_ content: UNNotificationContent) {
        guard let idString = content.userInfo[recurringIdKey] as? String,
              let id = UUID(uuidString: idString),
              let copy = content.mutableCopy() as? UNMutableNotificationContent
        else { return }
        let request = UNNotificationRequest(
            identifier: recurringSnoozeId(id),
            content: copy,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: recurringSnoozeInterval, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func sendImmediate(id: String, title: String, body: String, userInfo: [AnyHashable: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = brandSound
        content.threadIdentifier = "monavi-recordatorios"
        content.userInfo = userInfo
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
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
                let fireDate = calendar.date(
                    bySettingHour: dailyLogMinutes / 60,
                    minute: dailyLogMinutes % 60,
                    second: 0,
                    of: day
                ),
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

    // MARK: - Pago con tarjeta en un comercio aliado (Atajos/Wallet)

    static let partnerCardHintSentKey = "partnerCardHintSent"

    /// Identificador por comercio + dia: "partner-card-super 99-2026-11-07".
    static func partnerCardHintId(merchant: String, date: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04ld-%02ld-%02ld", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        return "partner-card-\(PartnerMerchantMatcher.normalized(merchant))-\(day)"
    }

    /// Despues de que un Atajo anota un pago con tarjeta en un comercio
    /// aliado: recuerda escanear la factura (la factura DGI es la prueba
    /// del pago con tarjeta y del bono). Maximo uno por comercio por dia.
    static func sendPartnerCardPaymentHint(merchantName: String, date: Date = Date()) {
        let id = partnerCardHintId(merchant: merchantName, date: date)
        let defaults = UserDefaults.standard
        var sent = defaults.stringArray(forKey: partnerCardHintSentKey) ?? []
        guard !sent.contains(id) else { return }
        sent.append(id)
        defaults.set(Array(sent.suffix(30)), forKey: partnerCardHintSentKey)

        let content = UNMutableNotificationContent()
        content.title = "Pagaste en \(merchantName) 💳"
        content.body = "Escanea tu factura para ganar tu cashback y el bono por pagar con tarjeta."
        content.sound = brandSound
        content.userInfo = ["screen": NotificationDestination.points.rawValue]

        let request = UNNotificationRequest(
            identifier: id,
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
    private static func schedule(
        id: String,
        title: String,
        body: String,
        date: Date,
        timeSensitive: Bool = false,
        categoryIdentifier: String? = nil,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = brandSound
        content.interruptionLevel = timeSensitive ? .timeSensitive : .active
        content.threadIdentifier = "monavi-recordatorios"
        if let categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }
        content.userInfo = userInfo

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
        NotificationManager.registerNotificationCategories()
    }

    // Se usan las versiones con completionHandler (no las async): iOS llama
    // a las async fuera del hilo principal y su completion tambien queda
    // fuera, lo que cierra la app con "Call must be made on main thread"
    // al tocar una notificacion. Aqui todo se resuelve en el hilo principal.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Con la app abierta iOS reproduce el sonido pero no siempre vibra:
        // se agrega la vibracion a mano para que se sienta igual.
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            completionHandler([.banner, .list, .sound])
        }
    }

    /// El usuario toco la notificacion: si trae un destino ("screen"),
    /// la app abre esa pantalla (ej. Puntos al sumar puntos). Los botones
    /// del aviso de un pago fijo ("Sí, ya lo pagué" / "Recordarme más
    /// tarde") se resuelven aqui; se le avisa a iOS que termino solo
    /// despues de registrar el movimiento.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let action = response.actionIdentifier
        Task { @MainActor in
            switch action {
            case NotificationManager.recurringConfirmAction:
                let idString = content.userInfo[NotificationManager.recurringIdKey] as? String
                await NotificationManager.confirmRecurringFromNotification(idString: idString)
            case NotificationManager.recurringSnoozeAction:
                NotificationManager.snoozeRecurring(content)
            default:
                let screen = content.userInfo["screen"] as? String
                NotificationRouter.shared.open(screen: screen)
            }
            completionHandler()
        }
    }
}

extension Notification.Name {
    /// Se registro un pago fijo desde el boton de la notificacion: Hoy se
    /// recarga si esta abierta.
    static let recurringLoggedFromNotification = Notification.Name("MonAviRecurringLoggedFromNotification")
}
