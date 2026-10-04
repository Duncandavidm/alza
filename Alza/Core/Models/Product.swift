import Foundation

/// Catalogo de productos/servicios con calculadora de precio: el usuario
/// pone cuanto le cuesta (precio costo) y el margen que quiere ganar, y
/// Avi calcula el precio de venta. Reutilizable al armar items de una
/// factura/remision.
///
/// Se llama "CatalogProduct" y no "Product" a proposito: StoreKit ya
/// define un tipo `Product` (la suscripcion de Avi Pro, ver
/// SubscriptionStore.swift) y, dentro del mismo modulo, un tipo propio
/// con ese nombre le gana la resolucion al de StoreKit — rompia el
/// paywall ("Value of type 'Product' has no member 'displayPrice'").
struct CatalogProduct: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    var unit: String?
    var costPrice: Decimal
    var marginPercent: Decimal
    var salePrice: Decimal
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case unit
        case costPrice = "cost_price"
        case marginPercent = "margin_percent"
        case salePrice = "sale_price"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct NewCatalogProduct: Encodable {
    let userId: UUID
    let name: String
    let unit: String?
    let costPrice: Decimal
    let marginPercent: Decimal
    let salePrice: Decimal

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case unit
        case costPrice = "cost_price"
        case marginPercent = "margin_percent"
        case salePrice = "sale_price"
    }
}

/// La calculadora en si: precio costo + margen deseado -> precio de venta.
/// Formula estandar de margen sobre precio de venta (no sobre el costo):
/// venta = costo / (1 - margen/100). Con eso, si el usuario dice "quiero
/// ganar 30% de margen", el 30% SI queda como proporcion del precio final,
/// que es como la mayoria de comercios piensan su margen.
enum PriceCalculator {
    static func salePrice(costPrice: Decimal, marginPercent: Decimal) -> Decimal {
        guard marginPercent < 100, marginPercent >= 0, costPrice >= 0 else { return costPrice }
        let divisor = 1 - (marginPercent / 100)
        guard divisor > 0 else { return costPrice }
        return costPrice / divisor
    }

    static func marginPercent(costPrice: Decimal, salePrice: Decimal) -> Decimal {
        guard salePrice > 0, costPrice >= 0 else { return 0 }
        return (1 - (costPrice / salePrice)) * 100
    }
}
