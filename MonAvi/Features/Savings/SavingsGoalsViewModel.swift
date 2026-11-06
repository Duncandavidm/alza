import Foundation
import Supabase

@MainActor
final class SavingsGoalsViewModel: ObservableObject {
    @Published private(set) var goals: [SavingsGoal] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            goals = try await supabase
                .from("savings_goals")
                .select()
                .eq("user_id", value: userId)
                .order("target_date", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = "No se pudieron cargar tus metas de ahorro: \(error.localizedDescription)"
        }
    }

    func add(_ new: NewSavingsGoal) async throws {
        let created: SavingsGoal = try await supabase
            .from("savings_goals")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
        goals.append(created)
        goals.sort { $0.targetDateValue < $1.targetDateValue }
    }

    func delete(_ goal: SavingsGoal) async throws {
        try await supabase.from("savings_goals").delete().eq("id", value: goal.id).execute()
        goals.removeAll { $0.id == goal.id }
    }

    /// Edita nombre/emoji/monto objetivo/fecha/cuenta vinculada — no toca
    /// currentAmount, eso solo cambia via `contribute`.
    func update(
        _ goal: SavingsGoal,
        name: String,
        emoji: String,
        targetAmount: Decimal,
        targetDate: String,
        accountId: UUID?
    ) async throws {
        struct Update: Encodable {
            let name: String
            let emoji: String
            let targetAmount: Decimal
            let targetDate: String
            let accountId: UUID?

            enum CodingKeys: String, CodingKey {
                case name, emoji
                case targetAmount = "target_amount"
                case targetDate = "target_date"
                case accountId = "account_id"
            }
        }

        let updated: SavingsGoal = try await supabase
            .from("savings_goals")
            .update(Update(name: name, emoji: emoji, targetAmount: targetAmount, targetDate: targetDate, accountId: accountId))
            .eq("id", value: goal.id)
            .select()
            .single()
            .execute()
            .value

        replace(updated)
    }

    /// Registra un aporte (amount > 0) o un retiro (amount < 0): ajusta
    /// `currentAmount`, deja el movimiento en el historial inmutable
    /// `savings_contributions` (base de los niveles e insignias: un aporte
    /// solo "madura" si pasan 30 dias sin retiros) y, si la meta tiene una
    /// cuenta vinculada, anota la transferencia real en esa cuenta (sale
    /// dinero al aportar, vuelve al retirar).
    func contribute(to goal: SavingsGoal, amount: Decimal, userId: UUID) async throws {
        guard amount != 0 else { return }
        if amount < 0 && -amount > goal.currentAmount {
            throw SavingsGoalError.withdrawalExceedsBalance
        }

        struct Update: Encodable {
            let currentAmount: Decimal
            enum CodingKeys: String, CodingKey { case currentAmount = "current_amount" }
        }

        let newAmount = goal.currentAmount + amount

        let updated: SavingsGoal = try await supabase
            .from("savings_goals")
            .update(Update(currentAmount: newAmount))
            .eq("id", value: goal.id)
            .select()
            .single()
            .execute()
            .value

        try await supabase
            .from("savings_contributions")
            .insert(NewSavingsContribution(userId: userId, goalId: goal.id, amount: amount))
            .execute()

        if let accountId = goal.accountId {
            _ = try await TransactionsRepository.shared.add(
                NewTransaction(
                    userId: userId,
                    accountId: accountId,
                    // Aporte: sale de la cuenta (negativo). Retiro: vuelve (positivo).
                    amount: -amount,
                    movementType: .transferencia,
                    category: TransactionCategory.savings.rawValue,
                    description: amount > 0 ? "Aporte a meta: \(goal.name)" : "Retiro de meta: \(goal.name)",
                    occurredAt: Date()
                )
            )
        }

        replace(updated)
    }

    private func replace(_ goal: SavingsGoal) {
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = goal
        }
    }
}

enum SavingsGoalError: LocalizedError {
    case withdrawalExceedsBalance

    var errorDescription: String? {
        switch self {
        case .withdrawalExceedsBalance:
            return "No puedes retirar más de lo que tienes ahorrado en esta meta."
        }
    }
}
