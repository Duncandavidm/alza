import Foundation

/// Adivina la categoria de un gasto a partir del nombre del comercio —
/// por palabras clave, sin IA ni red: tiene que correr instantaneo dentro
/// de AddAviExpenseIntent (la automatizacion de Atajos/Apple Pay no tiene
/// por que esperar una llamada a un modelo para algo tan simple). No es
/// perfecto, pero cubre los casos mas comunes de un comercio tipico.
enum MerchantCategoryGuesser {
    private static let keywordsByCategory: [TransactionCategory: [String]] = [
        .food: [
            "restaurante", "resto", "cafe", "café", "cafeteria", "starbucks", "mcdonald",
            "kfc", "burger", "pizza", "sushi", "panaderia", "super", "supermercado",
            "minimarket", "mini market", "grocery", "market", "comida", "bar", "cantina",
        ],
        .transport: [
            "uber", "taxi", "cabify", "didi", "gasolina", "gas station", "estacion de servicio",
            "parking", "estacionamiento", "metro", "bus", "peaje", "combustible",
        ],
        .entertainment: [
            "cine", "cinema", "netflix", "spotify", "disney", "hbo", "teatro", "concierto",
            "boletos", "tickets", "juegos", "steam", "playstation", "xbox",
        ],
        .health: [
            "farmacia", "hospital", "clinica", "clínica", "doctor", "medico", "médico",
            "dental", "laboratorio", "pharmacy",
        ],
        .housing: [
            "ferreteria", "ferretería", "electricidad", "acueducto", "agua", "alquiler",
            "renta", "mueble", "home depot", "hardware",
        ],
    ]

    /// nil si ninguna palabra clave coincide — se deja sin categoria (igual
    /// que cuando el usuario no elige ninguna a mano) en vez de forzar
    /// "Otro" como si fuera una deteccion real.
    static func category(for merchant: String) -> TransactionCategory? {
        let normalized = merchant
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        for (category, keywords) in keywordsByCategory {
            for keyword in keywords {
                let normalizedKeyword = keyword.folding(options: .diacriticInsensitive, locale: .current)
                if normalized.contains(normalizedKeyword) {
                    return category
                }
            }
        }
        return nil
    }
}
