import Foundation

enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: return "Semanal"
        case .monthly: return "Mensual"
        }
    }

    /// Rango [inicio, fin) del periodo actual que contiene `date`.
    func currentRange(containing date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        switch self {
        case .weekly:
            let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? date
            return (start, end)
        case .monthly:
            let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? date
            return (start, end)
        }
    }
}

struct Budget: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var category: String
    var period: BudgetPeriod
    var limitAmount: Decimal
    /// Hex "#RRGGBB" elegido a mano, o nil para usar el color por defecto
    /// (ver BudgetColorPalette.swift).
    var color: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case category
        case period
        case limitAmount = "limit_amount"
        case color
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct NewBudget: Encodable {
    let userId: UUID
    let category: String
    let period: BudgetPeriod
    let limitAmount: Decimal

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case category
        case period
        case limitAmount = "limit_amount"
    }
}

/// Lo que se puede cambiar desde la hoja de detalle de un presupuesto
/// (BudgetDetailSheet) — no toca category/period, esos no se editan ahi.
struct BudgetUpdate: Encodable {
    var limitAmount: Decimal
    var color: String?

    enum CodingKeys: String, CodingKey {
        case limitAmount = "limit_amount"
        case color
    }
}

/// Progreso calculado de un presupuesto contra los movimientos del periodo
/// actual (no se guarda en la base, se calcula en el cliente).
struct BudgetProgress: Identifiable {
    let budget: Budget
    let spent: Decimal

    var id: UUID { budget.id }
    var ratio: Double {
        guard budget.limitAmount > 0 else { return 0 }
        return NSDecimalNumber(decimal: spent / budget.limitAmount).doubleValue
    }

    /// Mismas reglas de semaforo que el resto de la app: verde bien,
    /// amarillo atencion, rojo cuidado.
    enum Status {
        case onTrack, warning, over
    }

    var status: Status {
        if ratio >= 1 { return .over }
        if ratio >= 0.8 { return .warning }
        return .onTrack
    }
}
