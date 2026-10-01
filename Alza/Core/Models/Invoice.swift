import Foundation

enum InvoiceDocType: String, Codable, CaseIterable, Identifiable {
    case factura
    case remision
    case cuentaPorCobrar = "cuenta_por_cobrar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .factura: return "Factura"
        case .remision: return "Remision"
        case .cuentaPorCobrar: return "Cuenta por cobrar"
        }
    }
}

enum InvoiceStatus: String, Codable, CaseIterable, Identifiable {
    case emitida
    case entregada
    case pagada
    case anulada

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .emitida: return "Emitida"
        case .entregada: return "Entregada"
        case .pagada: return "Pagada"
        case .anulada: return "Anulada"
        }
    }
}

/// Mismo patron que `BillDateFormat`: las columnas `date` de Postgres se
/// manejan como String "yyyy-MM-dd" de punta a punta, sin depender de como
/// el decoder de supabase-swift interprete una fecha sin hora.
enum InvoiceDateFormat {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return formatter.date(from: string)
    }
}

/// Factura, remision o cuenta por cobrar que el usuario le emite a SUS
/// clientes (lo contrario de Bill, que es una cuenta que el usuario mismo
/// debe pagar). Lleva el estado emitida -> entregada -> pagada, y el
/// vencimiento se calcula contra `dueDate` igual que en Bill.
struct Invoice: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var accountId: UUID?
    var docType: InvoiceDocType
    var number: String?
    var customerName: String
    var customerContact: String?
    var issueDate: String
    var deliveredDate: String?
    var dueDate: String?
    var status: InvoiceStatus
    var subtotal: Decimal
    var total: Decimal
    var notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case accountId = "account_id"
        case docType = "doc_type"
        case number
        case customerName = "customer_name"
        case customerContact = "customer_contact"
        case issueDate = "issue_date"
        case deliveredDate = "delivered_date"
        case dueDate = "due_date"
        case status
        case subtotal
        case total
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var issueDateValue: Date { InvoiceDateFormat.date(from: issueDate) ?? createdAt }
    var deliveredDateValue: Date? { InvoiceDateFormat.date(from: deliveredDate) }
    var dueDateValue: Date? { InvoiceDateFormat.date(from: dueDate) }

    var isOverdue: Bool {
        guard status != .pagada, status != .anulada, let dueDateValue else { return false }
        return Calendar.current.startOfDay(for: dueDateValue) < Calendar.current.startOfDay(for: Date())
    }

    /// Dias hasta el vencimiento (negativo = ya vencio). nil si no tiene
    /// fecha de vencimiento.
    var daysUntilDue: Int? {
        guard let dueDateValue else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let due = Calendar.current.startOfDay(for: dueDateValue)
        return Calendar.current.dateComponents([.day], from: start, to: due).day
    }

    var dueCountdownLabel: String? {
        guard status != .pagada, status != .anulada, let days = daysUntilDue else { return nil }
        if days < 0 { return "Vencida hace \(-days) dia\(-days == 1 ? "" : "s")" }
        if days == 0 { return "Vence hoy" }
        return "Vence en \(days) dia\(days == 1 ? "" : "s")"
    }
}

struct NewInvoice: Encodable {
    let userId: UUID
    let accountId: UUID?
    let docType: InvoiceDocType
    let number: String?
    let customerName: String
    let customerContact: String?
    let issueDate: String
    let dueDate: String?
    let subtotal: Decimal
    let total: Decimal
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case accountId = "account_id"
        case docType = "doc_type"
        case number
        case customerName = "customer_name"
        case customerContact = "customer_contact"
        case issueDate = "issue_date"
        case dueDate = "due_date"
        case subtotal
        case total
        case notes
    }
}

struct InvoiceItem: Codable, Identifiable, Hashable {
    let id: UUID
    let invoiceId: UUID
    var productId: UUID?
    var description: String
    var quantity: Decimal
    var unitPrice: Decimal
    var lineTotal: Decimal
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case invoiceId = "invoice_id"
        case productId = "product_id"
        case description
        case quantity
        case unitPrice = "unit_price"
        case lineTotal = "line_total"
        case sortOrder = "sort_order"
    }
}

struct NewInvoiceItem: Encodable {
    let invoiceId: UUID
    let productId: UUID?
    let description: String
    let quantity: Decimal
    let unitPrice: Decimal
    let lineTotal: Decimal
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case invoiceId = "invoice_id"
        case productId = "product_id"
        case description
        case quantity
        case unitPrice = "unit_price"
        case lineTotal = "line_total"
        case sortOrder = "sort_order"
    }
}

/// Linea de factura mientras se esta armando en el formulario, antes de
/// tener invoiceId (eso solo existe una vez que la factura ya se creo).
struct InvoiceItemDraft: Identifiable, Hashable {
    let id = UUID()
    var productId: UUID?
    var description: String = ""
    var quantityText: String = "1"
    var unitPriceText: String = ""

    var quantity: Decimal { Decimal(string: quantityText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    var unitPrice: Decimal { Decimal(string: unitPriceText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    var lineTotal: Decimal { quantity * unitPrice }
}

/// Recibo de pago: queda guardado al marcar una factura como pagada, para
/// poder volver a compartirlo despues sin regenerar nada.
struct PaymentReceipt: Codable, Identifiable, Hashable {
    let id: UUID
    let invoiceId: UUID
    let userId: UUID
    var amount: Decimal
    var paidAt: Date
    var receiptNumber: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case invoiceId = "invoice_id"
        case userId = "user_id"
        case amount
        case paidAt = "paid_at"
        case receiptNumber = "receipt_number"
        case createdAt = "created_at"
    }
}

struct NewPaymentReceipt: Encodable {
    let invoiceId: UUID
    let userId: UUID
    let amount: Decimal
    let receiptNumber: String

    enum CodingKeys: String, CodingKey {
        case invoiceId = "invoice_id"
        case userId = "user_id"
        case amount
        case receiptNumber = "receipt_number"
    }
}
