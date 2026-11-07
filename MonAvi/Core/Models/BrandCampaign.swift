import Foundation

/// Campaña de una marca ("Ofertas de marcas"): compra el producto en un
/// comercio participante, escanea la factura y, cuando la DGI la
/// verifica, el servidor acredita el bono (fuentes `marca` / `marca_puntos`
/// del ledger, ya incluidas en `points_balances`).
///
/// La RLS de `brand_campaigns` solo deja leer campañas activas y SOLO
/// estas columnas — por eso el select es explicito (ver
/// `BrandCampaign.selectColumns`); un `select()` con `*` falla.
struct BrandCampaign: Decodable, Identifiable, Hashable {
    let id: UUID
    var brand: String
    var name: String
    var description: String?
    var imageUrl: String?
    var merchantRucs: [String]
    var bonusCurrency: RewardCurrency
    /// Bono fijo por unidad: puntos, o centavos de cashback.
    var bonusPerUnit: Int?
    /// Bono porcentual sobre el monto: 1 = +1% (1¢ por cada $1).
    var bonusPercent: Double?
    var maxUnitsPerReceipt: Int?
    var startsAt: Date?
    var endsAt: Date?
    var status: String

    static let selectColumns = "id, brand, name, description, image_url, merchant_rucs, bonus_currency, bonus_per_unit, bonus_percent, max_units_per_receipt, starts_at, ends_at, status"

    enum CodingKeys: String, CodingKey {
        case id
        case brand
        case name
        case description
        case imageUrl = "image_url"
        case merchantRucs = "merchant_rucs"
        case bonusCurrency = "bonus_currency"
        case bonusPerUnit = "bonus_per_unit"
        case bonusPercent = "bonus_percent"
        case maxUnitsPerReceipt = "max_units_per_receipt"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case status
    }

    init(
        id: UUID = UUID(),
        brand: String,
        name: String,
        description: String? = nil,
        imageUrl: String? = nil,
        merchantRucs: [String] = [],
        bonusCurrency: RewardCurrency,
        bonusPerUnit: Int? = nil,
        bonusPercent: Double? = nil,
        maxUnitsPerReceipt: Int? = nil,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        status: String = "active"
    ) {
        self.id = id
        self.brand = brand
        self.name = name
        self.description = description
        self.imageUrl = imageUrl
        self.merchantRucs = merchantRucs
        self.bonusCurrency = bonusCurrency
        self.bonusPerUnit = bonusPerUnit
        self.bonusPercent = bonusPercent
        self.maxUnitsPerReceipt = maxUnitsPerReceipt
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.status = status
    }

    /// Decodificado tolerante: las fechas pueden venir como timestamp o
    /// solo fecha, y `numeric` puede llegar como numero o texto. Un campo
    /// raro no debe tumbar toda la lista.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        brand = (try? container.decode(String.self, forKey: .brand)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        imageUrl = try? container.decodeIfPresent(String.self, forKey: .imageUrl)
        merchantRucs = (try? container.decodeIfPresent([String].self, forKey: .merchantRucs)) ?? []
        bonusCurrency = (try? container.decodeIfPresent(RewardCurrency.self, forKey: .bonusCurrency)) ?? .cashback
        bonusPerUnit = Self.decodeInt(container, .bonusPerUnit)
        bonusPercent = Self.decodeDouble(container, .bonusPercent)
        maxUnitsPerReceipt = Self.decodeInt(container, .maxUnitsPerReceipt)
        startsAt = Self.decodeDate(container, .startsAt)
        endsAt = Self.decodeDate(container, .endsAt)
        status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? "active"
    }

    private static func decodeDouble(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }

    private static func decodeInt(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = decodeDouble(container, key) { return Int(value) }
        return nil
    }

    private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) { return date }
        guard let text = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return BrandCampaignText.parseDate(text)
    }
}

/// Textos de la tarjeta de una campaña de marca — logica pura (testeable).
enum BrandCampaignText {
    static let instruction = "Compra, escanea tu factura y el premio llega cuando la DGI la verifique."

    /// "+10 pts por unidad", "+25¢ por unidad", "Doble cashback",
    /// "+2¢ por cada $1", "+5 pts por cada $1". nil si la campaña no trae
    /// un bono valido.
    static func bonusText(for campaign: BrandCampaign) -> String? {
        bonusText(currency: campaign.bonusCurrency, perUnit: campaign.bonusPerUnit, percent: campaign.bonusPercent)
    }

    static func bonusText(currency: RewardCurrency, perUnit: Int?, percent: Double?) -> String? {
        if let perUnit, perUnit > 0 {
            switch currency {
            case .puntos:
                return "+\(perUnit) pts por unidad"
            case .cashback:
                return "+\(centsText(perUnit)) por unidad"
            }
        }
        if let percent, percent > 0 {
            switch currency {
            case .cashback:
                if abs(percent - 1) < 0.0001 { return "Doble cashback" }
                return "+\(number(percent))¢ por cada $1"
            case .puntos:
                return "+\(number(percent)) pts por cada $1"
            }
        }
        return nil
    }

    /// "Hasta 3 unidades por factura" / "Hasta 1 unidad por factura".
    static func unitsLimitText(_ maxUnits: Int?) -> String? {
        guard let maxUnits, maxUnits > 0 else { return nil }
        return "Hasta \(maxUnits) \(maxUnits == 1 ? "unidad" : "unidades") por factura"
    }

    /// "Válida hasta el 30 de noviembre".
    static func endsText(_ endsAt: Date?, calendar: Calendar = .current) -> String? {
        guard let endsAt else { return nil }
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "es_PA"), calendar: calendar, timeZone: calendar.timeZone)
            .day()
            .month(.wide)
        return "Válida hasta el \(endsAt.formatted(style))"
    }

    /// Centavos: menos de un dolar como "25¢", si no "$1.50".
    static func centsText(_ cents: Int) -> String {
        cents < 100 ? "\(cents)¢" : Cashback.format(cents: cents)
    }

    /// 2 -> "2", 1.5 -> "1.5", 0.25 -> "0.25" (sin depender del locale).
    static func number(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Timestamps de PostgREST ("2026-11-30T23:59:59+00:00", con o sin
    /// fracciones) o fechas sueltas ("2026-11-30").
    static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }

        let dayOnly = DateFormatter()
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.timeZone = .current
        dayOnly.dateFormat = "yyyy-MM-dd"
        return dayOnly.date(from: String(text.prefix(10)))
    }
}
