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

            // Si las facturas fallan (ej. sin conexion a esa tabla), los
            // niveles igual se calculan con lo demas.
            let receipts = (try? await DgiReceiptsRepository.shared.fetchAll(userId: userId)) ?? []
            let verifiedDates = receipts
                .filter { $0.status == .confirmada }
                .map { $0.dgiCheckedAt ?? $0.scannedAt }

            progress = HabitEngine().progress(
                for: HabitEngine.Input(
                    transactions: transactions,
                    budgets: budgets,
                    goals: goals,
                    contributions: contributions,
                    verifiedReceiptDates: verifiedDates
                )
            )
            goalsById = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })
        } catch {
            errorMessage = "No se pudo cargar tu nivel. Intenta de nuevo más tarde."
        }
    }
}
