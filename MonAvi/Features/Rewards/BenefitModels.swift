import Foundation

/// Cada cuanto se renueva un descuento de aliado (`per_user_period`,
/// migracion 0067). "semana" va de lunes a domingo, en hora de Panama.
enum BenefitPeriod: String, Codable, Hashable {
    case dia
    case semana
    case mes
    case siempre

    /// Tolerante: un valor desconocido cae en `.semana` (el de por defecto).
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = BenefitPeriod(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .semana
    }

    /// "por semana", "por día", "por mes", "en total".
    var label: String {
        switch self {
        case .dia: return "por día"
        case .semana: return "por semana"
        case .mes: return "por mes"
        case .siempre: return "en total"
        }
    }
}

/// Un descuento de aliado tal como lo devuelve `my_benefits()` (0067): el
/// producto con su comercio, cuantas veces ya lo uso esta persona en el
/// periodo, cuando vuelve a estar disponible y el codigo vigente (si ya
/// genero uno en los ultimos 15 minutos).
struct BenefitEntry: Decodable, Identifiable, Hashable {
    var item: RewardItem
    var usesInPeriod: Int
    var availableAgainAt: Date?
    var usedUp: Bool
    var activeRedemption: RewardRedemption?

    var id: UUID { item.id }

    enum CodingKeys: String, CodingKey {
        case item
        case usesInPeriod = "uses_in_period"
        case availableAgainAt = "available_again_at"
        case usedUp = "used_up"
        case activeRedemption = "active_redemption"
    }

    init(
        item: RewardItem,
        usesInPeriod: Int = 0,
        availableAgainAt: Date? = nil,
        usedUp: Bool = false,
        activeRedemption: RewardRedemption? = nil
    ) {
        self.item = item
        self.usesInPeriod = usesInPeriod
        self.availableAgainAt = availableAgainAt
        self.usedUp = usedUp
        self.activeRedemption = activeRedemption
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        item = try container.decode(RewardItem.self, forKey: .item)
        usesInPeriod = (try? container.decodeIfPresent(Int.self, forKey: .usesInPeriod)) ?? 0
        availableAgainAt = try? container.decodeIfPresent(Date.self, forKey: .availableAgainAt)
        usedUp = (try? container.decodeIfPresent(Bool.self, forKey: .usedUp)) ?? false
        // El codigo vigente viene sin embeds: se le pega el producto.
        if var redemption = try? container.decodeIfPresent(RewardRedemption.self, forKey: .activeRedemption) {
            redemption.item = item
            redemption.merchant = item.merchant
            activeRedemption = redemption
        } else {
            activeRedemption = nil
        }
    }
}

/// Respuesta de `my_benefits()`. `unlocked` es false hasta que la persona
/// escanea su primera factura fiscal.
struct BenefitsResponse: Decodable, Hashable {
    var unlocked: Bool
    var benefits: [BenefitEntry]

    static let empty = BenefitsResponse(unlocked: false, benefits: [])

    init(unlocked: Bool, benefits: [BenefitEntry]) {
        self.unlocked = unlocked
        self.benefits = benefits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unlocked = (try? container.decodeIfPresent(Bool.self, forKey: .unlocked)) ?? false
        benefits = (try? container.decodeIfPresent([BenefitEntry].self, forKey: .benefits)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case unlocked
        case benefits
    }
}

/// Que puede hacer la persona con un descuento ahora mismo.
enum BenefitState: Equatable {
    /// Aun no escanea su primera factura.
    case locked
    /// Ya genero un codigo que sigue vigente.
    case active(RewardRedemption)
    /// Lo puede usar.
    case available
    /// Ya lo uso en este periodo; vuelve a estar disponible en esa fecha.
    case cooldown(Date)
    /// Era de una sola vez y ya lo uso.
    case usedUp
}

/// Logica pura de los descuentos (sin red ni UI) para probarla aparte.
enum BenefitsMath {
    /// Vigencia del codigo de un descuento (lo fija `use_benefit`).
    static let codeLifetime: TimeInterval = 15 * 60

    static func state(of entry: BenefitEntry, unlocked: Bool, now: Date = Date()) -> BenefitState {
        guard unlocked else { return .locked }
        if let redemption = entry.activeRedemption, redemption.isUsable(now: now) {
            return .active(redemption)
        }
        if entry.usedUp { return .usedUp }
        if let again = entry.availableAgainAt, again > now { return .cooldown(again) }
        return .available
    }

    /// "1 vez por semana", "2 veces por mes", "1 vez en total".
    static func limitText(limit: Int?, period: BenefitPeriod?) -> String {
        let times = max(1, limit ?? 1)
        return "\(times) \(times == 1 ? "vez" : "veces") \((period ?? .semana).label)"
    }

    /// "Disponible de nuevo el lun 23 nov".
    static func availableAgainText(_ date: Date, calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle(locale: .monavi, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).day().month(.abbreviated)
        let day = date.formatted(style)
        return "Disponible de nuevo el \(day)"
    }

    /// Cuenta regresiva del codigo: "14:32" (minutos:segundos), o nil si
    /// ya vencio.
    static func countdownText(until expiresAt: Date, now: Date = Date()) -> String? {
        let remaining = Int(expiresAt.timeIntervalSince(now).rounded(.down))
        guard remaining > 0 else { return nil }
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    /// El descuento mas alto en % para el aviso de desbloqueo ("hasta 20%"),
    /// o nil si no hay descuentos en %.
    static func bestPercentText(_ entries: [BenefitEntry]) -> String? {
        let percents = entries.compactMap { entry -> Int? in
            guard entry.item.kind == .porcentaje else { return nil }
            return RewardsMath.leadingNumber(in: entry.item.name)
        }
        guard let best = percents.max(), best > 0 else { return nil }
        return "hasta \(best)%"
    }

    /// Titulo del dialogo antes de generar el codigo.
    static func confirmationTitle(for item: RewardItem) -> String {
        "¿Usar \(item.name) en \(item.merchantName) ahora?"
    }
}

extension RewardsMath {
    /// "Mis canjes" sin los codigos de descuento que vencieron sin usarse
    /// (duran 15 minutos: llenarian el historial de "Vencido").
    static func historyRows(_ rows: [RewardRedemption], now: Date = Date()) -> [RewardRedemption] {
        rows.filter { !($0.isBenefit && $0.effectiveStatus(now: now) == .vencido) }
    }

    /// "20% de descuento" -> 20. nil si el texto no empieza con un numero.
    static func leadingNumber(in text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}

/// Categoria de comercio que se administra en el panel (`merchant_categories`,
/// migracion 0068): nombre, emoji y orden.
struct MerchantCategory: Decodable, Hashable {
    var name: String
    var emoji: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case name, emoji
        case sortOrder = "sort_order"
    }
}

extension RewardsMath {
    /// Ordena las categorias como en el panel (sort_order); las que no
    /// estan en el panel van al final, en orden alfabetico.
    static func orderedCategories(_ names: [String], info: [MerchantCategory]) -> [String] {
        let order = Dictionary(info.map { ($0.name, $0.sortOrder) }, uniquingKeysWith: { first, _ in first })
        return names.sorted { lhs, rhs in
            let left = order[lhs] ?? Int.max
            let right = order[rhs] ?? Int.max
            if left != right { return left < right }
            return lhs.localizedLowercase < rhs.localizedLowercase
        }
    }

    /// "🍽️ Restaurantes y cafeterías" (o solo el nombre si no tiene emoji).
    static func categoryTitle(_ name: String, info: [MerchantCategory]) -> String {
        guard let emoji = info.first(where: { $0.name == name })?.emoji?.trimmingCharacters(in: .whitespaces),
              !emoji.isEmpty else { return name }
        return "\(emoji) \(name)"
    }
}
