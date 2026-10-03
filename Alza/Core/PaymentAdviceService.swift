import Foundation
import Supabase

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

/// El diferenciador de Amadai: al registrar un ingreso, pregunta que hacer
/// primero con ese dinero (Edge Function prioritize-payments).
enum PaymentAdviceService {
    private struct Payload: Encodable {
        let userId: String
        let incomeAmount: Double
    }

    static func fetch(userId: UUID, incomeAmount: Decimal) async throws -> PaymentAdviceResponse {
        let supabase = SupabaseManager.shared.client
        return try await supabase.functions.invoke(
            "prioritize-payments",
            options: FunctionInvokeOptions(
                body: Payload(userId: userId.uuidString, incomeAmount: NSDecimalNumber(decimal: incomeAmount).doubleValue)
            )
        )
    }
}
