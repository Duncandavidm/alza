import Foundation
import Supabase

@MainActor
final class BillsViewModel: ObservableObject {
    @Published private(set) var bills: [Bill] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    var pending: [Bill] {
        bills.filter { $0.status == .pendiente }.sorted { $0.dueDateValue < $1.dueDateValue }
    }

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            bills = try await supabase
                .from("bills")
                .select()
                .eq("user_id", value: userId)
                .order("due_date", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = "No se pudieron cargar tus cuentas por pagar: \(error.localizedDescription)"
        }
    }

    func add(_ new: NewBill) async throws {
        let created: Bill = try await supabase
            .from("bills")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
        bills.append(created)
    }

    func delete(_ bill: Bill) async throws {
        try await supabase.from("bills").delete().eq("id", value: bill.id).execute()
        bills.removeAll { $0.id == bill.id }
    }

    /// Marca la cuenta como pagada Y registra el gasto real, en un solo paso
    /// (se usa tanto desde la lista como desde el consejo de priorizacion).
    func markPaid(_ bill: Bill, userId: UUID) async throws {
        try await TransactionsRepository.shared.add(
            NewTransaction(
                userId: userId,
                accountId: bill.accountId,
                amount: bill.movementType.signedAmount(from: bill.amount),
                movementType: bill.movementType,
                category: bill.category,
                description: bill.name,
                occurredAt: Date()
            )
        )

        try await supabase
            .from("bills")
            .update(["status": BillStatus.pagada.rawValue])
            .eq("id", value: bill.id)
            .execute()

        if let index = bills.firstIndex(where: { $0.id == bill.id }) {
            bills[index].status = .pagada
        }
    }
}
