import Foundation

/// Un movimiento detectado en un aviso del banco que espera que el usuario
/// lo confirme ("Movimiento detectado… Toca para registrar"). Solo se
/// guardan los datos leidos, nunca el texto completo del aviso.
struct DetectedMovement: Codable, Identifiable, Hashable {
    let id: UUID
    var amount: Decimal
    var isIncome: Bool
    var counterpart: String?
    var last4: String?
    /// App o banco de donde vino el aviso, si el atajo lo manda (ej. "Yappy").
    var source: String?
    let detectedAt: Date
    /// Ya habia un movimiento igual (mismo monto, pocos minutos antes).
    var possibleDuplicate: Bool
    /// Cuenta elegida en la automatizacion (ej. la de Apple Pay), si la hay.
    var accountId: UUID? = nil
    /// Comercio aliado donde se pago (para recordar escanear la factura).
    var partnerName: String? = nil

    /// "Café La Esquina", o "Compra" / "Dinero recibido" si el aviso no
    /// trae el nombre.
    var title: String {
        if let counterpart, !counterpart.isEmpty { return counterpart }
        return isIncome ? "Dinero recibido" : "Compra"
    }

    var signedAmount: Decimal { isIncome ? abs(amount) : -abs(amount) }

    var amountText: String {
        (isIncome ? "+" : "−") + abs(amount).formatted(.appCurrency)
    }

    /// "Pago detectado" / "Ingreso detectado".
    var notificationTitle: String { isIncome ? "Ingreso detectado" : "Pago detectado" }

    /// "Café La Esquina · $12.40 (•4021)".
    var notificationBody: String {
        var body = "\(title) · \(abs(amount).formatted(.appCurrency))"
        if let last4 { body += " (•\(last4))" }
        return body
    }

    /// Gasto chico (hasta $10): "gasto hormiga", poco a poco suma.
    var isSmallExpense: Bool { !isIncome && abs(amount) <= 10 }
}

/// Movimientos por confirmar, guardados en el dispositivo. Los escribe la
/// accion de Atajos (DetectBankMovementIntent), aunque la app este cerrada,
/// y los muestra Hoy.
@MainActor
final class DetectedMovementStore: ObservableObject {
    static let shared = DetectedMovementStore()

    private static let storageKey = "monavi.detectedMovements"
    private static let cardAccountsKey = "monavi.detectedMovements.cardAccounts"
    /// Los que nadie confirmo en dos semanas se descartan solos.
    static let maxAge: TimeInterval = 14 * 24 * 3600
    static let maxCount = 50
    /// Dos avisos del mismo movimiento (la notificacion de la app y el SMS)
    /// llegan casi juntos: dentro de esta ventana, mismo monto, mismo tipo
    /// y misma tarjeta se cuentan como uno solo.
    static let sameAlertWindow: TimeInterval = 15 * 60

    @Published private(set) var pending: [DetectedMovement] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([DetectedMovement].self, from: data) else {
            pending = []
            return
        }
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        pending = decoded.filter { $0.detectedAt > cutoff }.sorted { $0.detectedAt > $1.detectedAt }
    }

    func movement(id: UUID) -> DetectedMovement? {
        load()
        return pending.first { $0.id == id }
    }

    /// true si se agrego; false si ya habia uno igual por confirmar (el
    /// mismo movimiento avisado dos veces).
    @discardableResult
    func add(_ movement: DetectedMovement) -> Bool {
        load()
        let isRepeat = pending.contains {
            $0.amount == movement.amount && $0.isIncome == movement.isIncome
                && ($0.last4 == nil || movement.last4 == nil || $0.last4 == movement.last4)
                && abs($0.detectedAt.timeIntervalSince(movement.detectedAt)) < Self.sameAlertWindow
        }
        guard !isRepeat else { return false }
        pending.insert(movement, at: 0)
        pending = Array(pending.prefix(Self.maxCount))
        save()
        return true
    }

    func remove(id: UUID) {
        load()
        pending.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: Self.storageKey)
        }
        NotificationCenter.default.post(name: .detectedMovementsChanged, object: nil)
    }

    /// Al cerrar sesion: borra los movimientos por confirmar y lo que se
    /// recordo de cada tarjeta (pertenecen a la cuenta anterior).
    func clearAll() {
        pending = []
        defaults.removeObject(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.cardAccountsKey)
        NotificationCenter.default.post(name: .detectedMovementsChanged, object: nil)
    }

    // MARK: - Tarjeta → cuenta

    /// La cuenta que el usuario eligio la ultima vez para esos 4 digitos.
    func accountId(forLast4 last4: String?) -> UUID? {
        guard let last4 else { return nil }
        let map = defaults.dictionary(forKey: Self.cardAccountsKey) as? [String: String] ?? [:]
        return map[last4].flatMap(UUID.init(uuidString:))
    }

    func remember(last4: String?, accountId: UUID) {
        guard let last4 else { return }
        var map = defaults.dictionary(forKey: Self.cardAccountsKey) as? [String: String] ?? [:]
        map[last4] = accountId.uuidString
        defaults.set(map, forKey: Self.cardAccountsKey)
    }
}

extension Notification.Name {
    /// Cambio la lista de movimientos por confirmar (nuevo, registrado o
    /// descartado): Hoy se actualiza.
    static let detectedMovementsChanged = Notification.Name("MonAviDetectedMovementsChanged")
}
