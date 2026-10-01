import Foundation
import Supabase

@MainActor
final class InvoicesViewModel: ObservableObject {
    @Published private(set) var invoices: [Invoice] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            invoices = try await supabase
                .from("invoices")
                .select()
                .eq("user_id", value: userId)
                .order("issue_date", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = "No se pudo cargar tus facturas: \(error.localizedDescription)"
        }
    }

    func fetchItems(invoiceId: UUID) async throws -> [InvoiceItem] {
        try await supabase
            .from("invoice_items")
            .select()
            .eq("invoice_id", value: invoiceId)
            .order("sort_order", ascending: true)
            .execute()
            .value
    }

    @discardableResult
    func create(_ draft: NewInvoice, items: [InvoiceItemDraft]) async throws -> Invoice {
        let number = try await nextNumber(userId: draft.userId, docType: draft.docType)

        let payload = NewInvoice(
            userId: draft.userId,
            accountId: draft.accountId,
            docType: draft.docType,
            number: number,
            customerName: draft.customerName,
            customerContact: draft.customerContact,
            issueDate: draft.issueDate,
            dueDate: draft.dueDate,
            subtotal: draft.subtotal,
            total: draft.total,
            notes: draft.notes
        )

        let created: Invoice = try await supabase
            .from("invoices")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value

        let validItems = items.filter { !$0.description.trimmingCharacters(in: .whitespaces).isEmpty && $0.lineTotal > 0 }

        if !validItems.isEmpty {
            let itemPayloads = validItems.enumerated().map { index, draft in
                NewInvoiceItem(
                    invoiceId: created.id,
                    productId: draft.productId,
                    description: draft.description,
                    quantity: draft.quantity,
                    unitPrice: draft.unitPrice,
                    lineTotal: draft.lineTotal,
                    sortOrder: index
                )
            }
            try await supabase.from("invoice_items").insert(itemPayloads).execute()
        }

        invoices.insert(created, at: 0)
        return created
    }

    func markDelivered(_ invoice: Invoice) async {
        struct Update: Encodable {
            let status: String
            let deliveredDate: String
            enum CodingKeys: String, CodingKey { case status, deliveredDate = "delivered_date" }
        }

        do {
            let updated: Invoice = try await supabase
                .from("invoices")
                .update(Update(status: InvoiceStatus.entregada.rawValue, deliveredDate: InvoiceDateFormat.string(from: Date())))
                .eq("id", value: invoice.id)
                .select()
                .single()
                .execute()
                .value
            replace(updated)
        } catch {
            errorMessage = "No se pudo marcar como entregada: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func markPaid(_ invoice: Invoice, userId: UUID) async throws -> PaymentReceipt {
        struct Update: Encodable { let status: String }

        let updated: Invoice = try await supabase
            .from("invoices")
            .update(Update(status: InvoiceStatus.pagada.rawValue))
            .eq("id", value: invoice.id)
            .select()
            .single()
            .execute()
            .value

        let receiptNumber = try await nextReceiptNumber(userId: userId)

        let receipt: PaymentReceipt = try await supabase
            .from("payment_receipts")
            .insert(NewPaymentReceipt(invoiceId: invoice.id, userId: userId, amount: invoice.total, receiptNumber: receiptNumber))
            .select()
            .single()
            .execute()
            .value

        if let accountId = invoice.accountId {
            try await TransactionsRepository.shared.add(
                NewTransaction(
                    userId: userId,
                    accountId: accountId,
                    amount: MovementType.ingreso.signedAmount(from: invoice.total),
                    movementType: .ingreso,
                    category: TransactionCategory.income.rawValue,
                    description: "Pago \(invoice.docType.displayName.lowercased()) \(invoice.number ?? "") — \(invoice.customerName)",
                    occurredAt: Date()
                )
            )
        }

        replace(updated)
        return receipt
    }

    func delete(_ invoice: Invoice) async {
        do {
            try await supabase.from("invoices").delete().eq("id", value: invoice.id).execute()
            invoices.removeAll { $0.id == invoice.id }
        } catch {
            errorMessage = "No se pudo borrar: \(error.localizedDescription)"
        }
    }

    private func replace(_ invoice: Invoice) {
        if let index = invoices.firstIndex(where: { $0.id == invoice.id }) {
            invoices[index] = invoice
        }
    }

    private func nextNumber(userId: UUID, docType: InvoiceDocType) async throws -> String {
        let prefix: String
        switch docType {
        case .factura: prefix = "F"
        case .remision: prefix = "R"
        case .cuentaPorCobrar: prefix = "CC"
        }

        let response = try await supabase
            .from("invoices")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: userId)
            .eq("doc_type", value: docType.rawValue)
            .execute()

        return "\(prefix)-\(String(format: "%04d", (response.count ?? 0) + 1))"
    }

    private func nextReceiptNumber(userId: UUID) async throws -> String {
        let response = try await supabase
            .from("payment_receipts")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: userId)
            .execute()

        return "REC-\(String(format: "%04d", (response.count ?? 0) + 1))"
    }
}
