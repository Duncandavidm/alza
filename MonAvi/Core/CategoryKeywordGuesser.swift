import Foundation

/// Sugiere una categoria a partir de lo que el usuario escribe en "¿Qué
/// fue?" (ej. "hamburguesa" → Comida, "quincena" → Ingreso). Puro y
/// sin red, para correr mientras escribe. Compara por inicio de palabra
/// (sin tildes ni mayusculas), asi "pizzas" coincide con "pizza" y
/// "supermercado" con "super", pero "barberia" no coincide con "bar".
enum CategoryKeywordGuesser {
    /// Palabras de ingreso: solo se usan cuando el movimiento es una entrada.
    static let incomeKeywords: [String] = [
        "salario", "sueldo", "quincena", "pago", "pagaron", "nomina", "nómina",
        "honorarios", "comision", "comisión", "bono", "venta", "cobro", "cliente",
        "freelance", "aguinaldo", "decimo", "décimo",
    ]

    /// En orden: la primera categoria que coincida gana, por eso las mas
    /// especificas van antes (ej. Supermercado antes que Comida).
    static let keywordsByCategory: [(TransactionCategory, [String])] = [
        (.groceries, [
            "supermercado", "super", "mercado", "minisuper", "abarrotes", "riba smith",
            "rey", "el machetazo", "xtra", "pricesmart", "despensa",
        ]),
        (.food, [
            "hamburguesa", "burger", "pizza", "almuerzo", "cena", "desayuno", "cafe",
            "café", "cafeteria", "restaurante", "fonda", "comida", "sushi", "pollo",
            "empanada", "helado", "panaderia", "panadería", "mcdonald", "kfc",
            "starbucks", "delivery", "pedidosya", "appetito", "merienda", "lonchera",
        ]),
        (.transport, [
            "gasolina", "combustible", "diesel", "taxi", "uber", "indrive", "cabify",
            "didi", "bus", "metrobus", "metro", "peaje", "corredor", "panapass",
            "estacionamiento", "parking", "carro", "taller", "llanta",
        ]),
        (.utilities, [
            "luz", "agua", "idaan", "internet", "celular", "telefono", "teléfono",
            "ensa", "naturgy", "edemet", "cable onda", "tigo", "mas movil", "más móvil",
            "claro", "digicel", "tanque de gas", "cilindro de gas", "recarga",
        ]),
        (.housing, [
            "alquiler", "renta", "hipoteca", "mantenimiento", "condominio", "ferreteria",
            "ferretería", "mueble",
        ]),
        (.health, [
            "farmacia", "medicina", "medicamento", "doctor", "medico", "médico",
            "clinica", "clínica", "hospital", "dentista", "laboratorio", "consulta",
            "seguro medico", "arrocha",
        ]),
        (.clothing, [
            "ropa", "zapatos", "zapatillas", "camisa", "pantalon", "pantalón", "vestido",
            "tenis",
        ]),
        (.subscriptions, [
            "netflix", "spotify", "disney", "hbo", "max", "prime video", "youtube premium",
            "icloud", "apple music", "chatgpt", "suscripcion", "suscripción", "membresia",
            "membresía",
        ]),
        (.entertainment, [
            "cine", "juego", "videojuego", "playstation", "xbox", "nintendo", "steam",
            "concierto", "teatro", "boletos", "entradas",
        ]),
        (.goingOut, [
            "cerveza", "cervezas", "tragos", "discoteca", "fiesta", "bar",
        ]),
        (.education, [
            "colegio", "escuela", "universidad", "matricula", "matrícula", "libros",
            "libro", "curso", "utiles", "útiles", "mensualidad escolar",
        ]),
        (.pets, [
            "veterinario", "veterinaria", "perro", "gato", "mascota", "concentrado",
        ]),
        (.gifts, [
            "regalo", "cumpleaños", "cumpleanos",
        ]),
        (.travel, [
            "hotel", "vuelo", "pasaje", "boleto aereo", "boleto aéreo", "airbnb",
            "copa airlines", "viaje", "hospedaje",
        ]),
        (.shopping, [
            "amazon", "shein", "temu", "compras", "tienda",
        ]),
        (.savings, [
            "ahorro", "ahorros",
        ]),
    ]

    /// La categoria sugerida para `text`, o nil si nada coincide.
    /// - Parameter isInflow: true si el movimiento es una entrada de dinero;
    ///   entonces las palabras de ingreso ("quincena", "pago") ganan.
    static func category(for text: String, isInflow: Bool) -> TransactionCategory? {
        let padded = normalizedPadded(text)
        guard padded.trimmingCharacters(in: .whitespaces).count >= 2 else { return nil }

        if isInflow {
            if matches(padded, any: incomeKeywords) { return .income }
        }

        for (category, keywords) in keywordsByCategory where matches(padded, any: keywords) {
            return category
        }

        if isInflow { return nil }
        // Respaldo: el adivinador de comercios (Atajos/Apple Pay) conoce
        // otros nombres de tiendas.
        return MerchantCategoryGuesser.category(for: text)
    }

    /// Sin tildes, en minusculas, solo letras/numeros separados por un
    /// espacio, con espacio al inicio y al final para comparar por palabra.
    static func normalizedPadded(_ text: String) -> String {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_PA"))
            .lowercased()
        let words = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return " " + words.joined(separator: " ") + " "
    }

    /// Cada palabra clave tiene que empezar una palabra del texto.
    private static func matches(_ padded: String, any keywords: [String]) -> Bool {
        keywords.contains { keyword in
            let normalized = normalizedPadded(keyword).trimmingCharacters(in: .whitespaces)
            guard !normalized.isEmpty else { return false }
            return padded.contains(" " + normalized)
        }
    }
}
