import Foundation
import Supabase

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var recentTransactions: [FinanceTransaction] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    var totalBalance: Decimal {
        accounts.reduce(0) { partial, account in
            switch account.type {
            case .creditCard, .loan:
                return partial - account.balance
            default:
                return partial + account.balance
            }
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let accountsTask: [Account] = supabase
                .from("accounts")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: true)
                .execute()
                .value

            async let transactionsTask: [FinanceTransaction] = supabase
                .from("transactions")
                .select()
                .eq("user_id", value: userId)
                .order("occurred_at", ascending: false)
                .limit(20)
                .execute()
                .value

            accounts = try await accountsTask
            recentTransactions = try await transactionsTask
        } catch {
            errorMessage = "No se pudo cargar tu informacion: \(error.localizedDescription)"
        }
    }

    func addAccount(_ new: NewAccount) async throws {
        let created: Account = try await supabase
            .from("accounts")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
        accounts.append(created)
    }

    func addTransaction(_ new: NewTransaction) async throws {
        let created: FinanceTransaction = try await supabase
            .from("transactions")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
        recentTransactions.insert(created, at: 0)

        // Refleja el movimiento en el balance de la cuenta.
        if let index = accounts.firstIndex(where: { $0.id == new.accountId }) {
            let updatedBalance = accounts[index].balance + new.amount
            try await supabase
                .from("accounts")
                .update(["balance": updatedBalance])
                .eq("id", value: new.accountId)
                .execute()
            accounts[index].balance = updatedBalance
        }
    }
}
