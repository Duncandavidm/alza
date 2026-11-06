import Foundation
import Supabase

/// Data del token de APNs -> string hex en minusculas (lo que espera
/// APNs al mandar un push).
enum PushTokenFormatter {
    static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

/// Guarda el token de notificaciones push de este dispositivo en
/// `device_push_tokens` (migracion 0031) para el usuario con sesion.
///
/// El token puede llegar ANTES de saber quien es el usuario (APNs
/// responde rapido al abrir la app), asi que se guarda en memoria (y en
/// UserDefaults) y se sube en cuanto hay un user id — `ReminderScheduler
/// .refreshAll(userId:)` llama a `sync(userId:)` cada vez que la app se
/// abre o vuelve al frente.
@MainActor
final class PushTokenService {
    static let shared = PushTokenService()

    private let supabase = SupabaseManager.shared.client
    private static let tokenDefaultsKey = "apnsDeviceToken"

    private(set) var currentToken: String?
    private var knownUserId: UUID?
    private var syncedToken: String?
    private var syncedUserId: UUID?

    private init() {
        currentToken = UserDefaults.standard.string(forKey: Self.tokenDefaultsKey)
    }

    /// APNs de desarrollo (builds Debug desde Xcode) o de produccion
    /// (TestFlight y App Store).
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private struct TokenRow: Encodable {
        let token: String
        let userId: UUID
        let environment: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case token
            case userId = "user_id"
            case environment
            case updatedAt = "updated_at"
        }
    }

    /// Lo llama el AppDelegate cada vez que iOS entrega el token.
    func didReceive(token: String) {
        currentToken = token
        UserDefaults.standard.set(token, forKey: Self.tokenDefaultsKey)
        if let userId = knownUserId {
            Task { await sync(userId: userId) }
        }
    }

    /// Recuerda al usuario y, si ya hay token, lo sube (una sola vez por
    /// combinacion token + usuario en esta sesion de la app).
    func sync(userId: UUID) async {
        knownUserId = userId
        guard let token = currentToken else { return }
        if syncedToken == token && syncedUserId == userId { return }

        let row = TokenRow(
            token: token,
            userId: userId,
            environment: Self.environment,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await supabase
                .from("device_push_tokens")
                .upsert(row, onConflict: "token")
                .execute()
            syncedToken = token
            syncedUserId = userId
        } catch {
            print("[Push] No se pudo guardar el token: \(error.localizedDescription)")
        }
    }

    /// Al cerrar sesion: borra la fila de ESTE dispositivo (mejor
    /// esfuerzo — si falla, el token queda huerfano y no pasa nada
    /// grave). Debe llamarse ANTES de `auth.signOut()`, porque la RLS
    /// exige la sesion del dueno para borrar.
    func removeCurrentToken() async {
        let token = currentToken
        knownUserId = nil
        syncedToken = nil
        syncedUserId = nil
        guard let token else { return }
        _ = try? await supabase
            .from("device_push_tokens")
            .delete()
            .eq("token", value: token)
            .execute()
    }
}
