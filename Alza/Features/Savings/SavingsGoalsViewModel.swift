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

    /// Registra un aporte: sube `currentAmount` y, si la meta tiene una
    /// cuenta vinculada, tambien anota un movimiento real (transferencia,
    /// categoria Ahorro) para que ese dinero salga de la cuenta de origen
    /// en el resto de la app — no es contabilidad de doble entrada, solo
    /// un movimiento de salida, igual de simple que el resto de Alza.
    func contribute(to goal: SavingsGoal, amount: Decimal, userId: UUID) async throws {
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

        if let accountId = goal.accountId {
            try await TransactionsRepository.shared.add(
                NewTransaction(
                    userId: userId,
                    accountId: accountId,
                    amount: MovementType.transferencia.signedAmount(from: amount),
                    movementType: .transferencia,
                    category: TransactionCategory.savings.rawValue,
                    description: "Aporte a meta: \(goal.name)",
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
