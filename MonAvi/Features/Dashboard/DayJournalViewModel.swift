import Foundation
import Supabase

/// Resumen de cierre del dia (mejora #5): un mensaje simple de si fue buen
/// dia, dia normal, o dia flojo, comparado contra como le ha ido antes.
struct DaySummary {
    enum Mood {
        case good, normal, slow

        var title: String {
            switch self {
            case .good: return "¡Buen día!"
            case .normal: return "Día normal"
            case .slow: return "Día flojo"
            }
        }

        var message: String {
            switch self {
            case .good: return "Te fue mejor que en un día normal. ¡Sigue así!"
            case .normal: return "Un día como cualquier otro. Todo en orden."
            case .slow: return "Estuvo más flojo de lo normal, pero ya quedó anotado."
            }
        }

        var emoji: String {
            switch self {
            case .good: return "🎉"
            case .normal: return "👍"
            case .slow: return "😕"
            }
        }
    }

    let income: Decimal
    let expense: Decimal
    let mood: Mood

    var net: Decimal { income - expense }
}

@MainActor
final class DayJournalViewModel: ObservableObject {
    @Published private(set) var todayTransactions: [FinanceTransaction] = []
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// El dia que se esta viendo — por default hoy. Cambiarlo y llamar a
    /// `refresh` de nuevo es como "hojear" otro dia desde el icono de
    /// calendario del dashboard.
    @Published var selectedDate = Date()
    var isViewingToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    @Published var searchQuery = ""
    @Published private(set) var searchResults: [FinanceTransaction]?
    @Published private(set) var isSearching = false

    private let repository = TransactionsRepository.shared
    private let supabase = SupabaseManager.shared.client

    /// Cuenta a usar por default en el ingreso ultra-rapido: la ultima que
    /// se uso hoy, o la primera del negocio si todavia no hay movimientos.
    var defaultAccountId: UUID? {
        todayTransactions.last?.accountId ?? accounts.first?.id
    }

    var todayIncome: Decimal {
        todayTransactions
            .filter { $0.movementType.isInflow }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    var todayExpense: Decimal {
        // Las salidas se guardan en negativo; aqui se regresa la magnitud.
        -todayTransactions
            .filter { !$0.movementType.isInflow }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    var todayNet: Decimal { todayIncome - todayExpense }

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let txTask = repository.fetchDay(userId: userId, date: selectedDate)
            async let accountsTask: [Account] = supabase
                .from("accounts")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: true)
                .execute()
                .value

            todayTransactions = try await txTask
            accounts = try await accountsTask
        } catch {
            errorMessage = "No se pudo cargar tu día: \(error.localizedDescription)"
        }
    }

    /// Busqueda en vivo (texto, o "#etiqueta") sobre TODOS los movimientos,
    /// no solo el dia que se esta viendo — activa por el icono de lupa.
    func search(userId: UUID) async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = nil
            return
        }
        isSearching = true
        defer { isSearching = false }
        searchResults = try? await repository.search(userId: userId, query: searchQuery)
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = nil
    }

    /// El ingreso ultra-rapido (mejora #2): solo monto + descripcion. El
    /// tipo de movimiento se pre-selecciona (gasto, lo mas comun) y se puede
    /// cambiar con un toque; la cuenta se infiere sola.
    func quickAdd(
        userId: UUID,
        accountId: UUID,
        magnitude: Decimal,
        description: String,
        movementType: MovementType,
        category: String? = nil
    ) async throws {
        let created = try await repository.add(
            NewTransaction(
                userId: userId,
                accountId: accountId,
                amount: movementType.signedAmount(from: magnitude),
                movementType: movementType,
                category: category,
                description: description.isEmpty ? nil : description,
                occurredAt: Date()
            )
        )
        todayTransactions.append(created)

        if let index = accounts.firstIndex(where: { $0.id == accountId }) {
            accounts[index].balance += created.amount
        }
    }

    /// Corregir un movimiento ya anotado (monto, tipo, categoria o
    /// descripcion) — antes de esto, un typo quedaba anotado para siempre.
    /// La cuenta no cambia aqui (ver TransactionsRepository.update).
    func updateTransaction(
        _ transaction: FinanceTransaction,
        magnitude: Decimal,
        movementType: MovementType,
        category: String?,
        description: String?
    ) async throws {
        let oldAmount = transaction.amount
        let updated = try await repository.update(
            transaction,
            magnitude: magnitude,
            movementType: movementType,
            category: category,
            description: description
        )

        if let index = todayTransactions.firstIndex(where: { $0.id == updated.id }) {
            todayTransactions[index] = updated
        }
        if let index = searchResults?.firstIndex(where: { $0.id == updated.id }) {
            searchResults?[index] = updated
        }
        if let index = accounts.firstIndex(where: { $0.id == updated.accountId }) {
            accounts[index].balance += updated.amount - oldAmount
        }
    }

    func deleteTransaction(_ transaction: FinanceTransaction) async throws {
        try await repository.delete(transaction)
        todayTransactions.removeAll { $0.id == transaction.id }
        searchResults?.removeAll { $0.id == transaction.id }
        if let index = accounts.firstIndex(where: { $0.id == transaction.accountId }) {
            accounts[index].balance -= transaction.amount
        }
    }

    func closeDaySummary(userId: UUID) async -> DaySummary {
        let pastNets = try? await repository.fetchPastDailyNets(userId: userId, days: 7)
        let mood = Self.mood(for: todayNet, comparedTo: pastNets ?? [])
        return DaySummary(income: todayIncome, expense: todayExpense, mood: mood)
    }

    private static func mood(for todayNet: Decimal, comparedTo pastNets: [Decimal]) -> DaySummary.Mood {
        guard !pastNets.isEmpty else {
            return todayNet > 0 ? .normal : .slow
        }

        let average = pastNets.reduce(Decimal(0), +) / Decimal(pastNets.count)
        let scale = max(abs(average), Decimal(1))
        let relativeDiff = (todayNet - average) / scale

        if relativeDiff >= 0.1 {
            return .good
        } else if relativeDiff >= -0.1 {
            return .normal
        } else {
            return .slow
        }
    }
}
