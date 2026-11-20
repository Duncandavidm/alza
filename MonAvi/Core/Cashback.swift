import Foundation

/// Los puntos canjeables se muestran como cashback en dolares: el ledger
/// guarda enteros donde 1 punto = US$0.01 (1% de cada factura verificada
/// por la DGI; una factura de $84.25 da 84 = $0.84). El cashback siempre
/// se muestra con este formato, nunca como "pts". Los puntos por habitos
/// (`habit_points`) son otra moneda: se muestran como "150 pts"
/// (`RewardCurrency.format`).
enum Cashback {
    /// Locale fijo para que siempre se vea "$6.50" (Panama usa el mismo
    /// separador decimal "." y de miles "," que en_US) sin depender del
    /// idioma del telefono ("US$" o "6,50 US$").
    private static let displayLocale = Locale(identifier: "en_US")

    /// Centavos -> "$6.50" (siempre 2 decimales).
    static func format(cents: Int) -> String {
        let amount = Decimal(cents) / 100
        return amount.formatted(
            .currency(code: "USD")
                .locale(displayLocale)
                .precision(.fractionLength(2))
        )
    }
}
