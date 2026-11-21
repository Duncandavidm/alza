import SwiftUI
import Supabase

/// Análisis > "Tu salud financiera": la misma foto financiera del final del
/// onboarding, pero con los datos de hoy (pagos fijos, deudas, cuentas).
struct FinancialHealthView: View {
    @EnvironmentObject private var appState: AppState
    @State private var snapshot: FinancialSnapshot?
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let snapshot {
                FinancialSnapshotSections(snapshot: snapshot, name: name, showRevisitHint: false)
            } else if let errorMessage {
                ContentUnavailableView("No se pudo cargar", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
            } else {
                HStack {
                    Spacer()
                    ProgressView("Analizando tus números…")
                    Spacer()
                }
                .padding(.vertical, 40)
            }
        }
        .navigationTitle("Tu salud financiera")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let userId = appState.currentUserId else { return }
        do {
            let result = try await FinancialHealthLoader.load(userId: userId)
            name = result.name
            snapshot = result.snapshot
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Junta todo lo que hace falta para el estudio real: pagos fijos, deudas,
/// cuentas, perfil y los movimientos de los ultimos ~3 meses. Lo usan
/// "Tu salud financiera" y el aviso de sobreendeudamiento de Hoy.
@MainActor
enum FinancialHealthLoader {
    private struct ProfileBits: Decodable {
        let fullName: String?
        let hasVariableIncome: Bool?
        let shortTermGoals: [String]?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case hasVariableIncome = "has_variable_income"
            case shortTermGoals = "short_term_goals"
        }
    }

    static func load(userId: UUID) async throws -> (snapshot: FinancialSnapshot, name: String) {
        let supabase = SupabaseManager.shared.client
        let since = Calendar.current.date(byAdding: .day, value: -92, to: Date()) ?? Date()
        async let recurringTask: [RecurringTransaction] = supabase
            .from("recurring_transactions").select().eq("user_id", value: userId).execute().value
        async let debtsTask: [Debt] = supabase
            .from("debts").select().eq("user_id", value: userId).execute().value
        async let accountsTask: [Account] = supabase
            .from("accounts").select().eq("user_id", value: userId).execute().value
        async let profileTask: [ProfileBits] = supabase
            .from("profiles").select("full_name, has_variable_income, short_term_goals").eq("id", value: userId).limit(1).execute().value
        async let transactionsTask = TransactionsRepository.shared.fetchSince(userId: userId, date: since, limit: 3000)

        let (recurring, debts, accounts, profiles, transactions) = try await (recurringTask, debtsTask, accountsTask, profileTask, transactionsTask)
        let profile = profiles.first
        let snapshot = FinancialHealthInputs.snapshot(
            recurring: recurring,
            debts: debts,
            accounts: accounts,
            transactions: transactions,
            firstGoal: profile?.shortTermGoals?.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
            hasVariableIncome: profile?.hasVariableIncome ?? false
        )
        let name = profile?.fullName?.split(separator: " ").first.map(String.init) ?? ""
        return (snapshot, name)
    }
}

/// Arma la foto financiera desde los datos guardados (lógica pura).
enum FinancialHealthInputs {
    /// Un pago fijo llevado a mes.
    static func monthly(_ item: RecurringTransaction) -> Decimal {
        switch item.frequency {
        case .monthly: return item.amount
        case .weekly: return (item.amount * 52 / 12).roundedTo(2)
        case .daily: return item.amount * (item.movementType.isInflow ? 22 : 30)
        }
    }

    /// Promedio mensual REAL de ingresos y gastos con los movimientos de
    /// los ultimos 3 meses. Hace falta al menos ~4 semanas de historial
    /// (desde la primera cuenta) para que el promedio signifique algo.
    /// Los pagos a la tarjeta y aportes a metas (transferencias) no cuentan
    /// como gasto: el gasto ya se conto cuando se compro con la tarjeta.
    static func realAverages(
        transactions: [FinanceTransaction],
        historyStart: Date?,
        now: Date = Date()
    ) -> (income: Decimal, spending: Decimal, months: Int)? {
        guard let historyStart else { return nil }
        let windowStart = max(historyStart, now.addingTimeInterval(-90 * 86_400))
        let days = now.timeIntervalSince(windowStart) / 86_400
        guard days >= 28 else { return nil }
        let months = min(max(Int((days / 30).rounded()), 1), 3)
        let start = now.addingTimeInterval(-Double(months) * 30 * 86_400)
        let inWindow = transactions.filter { $0.occurredAt >= start && $0.occurredAt <= now }
        let income = inWindow.filter { $0.movementType == .ingreso }.reduce(Decimal(0)) { $0 + abs($1.amount) }
        let spending = inWindow.filter { $0.movementType == .gasto || $0.movementType == .pagoProveedor }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }
        return ((income / Decimal(months)).roundedTo(2), (spending / Decimal(months)).roundedTo(2), months)
    }

    static func snapshot(
        recurring: [RecurringTransaction],
        debts: [Debt],
        accounts: [Account],
        transactions: [FinanceTransaction] = [],
        firstGoal: String?,
        hasVariableIncome: Bool,
        now: Date = Date()
    ) -> FinancialSnapshot {
        let real = realAverages(transactions: transactions, historyStart: accounts.map(\.createdAt).min(), now: now)
        let active = recurring.filter(\.active)
        let income = active.filter { $0.movementType.isInflow }.reduce(Decimal(0)) { $0 + monthly($1) }
        let fixed = active.filter { !$0.movementType.isInflow }.reduce(Decimal(0)) { $0 + monthly($1) }
        let openDebts = debts.filter { $0.status != .paidOff && $0.balance > 0 }
        return FinancialSnapshot(
            monthlyIncome: income,
            fixedExpenses: fixed,
            debts: openDebts.map {
                FinancialSnapshot.DebtInput(
                    name: $0.creditor,
                    balance: $0.balance,
                    creditLimit: $0.creditLimit,
                    minimumPayment: $0.minimumPayment,
                    monthlyRate: $0.interestRateMonthly,
                    isOverdue: $0.isOverdue
                )
            },
            cash: max(accounts.filter { !$0.type.isReserve && !$0.type.isLiability }.reduce(Decimal(0)) { $0 + $1.balance }, 0),
            savings: max(accounts.filter(\.type.isReserve).reduce(Decimal(0)) { $0 + $1.balance }, 0),
            firstGoal: firstGoal,
            hasVariableIncome: hasVariableIncome,
            realIncome: real?.income,
            realSpending: real?.spending,
            realMonths: real?.months ?? 0
        )
    }
}
