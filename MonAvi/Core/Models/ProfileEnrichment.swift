import Foundation

/// Campos del panorama personal que se juntan en el onboarding (migracion
/// 0011_profile_enrichment_and_debts.sql) para que el consejo financiero
/// tenga mas contexto: con quien vive, cuantos dependen de el, que tan
/// arriesgado quiere invertir.
enum MaritalStatus: String, Codable, CaseIterable, Identifiable {
    case soltero
    case casado
    case unionLibre = "union_libre"
    case divorciado
    case viudo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .soltero: return "Soltero/a"
        case .casado: return "Casado/a"
        case .unionLibre: return "Union libre"
        case .divorciado: return "Divorciado/a"
        case .viudo: return "Viudo/a"
        }
    }
}

enum RiskTolerance: String, Codable, CaseIterable, Identifiable {
    case bajo
    case medio
    case alto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bajo: return "Baja — prefiero seguridad"
        case .medio: return "Media — un balance"
        case .alto: return "Alta — busco crecimiento"
        }
    }
}
