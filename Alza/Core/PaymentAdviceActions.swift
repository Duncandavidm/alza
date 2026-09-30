import Foundation
import Supabase

/// Acciones que se pueden tomar directo desde el consejo de priorizacion
/// (PaymentAdviceView), sin necesitar los view models de Bills/Recurring —
/// opera solo con los IDs que ya trae cada PaymentAdviceItem.
@MainActor
enum PaymentAdviceActions {
    static func markPaid(item: PaymentAdviceItem, userId: UUID) async throws {
        guard
            let accountId = UUID(uuidString: item.accountId),
            let movementType = MovementType(rawValue: item.movementType)
        else { return }

        try await TransactionsRepository.shared.add(
            NewTransaction(
                userId: userId,
                accountId: accountId,
                amount: movementType.signedAmount(from: Decimal(item.amount)),
                movementType: movementType,
                category: item.category,
                description: item.name,
                occurredAt: Date()
            )
        )

        let supabase = SupabaseManager.shared.client

        if item.source == "bill", let billId = UUID(uuidString: item.id) {
            try await supabase
                .from("bills")
                .update(["status": BillStatus.pagada.rawValue])
                .eq("id", value: billId)
                .execute()
        } else if item.source == "recurring", let recurringId = UUID(uuidString: item.id) {
            try await supabase
                .from("recurring_transactions")
                .update(["last_logged_on": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: recurringId)
                .execute()
        }
    }
}
