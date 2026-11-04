import Foundation

/// "Ahorro verificado" (B2): el usuario se inscribe con un banco
/// patrocinador (consentimiento separado y revocable, nunca el numero
/// de cuenta real — solo un identificador opaco que el banco acuerda),
/// pone una meta mensual, y el banco reporta periodicamente si la
/// cumplio por SALDO PROMEDIO del mes (ver migracion
/// 0027_sponsored_savings.sql y reconcile-savings-reports). Los puntos
/// son de alto valor porque estan verificados por un tercero — a
/// diferencia de los habitos (B1), que no requieren verificacion.

enum BankPartnerStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case active
    case paused

    var id: String { rawValue }
}

struct BankPartner: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let status: BankPartnerStatus

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
    }
}

enum SavingsEnrollmentStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case active
    case revoked

    var id: String { rawValue }
}

/// `externalAccountRef` es el identificador OPACO que el banco le
/// entrega al usuario (nunca el numero de cuenta real) — lo unico que
/// MonAvi guarda para poder cruzar los reportes del banco.
struct SponsoredSavingsEnrollment: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let bankPartnerId: UUID
    var externalAccountRef: String
    var status: SavingsEnrollmentStatus
    let consentAt: Date
    var consentRevokedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case bankPartnerId = "bank_partner_id"
        case externalAccountRef = "external_account_ref"
        case status
        case consentAt = "consent_at"
        case consentRevokedAt = "consent_revoked_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct NewSponsoredSavingsEnrollment: Encodable {
    let userId: UUID
    let bankPartnerId: UUID
    let externalAccountRef: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case bankPartnerId = "bank_partner_id"
        case externalAccountRef = "external_account_ref"
    }
}

/// Revocar el consentimiento solo cambia el estado — nunca borra el
/// historial de metas/puntos ya otorgados.
struct SponsoredSavingsEnrollmentRevoke: Encodable {
    let status: SavingsEnrollmentStatus
    let consentRevokedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case consentRevokedAt = "consent_revoked_at"
    }
}

enum SavingsGoalStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case active
    case met
    case missed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: return "En curso"
        case .met: return "Cumplida"
        case .missed: return "No cumplida"
        }
    }
}

/// `periodMonth` siempre es el primer dia del mes, y se maneja como
/// String "yyyy-MM-dd" (mismo patron que `SavingsGoal.targetDate` para
/// toda columna `date` de Postgres — ver SavingsGoalDateFormat — para
/// no depender de como el decoder de supabase-swift interprete una
/// fecha sin hora, y para no desplazar el mes al formatear en una zona
/// horaria con offset negativo como Panama). El estado lo cambia
/// unicamente `reconcile-savings-reports` cuando llega el reporte del
/// banco — nunca el cliente.
struct SponsoredSavingsGoal: Codable, Identifiable, Hashable {
    let id: UUID
    let enrollmentId: UUID
    let periodMonth: String
    var targetAmount: Decimal
    var status: SavingsGoalStatus
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case enrollmentId = "enrollment_id"
        case periodMonth = "period_month"
        case targetAmount = "target_amount"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var periodMonthDate: Date { SavingsGoalDateFormat.date(from: periodMonth) }
}

struct NewSponsoredSavingsGoal: Encodable {
    let enrollmentId: UUID
    let periodMonth: String
    let targetAmount: Decimal

    enum CodingKeys: String, CodingKey {
        case enrollmentId = "enrollment_id"
        case periodMonth = "period_month"
        case targetAmount = "target_amount"
    }
}
