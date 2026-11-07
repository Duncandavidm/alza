import Foundation
import Supabase

// MARK: - Respuesta cruda de la Edge Function `lookup-dgi-receipt`

/// Un producto de la factura tal como lo devuelve `lookup-dgi-receipt`.
struct DgiLookupItem: Decodable, Sendable, Equatable {
    let description: String
    let quantity: Double?
    let total: Double?
    let category: String?

    enum CodingKeys: String, CodingKey {
        case description
        case quantity
        case total
        case category
    }
}

/// Monto por categoria que sugiere `lookup-dgi-receipt`.
struct DgiLookupBreakdownEntry: Decodable, Sendable, Equatable {
    let category: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case category
        case amount
    }
}

/// Cuerpo JSON de `lookup-dgi-receipt`. Todos los campos menos `status`
/// son opcionales porque cada estado (confirmada / pendiente /
/// no_disponible / duplicada) trae un subconjunto distinto.
struct DgiLookupResponse: Decodable, Sendable, Equatable {
    let status: String
    let merchantName: String?
    let amount: Double?
    let authorizedAt: String?
    let paymentMethods: [String]?
    let items: [DgiLookupItem]?
    let suggestedCategory: String?
    let breakdown: [DgiLookupBreakdownEntry]?
    let incomeTotal: Double?
    let backedTotal: Double?
    let incomeBacksPurchase: Bool?
    let mine: Bool?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case merchantName = "merchant_name"
        case amount
        case authorizedAt = "authorized_at"
        case paymentMethods = "payment_methods"
        case items
        case suggestedCategory = "suggested_category"
        case breakdown
        case incomeTotal = "income_total"
        case backedTotal = "backed_total"
        case incomeBacksPurchase = "income_backs_purchase"
        case mine
        case message
    }
}

// MARK: - Resultado ya interpretado (lo que usa la UI)

/// Producto ya listo para mostrar en la seccion "Productos".
struct DgiInvoiceItem: Equatable, Identifiable {
    let id: Int
    let description: String
    let quantity: Double?
    let total: Decimal?
}

/// Una linea del desglose por categoria (y, si el usuario activa
/// "Separar por categoría", un gasto aparte).
struct DgiCategorySplitLine: Equatable, Identifiable {
    /// Nombre tal como vino (rawValue de `TransactionCategory`, o texto
    /// libre si no se reconoce).
    let categoryName: String
    let category: TransactionCategory?
    let amount: Decimal

    var id: String { categoryName }
}

/// Datos de la factura cuando ya esta disponible (status "confirmada").
struct DgiInvoiceDetails: Equatable {
    let merchantName: String?
    let amount: Decimal?
    let authorizedAt: Date?
    let paymentMethods: [String]
    let items: [DgiInvoiceItem]
    let suggestedCategory: TransactionCategory?
    let breakdown: [DgiCategorySplitLine]
    let incomeBacksPurchase: Bool
}

enum DgiLookupOutcome: Equatable {
    /// Factura leida: se prellenan monto, comercio, fecha y categoria.
    case confirmed(DgiInvoiceDetails)
    /// Aun no aparece, o el servicio no respondio: flujo manual.
    /// `incomeTotal` = ingresos registrados en los ultimos 35 dias (nil si
    /// no se sabe).
    case manual(incomeTotal: Decimal?)
    /// Demasiadas consultas: flujo manual con una nota suave.
    case rateLimited
    /// Ya registrada (por el usuario u otra cuenta): no se puede guardar.
    case duplicate(message: String, mine: Bool)
    /// Error de red / timeout / respuesta rara: flujo manual sin nota.
    case failed

    /// Mostrar el aviso de "registra tus ingresos para recibir el cashback".
    var showsIncomeNotice: Bool {
        switch self {
        case .confirmed(let details):
            return !details.incomeBacksPurchase
        case .manual(let incomeTotal):
            return (incomeTotal ?? 1) <= 0
        case .rateLimited, .duplicate, .failed:
            return false
        }
    }
}

// MARK: - Logica pura (con pruebas en MonAviTests/DgiInvoiceLookupTests)

enum DgiInvoiceLookupLogic {
    /// "Supermercado" -> `.groceries`. Desconocido, vacio o "Ingreso"
    /// (no tiene sentido para un gasto) -> nil.
    static func category(from raw: String?) -> TransactionCategory? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard let category = TransactionCategory(rawValue: trimmed), category != .income else {
            return nil
        }
        return category
    }

    /// Dolares (Double del JSON) -> Decimal redondeado a centavos, sin el
    /// ruido binario de Double (12.34 no termina en 12.339999…).
    static func decimal(fromDollars value: Double) -> Decimal {
        Decimal(Int((value * 100).rounded())) / 100
    }

    /// Monto para el campo de texto: siempre "12.50" (punto, 2 decimales,
    /// sin separador de miles) — lo mismo que el usuario escribiria.
    static func amountText(for amount: Decimal) -> String {
        let amountCents = cents(from: amount)
        let sign = amountCents < 0 ? "-" : ""
        let absolute = abs(amountCents)
        let fraction = absolute % 100
        return "\(sign)\(absolute / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    /// Decimal -> centavos enteros (redondeo normal).
    static func cents(from value: Decimal) -> Int {
        var input = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// Fecha de autorizacion ("2026-11-05T14:32:00-05:00").
    static func date(fromISO raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }

    /// Reparte `totalCents` en proporcion a `weights` (centavos) con el
    /// metodo del residuo mayor: el resultado SIEMPRE suma exactamente
    /// `totalCents`. Pesos negativos cuentan como 0; si todos son 0, se
    /// reparte en partes iguales (el sobrante va a las primeras).
    static func allocate(totalCents: Int, weights: [Int]) -> [Int] {
        guard !weights.isEmpty else { return [] }
        let safeTotal = max(0, totalCents)
        let safeWeights = weights.map { max(0, $0) }
        let weightSum = safeWeights.reduce(0, +)

        guard weightSum > 0 else {
            let base = safeTotal / safeWeights.count
            let extra = safeTotal % safeWeights.count
            return safeWeights.indices.map { base + ($0 < extra ? 1 : 0) }
        }

        var shares: [Int] = []
        var remainders: [(index: Int, remainder: Int)] = []
        for (index, weight) in safeWeights.enumerated() {
            let product = safeTotal * weight
            shares.append(product / weightSum)
            remainders.append((index, product % weightSum))
        }

        var leftover = safeTotal - shares.reduce(0, +)
        // Residuo mayor primero; empate -> el que va antes.
        let order = remainders.sorted {
            $0.remainder != $1.remainder ? $0.remainder > $1.remainder : $0.index < $1.index
        }
        var cursor = 0
        while leftover > 0 && !order.isEmpty {
            shares[order[cursor % order.count].index] += 1
            leftover -= 1
            cursor += 1
        }
        return shares
    }

    /// Desglose por categoria ajustado a `total` (lo que el usuario deja
    /// como monto final): agrupa categorias repetidas, reparte en
    /// centavos de forma que la suma sea exacta, y quita las lineas en 0.
    static func splitLines(breakdown: [DgiCategorySplitLine], total: Decimal) -> [DgiCategorySplitLine] {
        var grouped: [(name: String, category: TransactionCategory?, cents: Int)] = []
        for line in breakdown {
            let lineCents = cents(from: line.amount)
            if let index = grouped.firstIndex(where: { $0.name == line.categoryName }) {
                grouped[index].cents += lineCents
            } else {
                grouped.append((line.categoryName, line.category, lineCents))
            }
        }
        let allocated = allocate(totalCents: cents(from: total), weights: grouped.map(\.cents))
        return zip(grouped, allocated).compactMap { entry, amountCents in
            guard amountCents > 0 else { return nil }
            return DgiCategorySplitLine(
                categoryName: entry.name,
                category: entry.category,
                amount: Decimal(amountCents) / 100
            )
        }
    }

    /// Indice de la linea mas grande (la primera si hay empate) — a esa
    /// transaccion se vincula la factura cuando se separa por categoria.
    static func indexOfLargest(_ amounts: [Decimal]) -> Int? {
        guard !amounts.isEmpty else { return nil }
        var best = 0
        for index in amounts.indices where amounts[index] > amounts[best] {
            best = index
        }
        return best
    }

    /// Descripcion de cada gasto separado: "Super 99 · Supermercado".
    static func splitDescription(merchant: String, categoryName: String) -> String {
        "\(merchant) · \(categoryName)"
    }

    /// Respuesta cruda -> resultado que usa la UI.
    static func outcome(from response: DgiLookupResponse) -> DgiLookupOutcome {
        switch response.status {
        case "confirmada":
            let merchant = response.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let items = (response.items ?? []).enumerated().map { index, item in
                DgiInvoiceItem(
                    id: index,
                    description: item.description,
                    quantity: item.quantity,
                    total: item.total.map(decimal(fromDollars:))
                )
            }
            let breakdown = (response.breakdown ?? []).map { entry in
                DgiCategorySplitLine(
                    categoryName: entry.category,
                    category: category(from: entry.category),
                    amount: decimal(fromDollars: entry.amount)
                )
            }
            let amount = response.amount.map(decimal(fromDollars:))
            return .confirmed(
                DgiInvoiceDetails(
                    merchantName: (merchant?.isEmpty ?? true) ? nil : merchant,
                    amount: amount,
                    authorizedAt: date(fromISO: response.authorizedAt),
                    paymentMethods: (response.paymentMethods ?? []).filter { !$0.isEmpty },
                    items: items,
                    suggestedCategory: category(from: response.suggestedCategory),
                    breakdown: breakdown,
                    // Sin dato, se asume respaldado (no asustar de mas).
                    incomeBacksPurchase: response.incomeBacksPurchase ?? true
                )
            )
        case "pendiente", "no_disponible":
            return .manual(incomeTotal: response.incomeTotal.map(decimal(fromDollars:)))
        case "duplicada":
            let message = response.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .duplicate(
                message: (message?.isEmpty ?? true) ? "Esta factura ya fue registrada." : (message ?? ""),
                mine: response.mine ?? false
            )
        default:
            return .failed
        }
    }
}

// MARK: - Llamada a la Edge Function

enum DgiInvoiceLookupService {
    private struct Payload: Encodable, Sendable {
        let cufe: String
        enum CodingKeys: String, CodingKey { case cufe }
    }

    private struct TimeoutError: Error {}

    /// Nunca lanza: cualquier fallo (red, timeout, 4xx/5xx) cae al flujo
    /// manual de siempre.
    static func lookup(cufe: String, timeoutSeconds: Double = 15) async -> DgiLookupOutcome {
        let client = SupabaseManager.shared.client
        do {
            let response = try await withThrowingTaskGroup(of: DgiLookupResponse.self) { group -> DgiLookupResponse in
                group.addTask {
                    try await client.functions.invoke(
                        "lookup-dgi-receipt",
                        options: FunctionInvokeOptions(body: Payload(cufe: cufe))
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    throw TimeoutError()
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw TimeoutError() }
                return first
            }
            return DgiInvoiceLookupLogic.outcome(from: response)
        } catch {
            if let functionsError = error as? FunctionsError,
               case .httpError(let code, _) = functionsError,
               code == 429 {
                return .rateLimited
            }
            return .failed
        }
    }
}
