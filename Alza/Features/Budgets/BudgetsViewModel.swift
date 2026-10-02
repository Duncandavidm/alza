import Foundation
import Supabase

@MainActor
final class BudgetsViewModel: ObservableObject {
    @Published private(set) var progresses: [BudgetProgress] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let budgets: [Budget] = try await supabase
                .from("budgets")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: true)
                .execute()
                .value

            var results: [BudgetProgress] = []
            for budget in budgets {
                results.append(BudgetProgress(budget: budget, spent: try await spent(for: budget, userId: userId)))
            }
            progresses = results
        } catch {
            errorMessage = "No se pudieron cargar tus presupuestos: \(error.localizedDescription)"
        }
    }

    private func spent(for budget: Budget, userId: UUID) async throws -> Decimal {
        let range = budget.period.currentRange(containing: Date())

        let rows: [FinanceTransaction] = try await supabase
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .eq("category", value: budget.category)
            .gte("occurred_at", value: range.start)
            .lt("occurred_at", value: range.end)
            .execute()
            .value

        return rows
            .filter { $0.amount < 0 }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }
    }

    func addBudget(_ new: NewBudget) async throws {
        let created: Budget = try await supabase
            .from("budgets")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
        progresses.append(BudgetProgress(budget: created, spent: 0))
    }

    func deleteBudget(_ budget: Budget) async throws {
        try await supabase.from("budgets").delete().eq("id", value: budget.id).execute()
        progresses.removeAll { $0.id == budget.id }
    }

    /// Edita limite y/o color desde BudgetDetailSheet — category/period no
    /// se tocan ahi (cambiarlos de verdad seria crear otro presupuesto).
    func updateBudget(_ budget: Budget, limitAmount: Decimal, color: String?) async throws {
        let updated: Budget = try await supabase
            .from("budgets")
            .update(BudgetUpdate(limitAmount: limitAmount, color: color))
            .eq("id", value: budget.id)
            .select()
            .single()
            .execute()
            .value

        if let index = progresses.firstIndex(where: { $0.id == budget.id }) {
            progresses[index] = BudgetProgress(budget: updated, spent: progresses[index].spent)
        }
    }

    /// Promedio de gasto de los ultimos 3 meses ya cerrados (sin contar el
    /// mes en curso, que todavia esta incompleto) — el "prom. $X/mes" que
    /// se muestra en BudgetDetailSheet.
    func averageMonthlySpent(for budget: Budget, userId: UUID) async throws -> Decimal {
        let calendar = Calendar.current
        let startOfThisMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        guard let start = calendar.date(byAdding: .month, value: -3, to: startOfThisMonth) else {
            return 0
        }

        let rows: [FinanceTransaction] = try await supabase
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .eq("category", value: budget.category)
            .gte("occurred_at", value: start)
            .lt("occurred_at", value: startOfThisMonth)
            .execute()
            .value

        let total = rows
            .filter { $0.amount < 0 }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }

        return total / 3
    }
}
