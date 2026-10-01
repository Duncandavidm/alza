import SwiftUI

/// Tipografia de marca para facturas/remisiones/recibos. No son fuentes
/// custom embebidas (eso requeriria empaquetar archivos de fuente); son
/// los "design" del sistema de SwiftUI, que ya dan variedad visual real
/// sin depender de assets adicionales.
enum BrandFont: String, Codable, CaseIterable, Identifiable {
    case `default`
    case rounded
    case serif
    case monospaced

    var id: String { rawValue }

    var design: Font.Design {
        switch self {
        case .default: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }

    var displayName: String {
        switch self {
        case .default: return "Predeterminada"
        case .rounded: return "Redondeada"
        case .serif: return "Serif"
        case .monospaced: return "Monoespaciada"
        }
    }
}

/// La marca del negocio del usuario: nombre, logo, color y tipografia
/// que se usan para pintar facturas, remisiones y recibos de pago.
struct BusinessSettings: Codable, Hashable {
    var userId: UUID
    var businessName: String?
    var logoPath: String?
    var brandColorHex: String
    var brandFont: BrandFont
    var taxId: String?
    var address: String?
    var phone: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case businessName = "business_name"
        case logoPath = "logo_path"
        case brandColorHex = "brand_color"
        case brandFont = "brand_font"
        case taxId = "tax_id"
        case address
        case phone
        case updatedAt = "updated_at"
    }

    var brandColor: Color { Color(hex: brandColorHex) ?? .accentColor }

    static func blank(userId: UUID) -> BusinessSettings {
        BusinessSettings(
            userId: userId,
            businessName: nil,
            logoPath: nil,
            brandColorHex: "#00A585",
            brandFont: .default,
            taxId: nil,
            address: nil,
            phone: nil,
            updatedAt: Date()
        )
    }
}

/// Payload de upsert (sin `updated_at`, que lo pone el trigger de la base).
struct BusinessSettingsUpsert: Encodable {
    let userId: UUID
    let businessName: String?
    let logoPath: String?
    let brandColor: String
    let brandFont: BrandFont
    let taxId: String?
    let address: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case businessName = "business_name"
        case logoPath = "logo_path"
        case brandColor = "brand_color"
        case brandFont = "brand_font"
        case taxId = "tax_id"
        case address
        case phone
    }
}
