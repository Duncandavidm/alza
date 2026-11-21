import Foundation
import Supabase

/// Fecha de disponibilidad de una cuenta de ahorro (logica pura). La fecha
/// se guarda como "yyyy-MM-dd" y se compara por dia del calendario local.
enum SavingsAvailability {
    static func date(from value: String?, calendar: Calendar = .current) -> Date? {
        guard let value else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
    }

    /// Todavia bloqueada (la fecha es despues de hoy).
    static func isLocked(_ account: Account, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let date = date(from: account.availableOn, calendar: calendar) else { return false }
        return date > calendar.startOfDay(for: now)
    }

    /// Llego (o ya paso) el dia que marco y todavia tiene dinero: hay que
    /// preguntar "¿Ya está disponible tu dinero?".
    static func isDue(_ account: Account, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard account.balance > 0, let date = date(from: account.availableOn, calendar: calendar) else { return false }
        return date <= calendar.startOfDay(for: now)
    }

    /// "1 de diciembre de 2026" (o "1 de diciembre" si es este año).
    static func label(_ value: String?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date = date(from: value, calendar: calendar) else { return nil }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style = sameYear
            ? Date.FormatStyle().day().month(.wide)
            : Date.FormatStyle().day().month(.wide).year()
        return date.formatted(style.locale(Locale(identifier: "es_PA")))
    }

    /// Fecha sugerida para un ahorro bloqueado: el 1 de diciembre (de este
    /// año, o del siguiente si ya paso).
    static func suggestedDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let year = calendar.component(.year, from: now)
        let thisYear = calendar.date(from: DateComponents(year: year, month: 12, day: 1)) ?? now
        return thisYear > now ? thisYear : (calendar.date(byAdding: .year, value: 1, to: thisYear) ?? thisYear)
    }
}

/// Mover dinero entre cuentas propias (ej. el ahorro que se libero a la
/// cuenta principal). Es una transferencia: sale de una y entra a la otra,
/// no cuenta como gasto ni como ingreso. Si pasa todo, la de origen queda
/// en $0.
@MainActor
enum AccountTransfers {
    static func transfer(amount: Decimal, from source: Account, to destination: Account, userId: UUID) async throws {
        let value = abs(amount)
        guard value > 0, source.id != destination.id else { return }
        try await TransactionsRepository.shared.add(
            NewTransaction(
                userId: userId,
                accountId: source.id,
                amount: -value,
                movementType: .transferencia,
                category: TransactionCategory.transfers.rawValue,
                description: "Transferencia a \(destination.name)",
                occurredAt: Date()
            )
        )
        try await TransactionsRepository.shared.add(
            NewTransaction(
                userId: userId,
                accountId: destination.id,
                amount: value,
                movementType: .transferencia,
                category: TransactionCategory.transfers.rawValue,
                description: "Transferencia desde \(source.name)",
                occurredAt: Date()
            )
        )
        // Si ya llego su fecha, el dinero ya esta libre: se quita el
        // bloqueo para no volver a preguntar.
        if source.availableOn != nil && !SavingsAvailability.isLocked(source) {
            try? await setAvailableOn(nil, accountId: source.id)
        }
        NotificationManager.removeSavingsAvailability(accountId: source.id)
    }

    /// Cambia (o quita, con nil) la fecha en que el dinero queda libre.
    static func setAvailableOn(_ date: Date?, accountId: UUID) async throws {
        struct Update: Encodable {
            let availableOn: String?
            enum CodingKeys: String, CodingKey { case availableOn = "available_on" }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(availableOn, forKey: .availableOn) // null explicito para quitarla
            }
        }
        try await SupabaseManager.shared.client
            .from("accounts")
            .update(Update(availableOn: date.map { SavingsAvailability.string(from: $0) }))
            .eq("id", value: accountId)
            .execute()
    }
}

/// Abrir "Transferir" con esa cuenta de origen (desde el aviso de
/// disponibilidad o desde Hoy).
struct AccountTransferRequest: Identifiable, Equatable {
    let id = UUID()
    let sourceAccountId: UUID?
}
