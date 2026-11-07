import Foundation
import Supabase

@MainActor
final class LevelsViewModel: ObservableObject {
    @Published private(set) var progress: HabitEngine.Progress?
    @Published private(set) var goalsById: [UUID: SavingsGoal] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let transactions = try await TransactionsRepository.shared.fetchAll(userId: userId)

            let budgets: [Budget] = try await supabase
                .from("budgets")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            let goals: [SavingsGoal] = try await supabase
                .from("savings_goals")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            let contributions: [SavingsContribution] = try await supabase
                .from("savings_contributions")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: true)
                .execute()
                .value

            // Las facturas ya no dan puntos (dan cashback); solo se usan
            // para las insignias de facturas. Si fallan, igual se sigue.
            let receipts = (try? await DgiReceiptsRepository.shared.fetchAll(userId: userId)) ?? []
            let verifiedDates = receipts
                .filter { $0.status == .confirmada }
                .map { $0.dgiCheckedAt ?? $0.scannedAt }

            let local = HabitEngine().progress(
                for: HabitEngine.Input(
                    transactions: transactions,
                    budgets: budgets,
                    goals: goals,
                    contributions: contributions,
                    verifiedReceiptDates: verifiedDates
                )
            )

            // El nivel sale de los puntos que calculo el servidor
            // (`habit_points_earned`). Si no se pudo leer el saldo, queda
            // el calculo local como respaldo.
            if let balance = try? await CardPointsRepository.shared.fetchBalanceOrThrow(userId: userId) {
                let thisMonth = await CardPointsRepository.shared.habitPointsThisMonth(userId: userId)
                progress = local.withServerTotals(totalXP: balance.habitPointsEarned, xpThisMonth: thisMonth)
            } else {
                progress = local
            }
            goalsById = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })
        } catch {
            errorMessage = "No se pudo cargar tu nivel. Intenta de nuevo más tarde."
        }
    }
}
