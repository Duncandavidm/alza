import Foundation

/// Cada cuanto se repite una recurrente. Quincenal no esta aqui a proposito:
/// se guarda como dos recurrentes mensuales (p.ej. dias 15 y 30), asi todo lo
/// que ya entiende "dia del mes" (recordatorios, plan de pagos) sigue igual.
enum RecurrenceFrequency: String, Codable, CaseIterable, Hashable {
    case monthly
    case weekly
    case daily
}

/// Movimiento fijo que se repite (renta, Netflix, gimnasio, salario...).
/// Inspirado en "Crea transacciones recurrentes para que nunca olvides
/// nada" — muy cercano al gastos_fijos_config del plan original de MonAvi.
struct RecurringTransaction: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var accountId: UUID
    var name: String
    var amount: Decimal
    var movementType: MovementType
    var category: String?
    var dayOfMonth: Int
    /// `.monthly` si la fila es de antes de 1.0.2 (la columna no existia).
    var frequency: RecurrenceFrequency
    /// Solo para `.weekly`: 1 = domingo ... 7 = sabado (Calendar de iOS).
    var weekday: Int?
    var active: Bool
    var lastLoggedOn: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case accountId = "account_id"
        case name
        case amount
        case movementType = "movement_type"
        case category
        case dayOfMonth = "day_of_month"
        case frequency
        case weekday
        case active
        case lastLoggedOn = "last_logged_on"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        accountId = try container.decode(UUID.self, forKey: .accountId)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Decimal.self, forKey: .amount)
        movementType = try container.decode(MovementType.self, forKey: .movementType)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        dayOfMonth = try container.decode(Int.self, forKey: .dayOfMonth)
        // Un valor desconocido (de una version futura) cae a mensual en vez
        // de romper la carga de toda la lista.
        let rawFrequency = try container.decodeIfPresent(String.self, forKey: .frequency)
        frequency = rawFrequency.flatMap(RecurrenceFrequency.init(rawValue:)) ?? .monthly
        weekday = try container.decodeIfPresent(Int.self, forKey: .weekday)
        active = try container.decode(Bool.self, forKey: .active)
        lastLoggedOn = try container.decodeIfPresent(Date.self, forKey: .lastLoggedOn)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// Granularidad con la que "ya se registro": una vez por mes, por
    /// semana o por dia segun la frecuencia.
    var loggingGranularity: Calendar.Component {
        switch frequency {
        case .monthly: return .month
        case .weekly: return .weekOfYear
        case .daily: return .day
        }
    }

    /// true si hoy le toca y todavia no se registro en este periodo.
    func isDueToday(calendar: Calendar = .current, today: Date = Date()) -> Bool {
        guard active else { return false }
        switch frequency {
        case .monthly:
            // "30" o "31" en un mes mas corto toca el ultimo dia del mes.
            let daysInMonth = calendar.range(of: .day, in: .month, for: today)?.count ?? 28
            guard calendar.component(.day, from: today) == min(dayOfMonth, daysInMonth) else { return false }
        case .weekly:
            guard let weekday, calendar.component(.weekday, from: today) == weekday else { return false }
        case .daily:
            break
        }
        guard let lastLoggedOn else { return true }
        return !calendar.isDate(lastLoggedOn, equalTo: today, toGranularity: loggingGranularity)
    }

    /// Texto corto para listas: "día 15", "cada lunes", "cada día".
    var scheduleDescription: String {
        switch frequency {
        case .monthly:
            return "día \(dayOfMonth)"
        case .weekly:
            return "cada \(Self.weekdayName(weekday ?? 2))"
        case .daily:
            return L("cada día")
        }
    }

    /// 1 = domingo ... 7 = sabado.
    static func weekdayName(_ weekday: Int) -> String {
        let names = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
        return names[(min(max(weekday, 1), 7)) - 1]
    }
}

struct NewRecurringTransaction: Encodable {
    let userId: UUID
    let accountId: UUID
    let name: String
    let amount: Decimal
    let movementType: MovementType
    let category: String?
    let dayOfMonth: Int
    var frequency: RecurrenceFrequency = .monthly
    var weekday: Int? = nil

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case accountId = "account_id"
        case name
        case amount
        case movementType = "movement_type"
        case category
        case dayOfMonth = "day_of_month"
        case frequency
        case weekday
    }

    init(
        userId: UUID,
        accountId: UUID,
        name: String,
        amount: Decimal,
        movementType: MovementType,
        category: String?,
        dayOfMonth: Int,
        frequency: RecurrenceFrequency = .monthly,
        weekday: Int? = nil
    ) {
        self.userId = userId
        self.accountId = accountId
        self.name = name
        self.amount = amount
        self.movementType = movementType
        self.category = category
        self.dayOfMonth = dayOfMonth
        self.frequency = frequency
        self.weekday = weekday
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(movementType, forKey: .movementType)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(dayOfMonth, forKey: .dayOfMonth)
        try container.encode(frequency, forKey: .frequency)
        // weekday solo viaja si es semanal (el CHECK exige null en el resto).
        if frequency == .weekly {
            try container.encode(weekday ?? 2, forKey: .weekday)
        }
    }
}
