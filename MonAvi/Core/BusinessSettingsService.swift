import Foundation
import Supabase

/// Lectura de la marca del negocio para pantallas que solo necesitan
/// pintarla (facturas, recibos), sin cargar todo el estado editable de
/// BusinessSettingsViewModel.
enum BusinessSettingsService {
    static func fetch(userId: UUID) async throws -> BusinessSettings {
        let settings: BusinessSettings? = try await SupabaseManager.shared.client
            .from("business_settings")
            .select()
            .eq("user_id", value: userId)
            .maybeSingle()
            .execute()
            .value
        return settings ?? .blank(userId: userId)
    }
}
