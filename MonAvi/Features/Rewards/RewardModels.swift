import Foundation

/// Moneda en la que un comercio aliado canjea sus premios
/// (`partner_merchants.reward_currency`, migracion 0036):
/// - `cashback`: US$ en centavos, de facturas verificadas por la DGI.
/// - `puntos`: puntos ganados con buenos habitos.
enum RewardCurrency: String, Codable, CaseIterable, Hashable {
    case cashback
    case puntos

    /// Tolerante: un valor desconocido cae en `.cashback` en vez de
    /// romper el decodificado de todo el catalogo.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = RewardCurrency(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .cashback
    }

    /// Costo o saldo en esta moneda: cashback -> "$3.50", puntos -> "150 pts".
    func format(_ amount: Int) -> String {
        switch self {
        case .cashback:
            return Cashback.format(cents: amount)
        case .puntos:
            return RewardCurrency.formatPoints(amount)
        }
    }

    /// "1,500 pts" (separador de miles fijo, como el cashback).
    static func formatPoints(_ points: Int) -> String {
        let number = points.formatted(.number.locale(Locale(identifier: "en_US")))
        return "\(number) pts"
    }

    /// Badge de cada comercio: "Canje con puntos" / "Canje con cashback".
    var badgeText: String {
        switch self {
        case .cashback: return "Canje con cashback"
        case .puntos: return "Canje con puntos"
        }
    }

    var systemImage: String {
        switch self {
        case .cashback: return "dollarsign.circle.fill"
        case .puntos: return "star.circle.fill"
        }
    }
}

/// Producto canjeable de un comercio aliado (tabla `reward_items`,
/// migracion 0031). La RLS solo devuelve productos activos de comercios
/// activos. Se lee con el comercio embebido:
/// `select("*, partner_merchants(*)")` -> clave JSON `partner_merchants`.
struct RewardItem: Codable, Identifiable, Hashable {
    let id: UUID
    let merchantId: UUID
    var name: String
    /// Columna `description` — se renombra para no confundirla con
    /// `CustomStringConvertible.description`.
    var itemDescription: String?
    var photoUrl: String?
    var pointsCost: Int
    var status: String
    var sortOrder: Int
    /// Comercio embebido. Opcional por si algun select no lo trae.
    var merchant: PartnerMerchant?

    enum CodingKeys: String, CodingKey {
        case id
        case merchantId = "merchant_id"
        case name
        case itemDescription = "description"
        case photoUrl = "photo_url"
        case pointsCost = "points_cost"
        case status
        case sortOrder = "sort_order"
        case merchant = "partner_merchants"
    }

    var merchantName: String { merchant?.name ?? "Comercio aliado" }

    /// Moneda en la que se paga: la del comercio (cashback si no viene).
    /// `pointsCost` esta en esta moneda (centavos o puntos).
    var currency: RewardCurrency { merchant?.currency ?? .cashback }

    /// "$3.50" o "150 pts".
    var formattedCost: String { currency.format(pointsCost) }
}

enum RewardRedemptionStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case emitido
    case entregado
    case cancelado
    case vencido

    var id: String { rawValue }

    /// Texto del badge en "Mis canjes".
    var displayName: String {
        switch self {
        case .emitido: return "Listo para usar"
        case .entregado: return "Entregado"
        case .cancelado: return "Cancelado"
        case .vencido: return "Vencido"
        }
    }
}

/// Origen de un canje (`reward_redemptions.source`, migracion 0040):
/// - `canje`: el usuario lo pago con su cashback o sus puntos.
/// - `regalo`: un producto gratis que le regalo MonAvi (bono); ya viene
///   emitido con su codigo y no le costo nada.
enum RewardRedemptionSource: String, Codable, Hashable {
    case canje
    case regalo

    /// Tolerante: un valor desconocido cae en `.canje`.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = RewardRedemptionSource(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .canje
    }
}

/// Un canje: el codigo de 6 caracteres que el usuario muestra en caja
/// (tabla `reward_redemptions`). Para "Mis canjes" se lee con
/// `select("*, reward_items(*, partner_merchants(*)), partner_merchants(*)")`
/// — el comercio va directo (por `merchant_id`) ademas de dentro del
/// producto, porque si el producto se pausa despues, la RLS de
/// `reward_items` lo esconde y el embed llega en null.
/// La RPC `redeem_reward` devuelve la fila sola (sin embeds); el
/// repositorio le pega el producto y el comercio que ya tenia la app.
struct RewardRedemption: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let rewardItemId: UUID
    let merchantId: UUID
    let pointsCost: Int
    let code: String
    var status: RewardRedemptionStatus
    let expiresAt: Date
    var deliveredAt: Date?
    let createdAt: Date
    var item: RewardItem?
    var merchant: PartnerMerchant?
    /// Columna `currency` (migracion 0036). Opcional: canjes viejos o
    /// selects sin la columna caen en la moneda del comercio.
    var currency: RewardCurrency? = nil
    /// Columna `source` (migracion 0040). Opcional: si no viene es `canje`.
    var source: RewardRedemptionSource? = nil
    /// Mensaje de MonAvi que acompana un regalo (`gift_message`).
    var giftMessage: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case rewardItemId = "reward_item_id"
        case merchantId = "merchant_id"
        case pointsCost = "points_cost"
        case code
        case status
        case expiresAt = "expires_at"
        case deliveredAt = "delivered_at"
        case createdAt = "created_at"
        case item = "reward_items"
        case merchant = "partner_merchants"
        case currency
        case source
        case giftMessage = "gift_message"
    }

    /// true si es un producto gratis que regalo MonAvi.
    var isGift: Bool { (source ?? .canje) == .regalo }

    /// El mensaje del regalo sin espacios, o nil si esta vacio.
    var displayGiftMessage: String? {
        guard let trimmed = giftMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Lo que se muestra como costo: "Gratis" en los regalos.
    var displayCostText: String { isGift ? "Gratis" : formattedCost }

    /// Comercio a mostrar: el directo, o el que viene dentro del producto.
    var displayMerchant: PartnerMerchant? { merchant ?? item?.merchant }

    var merchantName: String { displayMerchant?.name ?? "Comercio aliado" }

    var itemName: String { item?.name ?? "tu producto" }

    /// Moneda en la que se pago este canje.
    var displayCurrency: RewardCurrency {
        currency ?? displayMerchant?.currency ?? .cashback
    }

    /// "$3.50" o "150 pts".
    var formattedCost: String { displayCurrency.format(pointsCost) }

    /// El vencimiento real lo aplica un cron una vez al dia; mientras
    /// tanto, un codigo "emitido" que ya paso su fecha se muestra como
    /// vencido para no mandar a nadie a caja con un codigo muerto.
    func effectiveStatus(now: Date = Date()) -> RewardRedemptionStatus {
        if status == .emitido && expiresAt < now {
            return .vencido
        }
        return status
    }

    func isUsable(now: Date = Date()) -> Bool {
        effectiveStatus(now: now) == .emitido
    }
}

/// Logica pura del catalogo (sin red, sin UI) — separada para poder
/// probarla en MonAviTests.
enum RewardsMath {
    /// Cuanto le falta al usuario para poder canjear (0 si ya le alcanza),
    /// en la misma unidad que `cost` y `balance` (centavos o puntos).
    static func pointsMissing(cost: Int, balance: Int) -> Int {
        max(0, cost - max(0, balance))
    }

    static func canAfford(cost: Int, balance: Int) -> Bool {
        pointsMissing(cost: cost, balance: balance) == 0
    }

    /// Saldo que aplica a un producto: cashback (centavos) o puntos,
    /// segun la moneda del comercio.
    static func balance(for currency: RewardCurrency, cashbackCents: Int, habitPoints: Int) -> Int {
        switch currency {
        case .cashback: return cashbackCents
        case .puntos: return habitPoints
        }
    }

    static func pointsMissing(item: RewardItem, cashbackCents: Int, habitPoints: Int) -> Int {
        pointsMissing(
            cost: item.pointsCost,
            balance: balance(for: item.currency, cashbackCents: cashbackCents, habitPoints: habitPoints)
        )
    }

    static func canAfford(item: RewardItem, cashbackCents: Int, habitPoints: Int) -> Bool {
        pointsMissing(item: item, cashbackCents: cashbackCents, habitPoints: habitPoints) == 0
    }

    // MARK: - Textos

    /// "Tienes $6.50 de cashback".
    static func balanceText(cents: Int) -> String {
        "Tienes \(Cashback.format(cents: max(0, cents))) de cashback"
    }

    /// "Tienes 150 pts".
    static func pointsBalanceText(points: Int) -> String {
        "Tienes \(RewardCurrency.formatPoints(max(0, points)))"
    }

    /// "Te faltan $1.20" / "Te faltan 30 pts" — nil si ya le alcanza.
    static func missingText(cost: Int, balance: Int, currency: RewardCurrency = .cashback) -> String? {
        let missing = pointsMissing(cost: cost, balance: balance)
        guard missing > 0 else { return nil }
        return "Te faltan \(currency.format(missing))"
    }

    /// "¿Canjear Capuchino en Café X por $3.50 de cashback?" /
    /// "¿Canjear Capuchino en Café X por 150 pts?"
    static func confirmationTitle(
        itemName: String,
        merchantName: String,
        cost: Int,
        currency: RewardCurrency = .cashback
    ) -> String {
        switch currency {
        case .cashback:
            return "¿Canjear \(itemName) en \(merchantName) por \(Cashback.format(cents: cost)) de cashback?"
        case .puntos:
            return "¿Canjear \(itemName) en \(merchantName) por \(RewardCurrency.formatPoints(cost))?"
        }
    }

    /// Premios destacados para "Hoy": primero los que ya le alcanzan
    /// (del mas caro al mas barato, para que se sientan como premio), luego
    /// los que estan mas cerca de alcanzarse (menor proporcion faltante).
    static func featured(
        _ items: [RewardItem],
        cashbackCents: Int,
        habitPoints: Int,
        limit: Int = 5
    ) -> [RewardItem] {
        let affordable = items
            .filter { canAfford(item: $0, cashbackCents: cashbackCents, habitPoints: habitPoints) }
            .sorted { $0.pointsCost > $1.pointsCost }
        let pending = items
            .filter { !canAfford(item: $0, cashbackCents: cashbackCents, habitPoints: habitPoints) }
            .sorted { lhs, rhs in
                missingRatio(lhs, cashbackCents: cashbackCents, habitPoints: habitPoints)
                    < missingRatio(rhs, cashbackCents: cashbackCents, habitPoints: habitPoints)
            }
        return Array((affordable + pending).prefix(max(0, limit)))
    }

    private static func missingRatio(_ item: RewardItem, cashbackCents: Int, habitPoints: Int) -> Double {
        let missing = pointsMissing(item: item, cashbackCents: cashbackCents, habitPoints: habitPoints)
        guard item.pointsCost > 0 else { return 0 }
        return Double(missing) / Double(item.pointsCost)
    }

    /// Regalos que todavia se pueden usar (emitidos y sin vencer), del
    /// que vence primero al ultimo.
    static func activeGifts(_ redemptions: [RewardRedemption], now: Date = Date()) -> [RewardRedemption] {
        redemptions
            .filter { $0.isGift && $0.isUsable(now: now) }
            .sorted { $0.expiresAt < $1.expiresAt }
    }

    /// "Tienes 1 regalo" / "Tienes 3 regalos".
    static func giftCountText(_ count: Int) -> String {
        count == 1 ? "Tienes 1 regalo" : "Tienes \(count) regalos"
    }

    /// Lo que codifica el QR del canje:
    /// `https://monavi.maday.app/canjear?code=<CODIGO>` — el cajero lo
    /// escanea con la camara de cualquier telefono y abre la pagina de
    /// validacion con el codigo ya puesto.
    static func redeemURL(code: String, baseURL: URL = Config.redeemBaseURL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        return components.url
    }

    /// Orden del catalogo: por nombre del comercio y, dentro de cada
    /// comercio, por `sort_order` (y nombre del producto para desempatar).
    static func sorted(_ items: [RewardItem]) -> [RewardItem] {
        items.sorted { lhs, rhs in
            let lhsMerchant = lhs.merchantName.localizedLowercase
            let rhsMerchant = rhs.merchantName.localizedLowercase
            if lhsMerchant != rhsMerchant {
                return lhsMerchant < rhsMerchant
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.name.localizedLowercase < rhs.name.localizedLowercase
        }
    }

    /// Categorias distintas (sin vacias), en orden alfabetico, para los
    /// chips de filtro.
    static func categories(of items: [RewardItem]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            guard let raw = item.merchant?.category else { continue }
            let category = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !category.isEmpty, !seen.contains(category) else { continue }
            seen.insert(category)
            result.append(category)
        }
        return result.sorted { $0.localizedLowercase < $1.localizedLowercase }
    }

    static func filter(_ items: [RewardItem], category: String?) -> [RewardItem] {
        guard let category else { return items }
        return items.filter { item in
            let itemCategory = item.merchant?.category?.trimmingCharacters(in: .whitespacesAndNewlines)
            return itemCategory == category
        }
    }

    /// URL valida (http/https) a partir de un string opcional del panel.
    static func webURL(from string: String?) -> URL? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    /// "Como llegar": el enlace de mapas que puso el comercio o, si no
    /// hay, una busqueda en Apple Maps por nombre + direccion.
    static func directionsURL(name: String, address: String?, mapsUrl: String?) -> URL? {
        if let url = webURL(from: mapsUrl) {
            return url
        }
        var query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
            query += query.isEmpty ? address : ", \(address)"
        }
        guard !query.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }

    static func directionsURL(for merchant: PartnerMerchant?) -> URL? {
        guard let merchant else { return nil }
        return directionsURL(name: merchant.name, address: merchant.address, mapsUrl: merchant.mapsUrl)
    }
}
