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
}
