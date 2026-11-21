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
        } else if item.source == "debt", let debtId = UUID(uuidString: item.id) {
            try await applyDebtPayment(debtId: debtId, amount: Decimal(item.amount))
            CardPaymentTracker.markPaid(debtId: debtId)
        }
    }

    /// Acceso rapido desde el dashboard (fuera del flujo de "que pagar
    /// primero"): el usuario eligio la deuda y el monto el mismo, asi que
    /// aqui si hay que anotar el movimiento de salida ademas de bajar el
    /// saldo de la deuda.
    static func payDebt(debtId: UUID, amount: Decimal, accountId: UUID, creditor: String, userId: UUID) async throws {
        // Tarjeta con su cuenta (0079): el pago es una transferencia de la
        // cuenta de origen a la tarjeta. No es un gasto nuevo (las compras
        // ya se contaron como gasto al hacerlas con la tarjeta): sale de la
        // cuenta, entra a la tarjeta y la deuda baja sola (trigger).
        struct LinkedAccount: Decodable { let id: UUID }
        let linked: [LinkedAccount] = (try? await SupabaseManager.shared.client
            .from("accounts")
            .select("id")
            .eq("debt_id", value: debtId)
            .limit(1)
            .execute()
            .value) ?? []
        if let card = linked.first, card.id != accountId {
            let sourceName = (try? await accountName(accountId)) ?? "tu cuenta"
            try await TransactionsRepository.shared.add(
                NewTransaction(
                    userId: userId,
                    accountId: accountId,
                    amount: -abs(amount),
                    movementType: .transferencia,
                    category: TransactionCategory.transfers.rawValue,
                    description: "Pago a \(creditor)",
                    occurredAt: Date()
                )
            )
            try await TransactionsRepository.shared.add(
                NewTransaction(
                    userId: userId,
                    accountId: card.id,
                    amount: abs(amount),
                    movementType: .transferencia,
                    category: TransactionCategory.transfers.rawValue,
                    description: "Pago recibido desde \(sourceName)",
                    occurredAt: Date()
                )
            )
            CardPaymentTracker.markPaid(debtId: debtId)
            return
        }

        try await TransactionsRepository.shared.add(
            NewTransaction(
                userId: userId,
                accountId: accountId,
                amount: MovementType.gasto.signedAmount(from: amount),
                movementType: .gasto,
                category: nil,
                description: "Pago a \(creditor)",
                occurredAt: Date()
            )
        )
        try await applyDebtPayment(debtId: debtId, amount: amount)
        CardPaymentTracker.markPaid(debtId: debtId)
    }

    private static func accountName(_ id: UUID) async throws -> String {
        struct Row: Decodable { let name: String }
        let row: Row = try await SupabaseManager.shared.client
            .from("accounts").select("name").eq("id", value: id).single().execute().value
        return row.name
    }

    private static func applyDebtPayment(debtId: UUID, amount: Decimal) async throws {
        let supabase = SupabaseManager.shared.client

        struct DebtBalanceRow: Decodable { let balance: Decimal }
        let current: DebtBalanceRow = try await supabase
            .from("debts")
            .select("balance")
            .eq("id", value: debtId)
            .single()
            .execute()
            .value

        let newBalance = max(0, current.balance - amount)

        struct BalanceUpdate: Encodable { let balance: Decimal }
        try await supabase
            .from("debts")
            .update(BalanceUpdate(balance: newBalance))
            .eq("id", value: debtId)
            .execute()

        if newBalance <= 0 {
            struct StatusUpdate: Encodable { let status: String }
            try await supabase
                .from("debts")
                .update(StatusUpdate(status: DebtStatus.paidOff.rawValue))
                .eq("id", value: debtId)
                .execute()
        }
    }
}
