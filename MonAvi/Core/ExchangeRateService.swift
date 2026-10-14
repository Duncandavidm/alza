import Foundation
import Supabase

/// Conversion automatica de moneda (inspirado en "Paga en otra moneda y
/// MonAi la convierte a la tuya al instante"), via la Edge Function
/// exchange-rate.
enum ExchangeRateService {
    struct ConversionResult: Decodable {
        let rate: Double
        let convertedAmount: Double
    }

    private struct Payload: Encodable {
        let from: String
        let to: String
        let amount: Double
    }

    /// Monedas comunes en Centroamerica/LatAm que se ofrecen en el picker.
    /// frankfurter.app (ECB) no cubre todas las monedas del mundo — si el
    /// usuario necesita una que no esta aqui o falla la conversion, se le
    /// avisa y puede escribir el monto ya convertido a mano.
    static let commonCurrencies = ["USD", "EUR", "GBP", "MXN", "COP", "PEN", "CLP", "BRL", "CAD"]

    static func convert(amount: Decimal, from: String, to: String) async throws -> ConversionResult {
        let supabase = SupabaseManager.shared.client
        return try await supabase.functions.invoke(
            "exchange-rate",
            options: FunctionInvokeOptions(
                body: Payload(from: from, to: to, amount: NSDecimalNumber(decimal: amount).doubleValue)
            )
        )
    }
}
