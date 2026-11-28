import Foundation
import Supabase

/// Estado de ingresos para el cashback (1.1.0, migración 0100): tope sin
/// verificar, ingreso verificado, solicitud en curso y revisión abierta.
struct IncomeStatus: Decodable, Equatable {
    let cap: Decimal
    let verifiedIncome: Decimal?
    let verifiedUntil: String?
    let income30d: Decimal
    let requestStatus: String?
    let requestNote: String?
    let inReview: Bool

    enum CodingKeys: String, CodingKey {
        case cap
        case verifiedIncome = "verified_income"
        case verifiedUntil = "verified_until"
        case income30d = "income_30d"
        case requestStatus = "request_status"
        case requestNote = "request_note"
        case inReview = "in_review"
    }

    var isVerified: Bool {
        guard verifiedIncome != nil, let verifiedUntil, let until = DgiReceiptDateFormat.formatter.date(from: verifiedUntil) else { return false }
        return until >= Calendar.current.startOfDay(for: Date())
    }

    var hasPendingRequest: Bool { requestStatus == "pendiente" }

    /// Sus ingresos del último mes pasan del tope y no los ha verificado.
    var shouldOfferVerification: Bool {
        income30d > cap && !isVerified && !hasPendingRequest
    }
}

enum IncomeDocumentKind: String, CaseIterable, Identifiable {
    case talonario, cartaTrabajo = "carta_trabajo", css, estadoCuenta = "estado_cuenta", declaracionRenta = "declaracion_renta", otro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .talonario: return L("Talonario o comprobante de pago")
        case .cartaTrabajo: return L("Carta de trabajo")
        case .css: return L("Constancia de la CSS")
        case .estadoCuenta: return L("Estado de cuenta (últimos 2 meses)")
        case .declaracionRenta: return L("Declaración de renta")
        case .otro: return L("Otro documento")
        }
    }
}

enum IncomeVerificationService {
    private static var client: SupabaseClient { SupabaseManager.shared.client }

    static func status() async throws -> IncomeStatus {
        try await client.rpc("my_income_status").execute().value
    }

    /// Sube el documento a la carpeta privada de la persona, registra la
    /// solicitud y le pide a la IA que lo lea (si falla, el panel lo revisa
    /// a mano).
    static func submit(userId: UUID, data: Data, isPDF: Bool, kind: IncomeDocumentKind) async throws {
        let path = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(isPDF ? "pdf" : "jpg")"
        try await client.storage.from("income-docs").upload(
            path,
            data: data,
            options: FileOptions(contentType: isPDF ? "application/pdf" : "image/jpeg", upsert: false)
        )
        struct Params: Encodable {
            let pPath: String
            let pKind: String
            enum CodingKeys: String, CodingKey { case pPath = "p_path", pKind = "p_kind" }
        }
        let verificationId: UUID = try await client
            .rpc("submit_income_verification", params: Params(pPath: path, pKind: kind.rawValue))
            .execute()
            .value
        struct ReadBody: Encodable {
            let verificationId: UUID
            enum CodingKeys: String, CodingKey { case verificationId = "verification_id" }
        }
        _ = try? await client.functions.invoke(
            "read-income-document",
            options: FunctionInvokeOptions(body: ReadBody(verificationId: verificationId))
        )
    }

    /// Una vez por arranque: avisa al servidor de este iPhone (revisión de
    /// muchas cuentas en el mismo teléfono).
    static func registerDevice() async {
        struct Params: Encodable {
            let pDeviceId: String
            enum CodingKeys: String, CodingKey { case pDeviceId = "p_device_id" }
        }
        _ = try? await client.rpc("register_device", params: Params(pDeviceId: DeviceIdentity.id)).execute()
    }
}
