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

    private func load() async {
        guard let userId = appState.currentUserId else { return }
        let supabase = SupabaseManager.shared.client
        do {
            async let recurringTask: [RecurringTransaction] = supabase
                .from("recurring_transactions").select().eq("user_id", value: userId).execute().value
            async let debtsTask: [Debt] = supabase
                .from("debts").select().eq("user_id", value: userId).execute().value
            async let accountsTask: [Account] = supabase
                .from("accounts").select().eq("user_id", value: userId).execute().value
            async let profileTask: [ProfileBits] = supabase
                .from("profiles").select("full_name, has_variable_income, short_term_goals").eq("id", value: userId).limit(1).execute().value

            let (recurring, debts, accounts, profiles) = try await (recurringTask, debtsTask, accountsTask, profileTask)
            let profile = profiles.first
            name = profile?.fullName?.split(separator: " ").first.map(String.init) ?? ""
            snapshot = FinancialHealthInputs.snapshot(
                recurring: recurring,
                debts: debts,
                accounts: accounts,
                firstGoal: profile?.shortTermGoals?.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                hasVariableIncome: profile?.hasVariableIncome ?? false
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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

    static func snapshot(
        recurring: [RecurringTransaction],
        debts: [Debt],
        accounts: [Account],
        firstGoal: String?,
        hasVariableIncome: Bool
    ) -> FinancialSnapshot {
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
            hasVariableIncome: hasVariableIncome
        )
    }
}
