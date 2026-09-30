import Foundation

enum BillPriority: String, Codable, CaseIterable, Identifiable {
    case critica
    case alta
    case normal
    case baja

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .critica: return "Critica"
        case .alta: return "Alta"
        case .normal: return "Normal"
        case .baja: return "Baja"
        }
    }
}

enum BillStatus: String, Codable {
    case pendiente
    case pagada
}

/// Formato de la columna `due_date` (Postgres `date`, sin hora): "yyyy-MM-dd".
/// Se maneja como String de punta a punta para no depender de como el
/// decoder de supabase-swift interprete una fecha sin hora.
enum BillDateFormat {
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

    static func date(from string: String) -> Date {
        formatter.date(from: string) ?? Date()
    }
}

/// "Cuenta por pagar" — una factura o recibo pendiente con fecha de
/// vencimiento. El diferenciador de Alza: al registrar un ingreso, la app
/// mira estas (mas las recurrentes vencidas) y aconseja que pagar primero.
struct Bill: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var accountId: UUID
    var name: String
    var amount: Decimal
    var dueDate: String
    var category: String?
    var movementType: MovementType
    var priority: BillPriority
    var status: BillStatus
    var recurringTransactionId: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case accountId = "account_id"
        case name
        case amount
        case dueDate = "due_date"
        case category
        case movementType = "movement_type"
        case priority
        case status
        case recurringTransactionId = "recurring_transaction_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var dueDateValue: Date { BillDateFormat.date(from: dueDate) }

    var isOverdue: Bool {
        status == .pendiente && Calendar.current.startOfDay(for: dueDateValue) < Calendar.current.startOfDay(for: Date())
    }
}

struct NewBill: Encodable {
    let userId: UUID
    let accountId: UUID
    let name: String
    let amount: Decimal
    let dueDate: String
    let category: String?
    let movementType: MovementType
    let priority: BillPriority

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case accountId = "account_id"
        case name
        case amount
        case dueDate = "due_date"
        case category
        case movementType = "movement_type"
        case priority
    }
}
