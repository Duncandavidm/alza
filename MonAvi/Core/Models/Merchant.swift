import Foundation

/// RUC -> nombre + categoria, catalogo compartido para auto-rellenar la
/// categoria de un gasto al escanear una factura DGI (modulo "Facturas
/// que suman"). Se llena a mano por David en el Table Editor de Supabase
/// (ver migracion 0022_dgi_receipts.sql) — la app solo LEE esta tabla.
struct Merchant: Codable, Identifiable, Hashable {
    let id: UUID
    let ruc: String
    var name: String
    var category: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ruc
        case name
        case category
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
