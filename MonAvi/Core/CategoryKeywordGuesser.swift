import Foundation

/// Sugiere una categoria a partir de lo que el usuario escribe en "¿Qué
/// fue?" (ej. "hamburguesa" → Comida, "quincena" → Ingreso). Puro y
/// sin red, para correr mientras escribe.
///
/// Como compara (todo sin tildes ni mayusculas):
/// 1. Frases de varias palabras primero ("comida de perro" → Mascotas,
///    "seguro medico" → Salud, "cuota de mantenimiento" → Vivienda); gana la
///    mas larga.
/// 2. Si ninguna frase coincide, palabra por palabra: a cada palabra del
///    texto se le busca la palabra clave mas larga que la empiece ("pizzas"
///    → "pizza", "aguacate" → "aguacate" y no "agua"). Si varias palabras
///    caen en categorias distintas, gana la de mayor prioridad
///    (`priority`): "comida para el perro" → Mascotas.
///
/// Las palabras clave de 3 letras o menos ("bar", "gas", "rey", "max") y las
/// que empiezan con "=" ("=plan", "=claro") tienen que ser la palabra
/// entera, asi "barberia" no es "bar" ni "gasolina" es "gas".
enum CategoryKeywordGuesser {
    /// Palabras de ingreso: solo se usan cuando el movimiento es una entrada.
    static let incomeKeywords: [String] = [
        "salario", "sueldo", "quincena", "pago", "pagaron", "me pagaron", "pago de nomina",
        "nomina", "planilla", "honorarios", "comision", "bono", "bonificacion",
        "venta", "ventas", "vendi", "cobro", "cobre", "cliente", "freelance", "factura cobrada",
        "aguinaldo", "decimo", "decimo tercer mes", "tercer mes", "xiii mes", "propina", "propinas",
        "intereses", "interes ganado", "reembolso", "devolucion", "reintegro", "dividendos",
        "pension", "jubilacion", "remesa", "me depositaron", "me transfirieron", "me yapearon",
        "ingreso", "ganancia", "utilidades", "alquiler cobrado", "arriendo cobrado",
    ]

    /// Palabras clave por categoria (sin importar el orden: la prioridad la
    /// da `priority`).
    static let keywordsByCategory: [(TransactionCategory, [String])] = [
        (.housing, [
            "arriendo", "arrendamiento", "alquiler", "alquiler casa", "alquiler apartamento",
            "=renta", "rentas", "renta de casa", "renta del apartamento", "hipoteca", "hipotecario",
            "mensualidad casa", "mensualidad de la casa", "mensualidad apartamento",
            "mensualidad del apartamento", "mensualidad apto", "mensualidad del apto",
            "apartamento", "=apto", "condominio", "cuota de mantenimiento", "cuota mantenimiento",
            "mantenimiento", "administracion", "administracion del edificio", "=ph",
            "propiedad horizontal", "mueble", "muebles", "colchon", "reparacion casa",
            "reparacion de la casa", "arreglo casa", "plomero", "plomeria", "electricista",
            "cerrajero", "pintura casa", "pintor", "aire acondicionado", "fumigacion",
            "empleada domestica", "empleada", "limpieza casa", "jardinero", "deposito de alquiler",
            "vivienda", "casa nueva",
        ]),
        (.utilities, [
            "luz", "factura de luz", "recibo de luz", "electricidad", "ensa", "naturgy", "edemet",
            "edechi", "agua", "recibo de agua", "idaan", "internet", "wifi", "cable onda",
            "cableonda", "=cable", "tigo", "mas movil", "masmovil", "=movil", "=claro", "digicel",
            "liberty", "celular", "telefono", "recarga", "recargas", "=plan",
            "plan de datos", "plan celular", "plan del celular", "=gas", "tanque de gas",
            "cilindro", "cilindro de gas", "gas de cocina", "basura", "aseo", "servicios",
            "servicios publicos",
        ]),
        (.groceries, [
            "supermercado", "super", "=sup", "mercado", "minisuper", "mini super", "abarrotes",
            "abarroteria", "=rey", "el rey", "riba smith", "ribasmith", "super 99", "super99",
            "=xtra", "super xtra", "machetazo", "el machetazo", "el fuerte", "pricesmart",
            "price smart", "felipe motta", "despensa", "viveres", "super carnes", "supercarnes",
            "romero", "super romero", "carniceria", "frutas", "verduras", "legumbres",
            "aguacate", "compra del super", "compras del super", "mercado de abastos",
            "aceite de oliva", "arroz", "huevos", "leche", "pan de molde", "jumbo",
        ]),
        (.food, [
            "almuerzo", "almorzar", "desayuno", "desayunar", "cena", "cenar", "comida",
            "comida rapida", "hamburguesa", "burger", "burger king", "pizza", "pollo", "sushi",
            "tacos", "taco", "burrito", "empanada", "hojaldra", "carimanola", "patacones",
            "sandwich", "emparedado", "cafe", "cafeteria", "restaurante", "restaurant", "fonda",
            "kfc", "mcdonald", "mcdonalds", "mc donalds", "subway", "domino", "dominos",
            "papa john", "papa johns", "pio pio", "piopio", "nikos", "niko s", "starbucks",
            "dunkin", "delivery", "pedidosya", "pedidos ya", "uber eats", "ubereats", "appetito",
            "appetito24", "helado", "helados", "panaderia", "postre", "dulces", "merienda",
            "lonchera", "arroz con pollo", "perro caliente", "perros calientes", "hot dog", "pasteleria", "pastel",
            "batido", "jugo", "snack", "comer afuera", "antojo",
        ]),
        (.transport, [
            "gasolina", "gasolinera", "combustible", "diesel", "taxi", "uber", "indrive", "cabify",
            "didi", "=bus", "buses", "pasaje de bus", "pasaje del bus", "metrobus", "metro",
            "tarjeta metro", "tarjeta del metro", "recarga metro", "recarga del metro",
            "recarga metrobus", "peaje", "panapass", "corredor", "corredor norte", "corredor sur",
            "estacionamiento", "parking", "parquimetro", "taller", "mecanico", "llanta", "llantas",
            "aceite", "cambio de aceite", "lavado", "lavado de carro", "lavado del carro",
            "car wash", "repuestos", "repuesto", "revisado", "carro", "=auto", "seguro del carro",
            "seguro de auto", "mantenimiento del carro", "placa", "grua", "bateria del carro",
            "transporte", "moto",
        ]),
        (.health, [
            "farmacia", "farmacias", "arrocha", "metro plus", "metroplus", "medicina", "medicinas",
            "medicamento", "medicamentos", "pastillas", "doctor", "doctora", "medico", "medica",
            "cita medica", "consulta", "consulta medica", "clinica", "hospital", "laboratorio",
            "examenes", "examen de sangre", "dentista", "odontologo", "ortodoncia", "optica",
            "lentes", "seguro medico", "seguro de salud", "poliza de salud", "terapia",
            "fisioterapia", "psicologo", "psicologa", "psiquiatra", "pediatra", "ginecologo",
            "vitaminas", "gimnasio", "=gym", "smart fit", "salud", "inyeccion", "vacuna",
        ]),
        (.clothing, [
            "ropa", "ropa interior", "zapatos", "zapatillas", "tenis", "sandalias", "camisa",
            "camiseta", "pantalon", "jeans", "vestido", "blusa", "falda", "medias", "zara",
            "h m", "=hm", "stevens", "uniforme", "uniformes", "bershka", "pull and bear",
            "forever 21", "nike", "adidas", "carters", "traje", "corbata", "cartera", "bolso",
        ]),
        (.shopping, [
            "amazon", "temu", "shein", "aliexpress", "ebay", "do it center", "doit center",
            "novey", "cochez", "ferreteria", "panafoto", "electronicos", "electronica",
            "celular nuevo", "telefono nuevo", "iphone nuevo", "multimax", "tienda", "compras",
            "conway", "titan", "audiofoto", "best buy", "mall", "albrook", "multiplaza",
            "apple store", "laptop", "computadora", "audifonos", "televisor",
        ]),
        (.subscriptions, [
            "netflix", "spotify", "disney", "disney plus", "hbo", "hbo max", "=max", "prime video",
            "amazon prime", "youtube premium", "youtube music", "=apple", "apple music",
            "apple tv", "apple one", "icloud", "chatgpt", "openai", "claude", "membresia",
            "suscripcion", "suscripciones", "crunchyroll", "paramount", "google one",
            "game pass", "xbox game pass", "playstation plus", "ps plus", "nintendo online",
            "canva", "dropbox", "office 365", "microsoft 365", "duolingo", "deezer", "star plus",
        ]),
        (.entertainment, [
            "cine", "cinepolis", "cinemark", "pelicula", "concierto", "juego", "juegos",
            "videojuego", "playstation", "=ps5", "xbox", "nintendo", "steam", "teatro", "boletos",
            "entradas", "evento", "boliche", "bolos", "museo", "parque de diversiones",
            "entretenimiento", "partido", "estadio",
        ]),
        (.goingOut, [
            "salir", "salida", "salidas", "cena fuera", "cena afuera", "tragos", "trago",
            "cerveza", "cervezas", "birras", "=bar", "bares", "discoteca", "=disco", "fiesta",
            "rumba", "parranda", "karaoke", "copa de vino", "copas", "vino", "licor", "=seco",
            "happy hour", "jangueo",
        ]),
        (.education, [
            "colegio", "escuela", "universidad", "=u", "matricula", "mensualidad colegio",
            "mensualidad del colegio", "mensualidad escolar", "mensualidad de la universidad",
            "libros", "libro", "utiles", "utiles escolares", "curso", "cursos", "clases", "clase",
            "udemy", "platzi", "coursera", "tutor", "tutoria", "diplomado", "maestria",
            "seminario", "inscripcion", "educacion", "guarderia", "kinder",
        ]),
        (.pets, [
            "veterinario", "veterinaria", "vet", "perro", "perros", "perrito", "perrita", "gato",
            "gatos", "gatito", "mascota", "mascotas", "concentrado", "croquetas", "grooming",
            "=pet", "pets", "petshop", "pet shop", "petco", "comida de perro", "comida para perro",
            "comida del perro", "comida de gato", "comida para gato", "comida del gato",
            "arena para gato", "arena de gato", "bano del perro", "vacuna del perro",
        ]),
        (.gifts, [
            "regalo", "regalos", "cumpleanos", "obsequio", "detalle", "donacion", "donativo",
            "ofrenda", "diezmo", "baby shower", "dia de la madre", "dia del padre", "san valentin",
            "aniversario",
        ]),
        (.travel, [
            "hotel", "hostal", "airbnb", "vuelo", "vuelos", "pasaje", "pasaje aereo",
            "boleto avion", "boleto de avion", "boleto aereo", "=copa", "copa airlines",
            "maleta", "equipaje", "viaje", "vacaciones", "hospedaje", "booking", "expedia",
            "aeropuerto", "tocumen", "alquiler de carro", "renta de carro", "rent a car",
            "crucero", "tour",
        ]),
        (.savings, [
            "ahorro", "ahorros", "ahorre", "guarde", "alcancia", "deposito a plazo",
            "plazo fijo", "fondo de emergencia", "cuenta de ahorro", "meta de ahorro",
        ]),
        (.suppliers, [
            "proveedor", "proveedores", "pago a proveedor", "pago al proveedor", "mercancia",
            "mercaderia", "insumos", "materia prima", "distribuidor", "distribuidora",
            "inventario",
        ]),
        (.transfers, [
            "transferencia", "transferencias", "transferi", "transferir", "=ach", "yappy",
            "yapee", "nequi", "envie dinero", "envie plata", "le pase", "le pase plata",
            "mande plata", "mande dinero", "le mande", "envio de dinero", "western union",
            "remesa enviada",
        ]),
    ]

    /// Ante un empate entre palabras sueltas de categorias distintas, la
    /// primera de esta lista gana: las intenciones mas especificas antes que
    /// las generales ("comida para el perro" → Mascotas, "taxi al super" →
    /// Transporte, "almuerzo en el super" → Supermercado).
    static let priority: [TransactionCategory] = [
        .savings, .transfers, .suppliers, .pets, .gifts, .education, .health, .travel,
        .subscriptions, .utilities, .housing, .transport, .groceries, .clothing, .goingOut,
        .entertainment, .food, .shopping,
    ]

    private struct Keyword {
        let words: [String]
        let exact: Bool
        let category: TransactionCategory
        var length: Int { words.joined(separator: " ").count }
    }

    /// Las palabras clave ya normalizadas, una sola vez.
    private static let compiled: [Keyword] = {
        var result: [Keyword] = []
        for (category, keywords) in keywordsByCategory {
            result.append(contentsOf: keywords.compactMap { compile($0, category: category) })
        }
        return result
    }()

    private static let compiledIncome: [Keyword] = incomeKeywords.compactMap {
        compile($0, category: .income)
    }

    private static func compile(_ raw: String, category: TransactionCategory) -> Keyword? {
        let forcedExact = raw.hasPrefix("=")
        let text = forcedExact ? String(raw.dropFirst()) : raw
        let words = normalizedWords(text)
        guard !words.isEmpty else { return nil }
        let exact = forcedExact || (words.count == 1 && words[0].count <= 3)
        return Keyword(words: words, exact: exact, category: category)
    }

    /// La categoria sugerida para `text`, o nil si nada coincide.
    /// - Parameter isInflow: true si el movimiento es una entrada de dinero;
    ///   entonces las palabras de ingreso ("quincena", "pago") ganan.
    static func category(for text: String, isInflow: Bool) -> TransactionCategory? {
        let words = normalizedWords(text)
        guard words.joined().count >= 2 else { return nil }

        if isInflow, bestMatch(in: words, among: compiledIncome) != nil {
            return .income
        }

        if let found = bestMatch(in: words, among: compiled) {
            return found
        }

        if isInflow { return nil }
        // Respaldo: el adivinador de comercios (Atajos/Apple Pay) conoce
        // otros nombres de tiendas.
        return MerchantCategoryGuesser.category(for: text)
    }

    /// Frases primero (la mas larga gana), luego palabras sueltas resueltas
    /// por `priority`.
    private static func bestMatch(in words: [String], among keywords: [Keyword]) -> TransactionCategory? {
        // 1. Frases de varias palabras.
        let phrases = keywords
            .filter { $0.words.count > 1 && matches($0, in: words) }
            .sorted { lhs, rhs in
                if lhs.words.count != rhs.words.count { return lhs.words.count > rhs.words.count }
                if lhs.length != rhs.length { return lhs.length > rhs.length }
                return rank(lhs.category) < rank(rhs.category)
            }
        if let phrase = phrases.first { return phrase.category }

        // 2. Palabras sueltas: para cada palabra, la palabra clave mas larga.
        var candidates: [TransactionCategory] = []
        let singles = keywords.filter { $0.words.count == 1 }
        for word in words {
            let best = singles
                .filter { wordMatches(word, keyword: $0.words[0], exact: $0.exact) }
                .max { lhs, rhs in
                    if lhs.length != rhs.length { return lhs.length < rhs.length }
                    return rank(lhs.category) > rank(rhs.category)
                }
            if let best { candidates.append(best.category) }
        }
        return candidates.min { rank($0) < rank($1) }
    }

    private static func rank(_ category: TransactionCategory) -> Int {
        priority.firstIndex(of: category) ?? priority.count
    }

    /// Las palabras de la frase, seguidas, en el texto; la ultima puede ser
    /// solo el inicio de una palabra (salvo frases exactas).
    private static func matches(_ keyword: Keyword, in words: [String]) -> Bool {
        let count = keyword.words.count
        guard words.count >= count else { return false }
        for start in 0...(words.count - count) {
            var ok = true
            for offset in 0..<count {
                let word = words[start + offset]
                let key = keyword.words[offset]
                let isLast = offset == count - 1
                if isLast && !keyword.exact {
                    if !word.hasPrefix(key) { ok = false; break }
                } else if word != key {
                    ok = false; break
                }
            }
            if ok { return true }
        }
        return false
    }

    private static func wordMatches(_ word: String, keyword: String, exact: Bool) -> Bool {
        exact ? word == keyword : word.hasPrefix(keyword)
    }

    /// Sin tildes, en minusculas, solo letras/numeros.
    static func normalizedWords(_ text: String) -> [String] {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_PA"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Sin tildes, en minusculas, solo letras/numeros separados por un
    /// espacio, con espacio al inicio y al final para comparar por palabra.
    static func normalizedPadded(_ text: String) -> String {
        " " + normalizedWords(text).joined(separator: " ") + " "
    }
}
