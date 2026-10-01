import Foundation
import Supabase

/// Punto unico de acceso al SupabaseClient del backend de Alza.
final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: Config.supabaseURL,
            supabaseKey: Config.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: KeychainAuthLocalStorage()
                )
            )
        )
    }
}
