import Foundation

/// amount positivo = ingreso, negativo = gasto (misma convencion que la
/// tabla public.transactions).
struct FinanceTransaction: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let accountId: UUID
    var amount: Decimal
    var category: String?
    var description: String?
    var occurredAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case accountId = "account_id"
        case amount
        case category
        case description
        case occurredAt = "occurred_at"
        case createdAt = "created_at"
    }
}

struct NewTransaction: Encodable {
    let userId: UUID
    let accountId: UUID
    let amount: Decimal
    let category: String?
    let description: String?
    let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case accountId = "account_id"
        case amount
        case category
        case description
        case occurredAt = "occurred_at"
    }
}

enum TransactionCategory: String, CaseIterable, Identifiable {
    case income = "Ingreso"
    case housing = "Vivienda"
    case food = "Comida"
    case transport = "Transporte"
    case entertainment = "Entretenimiento"
    case health = "Salud"
    case savings = "Ahorro"
    case other = "Otro"

    var id: String { rawValue }
}
