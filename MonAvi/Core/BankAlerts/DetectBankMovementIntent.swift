import AppIntents
import Foundation
import Supabase
import UserNotifications

/// "Detectar movimiento del banco": la llama una automatizacion de Atajos
/// (disparador Notificación de la app del banco o de Yappy, Mensaje o
/// Correo) con el texto del aviso. MonAvi lo lee en el dispositivo y, si es
/// un movimiento, lo deja por confirmar y avisa "Movimiento detectado…
/// Toca para registrar". Nunca guarda sin que el usuario confirme.
/// Corre sin abrir la app y sin mostrar nada si el aviso no era un
/// movimiento (un codigo de seguridad, una promocion…).
struct DetectBankMovementIntent: AppIntent {
    static var title: LocalizedStringResource = "Detectar movimiento del banco"
    static var description = IntentDescription(
        "Lee el aviso de tu banco o billetera (notificación, SMS o correo) y, si es una compra o un dinero recibido, te pregunta si quieres registrarlo en MonAvi. El texto se lee en tu teléfono y no se guarda."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Aviso", description: "El texto de la notificación, el SMS o el correo del banco.")
    var text: String

    @Parameter(title: "App o banco (opcional)", description: "Ej. Yappy, Banco General. Solo para mostrarlo.")
    var source: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Detectar movimiento en \(\.$text)") {
            \.$source
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = await DetectedMovementActions.detect(text: text, source: source)
        return .result()
    }
}

/// Lo que se puede hacer con un movimiento detectado: detectarlo (Atajos o
/// "Probar" en la guia), registrarlo (boton de la notificacion o la hoja de
/// revision) o descartarlo.
@MainActor
enum DetectedMovementActions {
    nonisolated static let notificationCategory = "monavi.detected-movement"
    nonisolated static let registerAction = "monavi.detected.register"
    nonisolated static let reviewAction = "monavi.detected.review"
    nonisolated static let dismissAction = "monavi.detected.dismiss"
    nonisolated static let idKey = "detectedId"
    /// Ventana para avisar "parece que ya lo anotaste" (Apple Pay o a mano).
    static let duplicateWindow: TimeInterval = 45 * 60

    nonisolated static func notificationId(_ id: UUID) -> String { "detected-\(id.uuidString)" }

    /// Lee el aviso y, si es un movimiento nuevo, lo deja por confirmar y
    /// manda la notificacion. Devuelve el movimiento (nil si no era uno o
    /// si ya estaba por confirmar).
    @discardableResult
    static func detect(text: String, source: String?, now: Date = Date()) async -> DetectedMovement? {
        guard let session = try? await SupabaseManager.shared.client.auth.session,
              let parsed = BankAlertParser.parse(text) else { return nil }

        let trimmedSource = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        var movement = DetectedMovement(
            id: UUID(),
            amount: parsed.amount,
            isIncome: parsed.isIncome,
            counterpart: parsed.counterpart,
            last4: parsed.last4,
            source: (trimmedSource?.isEmpty ?? true) ? nil : trimmedSource,
            detectedAt: now,
            possibleDuplicate: false
        )
        return await keepForConfirmation(movement, userId: session.user.id, now: now)
    }

    /// Pago con Apple Pay (automatizacion "Transacción" de Wallet, ver
    /// AddMonAviExpenseIntent): queda por confirmar igual que un aviso del
    /// banco, con la cuenta que se eligio en la automatizacion.
    @discardableResult
    static func detectPayment(amount: Decimal, merchant: String, accountId: UUID?, now: Date = Date()) async -> DetectedMovement? {
        guard amount > 0, let session = try? await SupabaseManager.shared.client.auth.session else { return nil }
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        var partner: String?
        if !name.isEmpty { partner = await partnerName(for: name) }
        let movement = DetectedMovement(
            id: UUID(),
            amount: amount,
            isIncome: false,
            counterpart: name.isEmpty ? nil : name,
            last4: nil,
            source: "Apple Pay",
            detectedAt: now,
            possibleDuplicate: false,
            accountId: accountId,
            partnerName: partner
        )
        return await keepForConfirmation(movement, userId: session.user.id, now: now)
    }

    private static func keepForConfirmation(_ detected: DetectedMovement, userId: UUID, now: Date) async -> DetectedMovement? {
        var movement = detected
        movement.possibleDuplicate = await alreadyLogged(movement, userId: userId, now: now)
        guard DetectedMovementStore.shared.add(movement) else { return nil }
        sendDetectedNotification(movement)
        return movement
    }

    /// Comercio aliado activo con ese nombre (best-effort: si falla, nil).
    private static func partnerName(for merchant: String) async -> String? {
        struct Row: Decodable { let name: String }
        let rows: [Row] = (try? await SupabaseManager.shared.client
            .from("partner_merchants")
            .select("name")
            .eq("status", value: "active")
            .execute()
            .value) ?? []
        return PartnerMerchantMatcher.match(merchant: merchant, partnerNames: rows.map(\.name))
    }

    /// Ya hay un movimiento con el mismo monto en los ultimos minutos (ej.
    /// la automatizacion de Apple Pay lo anoto, o el usuario a mano).
    private static func alreadyLogged(_ movement: DetectedMovement, userId: UUID, now: Date) async -> Bool {
        let recent = (try? await TransactionsRepository.shared.fetchSince(
            userId: userId, date: now.addingTimeInterval(-duplicateWindow), limit: 50
        )) ?? []
        return recent.contains { $0.amount == movement.signedAmount }
    }

    // MARK: - Registrar

    /// La cuenta sugerida: la que el usuario eligio antes para esa tarjeta;
    /// si no, la primera de uso diario (no tarjeta de credito, prestamo,
    /// ahorro ni inversion); si no, la primera.
    static func suggestedAccountId(for movement: DetectedMovement, accounts: [Account]) -> UUID? {
        if let chosen = movement.accountId, accounts.contains(where: { $0.id == chosen }) {
            return chosen
        }
        if let remembered = DetectedMovementStore.shared.accountId(forLast4: movement.last4),
           accounts.contains(where: { $0.id == remembered }) {
            return remembered
        }
        let everyday = accounts.first { ![.creditCard, .loan, .savings, .investment].contains($0.type) }
        return (everyday ?? accounts.first)?.id
    }

    nonisolated static func suggestedCategory(for movement: DetectedMovement) -> TransactionCategory? {
        let text = movement.counterpart ?? ""
        if movement.isIncome {
            return CategoryKeywordGuesser.category(for: text, isInflow: true) ?? .income
        }
        return CategoryKeywordGuesser.category(for: text, isInflow: false)
    }

    /// Guarda el movimiento (con lo que el usuario ajusto en la revision) y
    /// lo saca de la lista por confirmar.
    static func register(
        _ movement: DetectedMovement,
        userId: UUID,
        accountId: UUID,
        amount: Decimal? = nil,
        isIncome: Bool? = nil,
        category: TransactionCategory?,
        description: String?,
        rememberCard: Bool = true
    ) async throws {
        let income = isIncome ?? movement.isIncome
        let type: MovementType = income ? .ingreso : .gasto
        let magnitude = abs(amount ?? movement.amount)
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await TransactionsRepository.shared.add(
            NewTransaction(
                userId: userId,
                accountId: accountId,
                amount: type.signedAmount(from: magnitude),
                movementType: type,
                category: category?.rawValue,
                description: (trimmed?.isEmpty ?? true) ? movement.title : trimmed,
                occurredAt: movement.detectedAt
            )
        )
        if rememberCard { DetectedMovementStore.shared.remember(last4: movement.last4, accountId: accountId) }
        DetectedMovementStore.shared.remove(id: movement.id)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationId(movement.id)])
        // Pago en un comercio aliado: recordar escanear la factura (cashback).
        if let partner = movement.partnerName, !income {
            NotificationManager.sendPartnerCardPaymentHint(merchantName: partner)
        }
    }

    /// Boton "Registrar" de la notificacion (sin abrir la app): usa la
    /// cuenta y la categoria sugeridas.
    static func registerFromNotification(idString: String?) async {
        guard let idString, let id = UUID(uuidString: idString),
              let movement = DetectedMovementStore.shared.movement(id: id) else { return }
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let accounts: [Account] = try await SupabaseManager.shared.client
                .from("accounts")
                .select()
                .eq("user_id", value: session.user.id)
                .order("created_at", ascending: true)
                .execute()
                .value
            guard let accountId = suggestedAccountId(for: movement, accounts: accounts) else {
                sendSimple(id: "detected-failed-\(id)", title: "Falta una cuenta",
                           body: "Crea una cuenta en MonAvi para registrar tus movimientos.", userInfo: ["screen": "home"])
                return
            }
            try await register(movement, userId: session.user.id, accountId: accountId,
                               category: suggestedCategory(for: movement), description: nil, rememberCard: false)
            let name = accounts.first { $0.id == accountId }?.name ?? "tu cuenta"
            sendSimple(id: "detected-done-\(id)", title: "Listo ✓",
                       body: "Registramos \(movement.title) por \(abs(movement.amount).formatted(.currency(code: "USD"))) en \(name).")
            NotificationCenter.default.post(name: .recurringLoggedFromNotification, object: nil)
        } catch {
            sendSimple(id: "detected-failed-\(id)", title: "No se pudo registrar",
                       body: "Abre MonAvi para registrar este movimiento. Revisa tu conexión a internet.",
                       userInfo: ["screen": "detected", idKey: idString])
        }
    }

    static func dismiss(idString: String?) {
        guard let idString, let id = UUID(uuidString: idString) else { return }
        DetectedMovementStore.shared.remove(id: id)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationId(id)])
    }

    // MARK: - Notificaciones

    private static func sendDetectedNotification(_ movement: DetectedMovement) {
        let content = UNMutableNotificationContent()
        content.title = movement.notificationTitle
        if let source = movement.source { content.subtitle = source }
        content.body = movement.notificationBody + (movement.possibleDuplicate
            ? " · Parece que ya lo anotaste: revísalo antes de guardarlo."
            : " · Toca para registrar.")
        content.sound = NotificationManager.brandSound
        content.categoryIdentifier = notificationCategory
        content.threadIdentifier = "monavi-detectados"
        content.userInfo = ["screen": "detected", idKey: movement.id.uuidString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: notificationId(movement.id),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        ))
    }

    private static func sendSimple(id: String, title: String, body: String, userInfo: [AnyHashable: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = NotificationManager.brandSound
        content.threadIdentifier = "monavi-detectados"
        content.userInfo = userInfo
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        ))
    }

    nonisolated static var notificationCategoryDefinition: UNNotificationCategory {
        UNNotificationCategory(
            identifier: notificationCategory,
            actions: [
                UNNotificationAction(identifier: registerAction, title: "Registrar", options: []),
                UNNotificationAction(identifier: reviewAction, title: "Revisar y editar", options: [.foreground]),
                UNNotificationAction(identifier: dismissAction, title: "Descartar", options: [.destructive]),
            ],
            intentIdentifiers: [],
            options: []
        )
    }
}
