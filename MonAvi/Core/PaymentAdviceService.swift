import Foundation
import Supabase

/// Como ordenar las deudas dentro del plan de "que pagar primero" — solo
/// afecta el orden ENTRE deudas (bills/recurrentes siguen ordenandose por
/// vencimiento/prioridad, eso no cambia). El ranking real lo calcula
/// `prioritize-payments` con reglas deterministas, no Claude.
enum DebtPayoffStrategy: String, CaseIterable, Identifiable {
    case avalanche
    case snowball

    static let storageKey = "debtPayoffStrategy"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .avalanche: return "Avalancha"
        case .snowball: return "Bola de nieve"
        }
    }

    var explanation: String {
        switch self {
        case .avalanche: return "Primero la deuda con mayor tasa de interes — ahorras mas a largo plazo."
        case .snowball: return "Primero la deuda con menor saldo — la liquidas rapido y ganas impulso."
        }
    }
}

struct PaymentAdviceItem: Decodable, Identifiable {
    let id: String
    let source: String
    let rank: Int
    let reason: String
    let name: String
    let amount: Double
    let dueInfo: String
    let accountId: String
    let movementType: String
    let category: String?
}

struct PaymentAdviceResponse: Decodable {
    let hasAdvice: Bool
    let advice: String?
    let items: [PaymentAdviceItem]?
}

/// El diferenciador de MonAvi: al registrar un ingreso, pregunta que hacer
/// primero con ese dinero (Edge Function prioritize-payments).
enum PaymentAdviceService {
    private struct Payload: Encodable {
        let userId: String
        let incomeAmount: Double
        let debtStrategy: String
    }

    static func fetch(userId: UUID, incomeAmount: Decimal) async throws -> PaymentAdviceResponse {
        let strategy = DebtPayoffStrategy(
            rawValue: UserDefaults.standard.string(forKey: DebtPayoffStrategy.storageKey) ?? ""
        ) ?? .avalanche

        let supabase = SupabaseManager.shared.client
        return try await supabase.functions.invoke(
            "prioritize-payments",
            options: FunctionInvokeOptions(
                body: Payload(
                    userId: userId.uuidString,
                    incomeAmount: NSDecimalNumber(decimal: incomeAmount).doubleValue,
                    debtStrategy: strategy.rawValue
                )
            )
        )
    }
}
