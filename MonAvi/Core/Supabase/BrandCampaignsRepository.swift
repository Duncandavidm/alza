import Foundation
import Supabase

/// "Ofertas de marcas" (tabla `brand_campaigns`). La RLS solo deja leer
/// campañas activas y un set fijo de columnas: el select va explicito.
@MainActor
final class BrandCampaignsRepository {
    static let shared = BrandCampaignsRepository()
    private let supabase = SupabaseManager.shared.client
    private init() {}

    /// Campañas activas y vigentes hoy, las que vencen antes primero.
    func fetchActive(now: Date = Date()) async throws -> [BrandCampaign] {
        let rows: [BrandCampaign] = try await supabase
            .from("brand_campaigns")
            .select(BrandCampaign.selectColumns)
            .eq("status", value: "active")
            .execute()
            .value
        return BrandCampaignsRepository.current(rows, now: now)
    }

    /// Tolerante a fallas: cualquier error devuelve `[]` y la seccion
    /// simplemente no se muestra.
    func fetchActiveOrEmpty() async -> [BrandCampaign] {
        (try? await fetchActive()) ?? []
    }

    /// Filtra por fechas (por si el servidor aun no las aplica) y ordena:
    /// las que vencen antes primero, las sin fecha al final.
    nonisolated static func current(_ campaigns: [BrandCampaign], now: Date) -> [BrandCampaign] {
        campaigns
            .filter { campaign in
                (campaign.startsAt.map { $0 <= now } ?? true)
                    && (campaign.endsAt.map { $0 >= now } ?? true)
            }
            .sorted { lhs, rhs in
                switch (lhs.endsAt, rhs.endsAt) {
                case let (left?, right?): return left < right
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.brand.localizedCaseInsensitiveCompare(rhs.brand) == .orderedAscending
                }
            }
    }
}
