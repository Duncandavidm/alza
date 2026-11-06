import Foundation

/// Campos del panorama personal que se juntan en el onboarding (migracion
/// 0011_profile_enrichment_and_debts.sql) para que el consejo financiero
/// tenga mas contexto: con quien vive, cuantos dependen de el, que tan
/// arriesgado quiere invertir.
enum MaritalStatus: String, Codable, CaseIterable, Identifiable, Hashable {
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

enum RiskTolerance: String, Codable, CaseIterable, Identifiable, Hashable {
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

/// Genero (opcional) del perfil — columna `profiles.gender` (migracion
/// 0031), solo para el estudio de mercado agregado y anonimo. nil = no
/// respondio.
enum ProfileGender: String, Codable, CaseIterable, Identifiable, Hashable {
    case femenino
    case masculino
    case otro
    case prefieroNoDecir = "prefiero_no_decir"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .femenino: return "Femenino"
        case .masculino: return "Masculino"
        case .otro: return "Otro"
        case .prefieroNoDecir: return "Prefiero no decir"
        }
    }
}
