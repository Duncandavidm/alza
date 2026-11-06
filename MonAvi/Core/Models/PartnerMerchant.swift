import Foundation

/// Comercio aliado y su oferta activa — catalogo de solo lectura para la
/// app (se administra desde el panel admin o el Table Editor, ver
/// migracion 0024_card_linked_offers.sql).
struct PartnerMerchant: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var ruc: String
    var status: String
    /// Ficha publica del comercio (migracion 0031): logo, enlace de
    /// mapas, categoria y direccion. Opcionales — el panel las llena
    /// cuando el comercio entra al catalogo de canje.
    var logoUrl: String?
    var mapsUrl: String?
    var category: String?
    var address: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ruc
        case status
        case logoUrl = "logo_url"
        case mapsUrl = "maps_url"
        case category
        case address
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum PartnerOfferType: String, Codable {
    case percent
    case fixed
}

struct PartnerMerchantOffer: Codable, Identifiable, Hashable {
    let id: UUID
    let merchantId: UUID
    var offerType: PartnerOfferType
    var value: Decimal
    var minAmount: Decimal?
    var startsAt: Date
    var endsAt: Date?
    var budgetTotalPoints: Int?
    var budgetSpentPoints: Int
    var status: String

    enum CodingKeys: String, CodingKey {
        case id
        case merchantId = "merchant_id"
        case offerType = "offer_type"
        case value
        case minAmount = "min_amount"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case budgetTotalPoints = "budget_total_points"
        case budgetSpentPoints = "budget_spent_points"
        case status
    }

    /// Texto corto para la tarjeta de la oferta ("5% en puntos" / "80
    /// puntos fijos por compra").
    var summaryText: String {
        switch offerType {
        case .percent:
            return "\(value.formatted(.number.precision(.fractionLength(0))))% en puntos"
        case .fixed:
            return "\(value.formatted(.number.precision(.fractionLength(0)))) puntos fijos por compra"
        }
    }
}

/// Lo que ve "Ofertas cerca": el comercio con su oferta activa ya unida
/// (nil si no tiene ninguna vigente ahorita).
struct PartnerOffer: Identifiable {
    let merchant: PartnerMerchant
    let offer: PartnerMerchantOffer?

    var id: UUID { merchant.id }
}
