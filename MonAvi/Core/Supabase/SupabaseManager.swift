import Foundation
import Supabase

/// Punto unico de acceso al SupabaseClient del backend de MonAvi.
final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: Config.supabaseURL,
            supabaseKey: Config.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: KeychainAuthLocalStorage(),
                    // Comportamiento nuevo del SDK: la sesion guardada se
                    // entrega siempre al abrir la app, aunque este vencida;
                    // AppState la renueva antes de usarla (ver start()).
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}
