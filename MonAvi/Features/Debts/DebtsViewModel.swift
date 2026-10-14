import Foundation
import Supabase

@MainActor
final class DebtsViewModel: ObservableObject {
    @Published private(set) var debts: [Debt] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    var totalActiveBalance: Decimal {
        debts.filter { $0.status != .paidOff }.reduce(0) { $0 + $1.balance }
    }

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            debts = try await supabase
                .from("debts")
                .select()
                .eq("user_id", value: userId)
                .order("is_overdue", ascending: false)
                .order("balance", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = "No se pudo cargar tus deudas: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func add(_ new: NewDebt) async throws -> Debt {
        let created: Debt = try await supabase
            .from("debts")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
        debts.append(created)
        return created
    }

    func delete(_ debt: Debt) async {
        do {
            try await supabase.from("debts").delete().eq("id", value: debt.id).execute()
            debts.removeAll { $0.id == debt.id }
        } catch {
            errorMessage = "No se pudo borrar: \(error.localizedDescription)"
        }
    }
}
